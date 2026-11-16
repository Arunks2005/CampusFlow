#!/usr/bin/env python3
"""Use the laptop webcam as a two-zone people-count demo for CampusFlow.

The camera frame is divided into left and right virtual zones. Only counts are
sent to Supabase; frames and images are not saved or uploaded.

Required environment variables:
  CAMPUSFLOW_SUPABASE_URL
  CAMPUSFLOW_SUPABASE_KEY (publishable key or legacy anon key)
  CAMPUSFLOW_NODE_TOKEN_C1 and CAMPUSFLOW_NODE_TOKEN_C2 (sensor credentials)

The same settings may be stored in a local `.env.sensor` file at the project root.
Start with `.env.sensor.example`; never commit the real `.env.sensor` file.

Optional:
  CAMPUSFLOW_CAMERA_INDEX (default: 0)
  CAMPUSFLOW_CAMERA_ZONES (default: cafeteria_c1,cafeteria_c2)
  CAMPUSFLOW_YOLO_MODEL (default: yolo26s.pt)
  CAMPUSFLOW_IMAGE_SIZE (default: 768)
  CAMPUSFLOW_DETECTION_CONF (default: 0.20)
  CAMPUSFLOW_HEADLESS=1 (run without a camera preview window)
"""

from __future__ import annotations

import json
import os
import shutil
import statistics
import sys
import threading
import time
from collections import deque
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


NODE_FOR_ZONE = {
    "cafeteria_c1": "node_c1",
    "cafeteria_c2": "node_c2",
    "lift_lobby_1": "node_l1",
    "lift_lobby_2": "node_l2",
}

SEND_INTERVAL_SECONDS = 15
# Ask for HD input, while avoiding the extra bandwidth and decode load of 1080p.
REQUESTED_FRAME_WIDTH = 1280
REQUESTED_FRAME_HEIGHT = 720
SMOOTHING_SAMPLES = 5
MAX_LOG_BYTES = 2 * 1024 * 1024


def load_local_environment() -> None:
    """Load optional project-local settings; existing process variables win."""
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    env_file = os.path.join(project_root, ".env.sensor")
    if not os.path.isfile(env_file):
        return
    with open(env_file, encoding="utf-8-sig") as settings:
        for raw_line in settings:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def is_headless() -> bool:
    return os.environ.get("CAMPUSFLOW_HEADLESS", "").strip().lower() in {
        "1", "true", "yes", "on"
    } or "--headless" in sys.argv


def configure_headless_log() -> None:
    """Redirect pythonw output to a small rotating local log file."""
    log_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sensor_simulator.log")
    backup_path = f"{log_path}.1"
    if os.path.isfile(log_path) and os.path.getsize(log_path) >= MAX_LOG_BYTES:
        if os.path.exists(backup_path):
            os.remove(backup_path)
        shutil.move(log_path, backup_path)
    stream = open(log_path, "a", encoding="utf-8", buffering=1)
    sys.stdout = stream
    sys.stderr = stream


def request_json(base_url: str, api_key: str, path: str, *, method: str = "GET", body=None):
    url = f"{base_url.rstrip('/')}/rest/v1/{path}"
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=payload,
        method=method,
        headers={
            "apikey": api_key,
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urlopen(request, timeout=30) as response:
        data = response.read()
        return json.loads(data.decode("utf-8")) if data else None


def get_json(base_url: str, api_key: str, resource: str, params: dict[str, str]):
    return request_json(base_url, api_key, f"{resource}?{urlencode(params)}")


def selected_zone_ids() -> list[str]:
    raw = os.environ.get(
        "CAMPUSFLOW_CAMERA_ZONES", "cafeteria_c1,cafeteria_c2"
    )
    zone_ids = [zone.strip() for zone in raw.split(",") if zone.strip()]
    if len(zone_ids) != 2 or len(set(zone_ids)) != 2:
        raise ValueError(
            "CAMPUSFLOW_CAMERA_ZONES must contain exactly two different zone IDs, "
            "for example cafeteria_c1,cafeteria_c2."
        )
    unknown = [zone_id for zone_id in zone_ids if zone_id not in NODE_FOR_ZONE]
    if unknown:
        raise ValueError(f"No seeded demo node is mapped to: {', '.join(unknown)}")
    return zone_ids


def send_reading(base_url: str, api_key: str, zone: dict, count: int):
    """Send the number of people visible in one camera half.

    The webcam cannot detect queue length, so it is sent as zero. Wait time in
    Supabase is therefore not a camera measurement and will show as zero.
    """
    node_id = zone["node_id"]
    expected_count = max(0, min(zone["capacity"], int(count)))
    sent_at = datetime.now(timezone.utc)
    request_json(
        base_url,
        api_key,
        "rpc/ingest_reading",
        method="POST",
        body={
            "p_node_id": node_id,
            "p_token": node_token(node_id),
            "p_count": expected_count,
            "p_queue_len": 0,
            "p_ts": sent_at.isoformat(),
        },
    )

    # Read the live row back after the RPC. This confirms the value reached the
    # same table that the Flutter Home page reads, rather than only confirming
    # that the HTTP request returned successfully.
    rows = get_json(
        base_url,
        api_key,
        "zone_live",
        {
            "select": "zone_id,count,updated_at",
            "zone_id": f"eq.{zone['id']}",
            "limit": "1",
        },
    )
    if not rows:
        raise RuntimeError(
            f"Supabase accepted the request, but zone_live has no row for {zone['id']}."
        )

    row = rows[0]
    received_count = int(row["count"])
    updated_at = datetime.fromisoformat(
        str(row["updated_at"]).replace("Z", "+00:00")
    )
    if received_count != expected_count or updated_at < sent_at.replace(microsecond=0):
        raise RuntimeError(
            f"Supabase verification failed for {zone['id']}: sent {expected_count}, "
            f"read back {received_count} at {row['updated_at']}."
        )
    return received_count, row["updated_at"]


def node_token(node_id: str) -> str:
    """Read a sensor credential from the local process environment."""
    env_name = {
        "node_c1": "CAMPUSFLOW_NODE_TOKEN_C1",
        "node_c2": "CAMPUSFLOW_NODE_TOKEN_C2",
        "node_l1": "CAMPUSFLOW_NODE_TOKEN_L1",
        "node_l2": "CAMPUSFLOW_NODE_TOKEN_L2",
    }[node_id]
    value = os.environ.get(env_name, "").strip()
    if not value:
        raise RuntimeError(
            f"Missing {env_name}. Set the sensor token locally; do not commit it."
        )
    return value


def capture_loop(camera, shared: dict, lock: threading.Lock, stop: threading.Event):
    """Continuously keep only the newest camera frame; never build a backlog."""
    while not stop.is_set():
        ok, frame = camera.read()
        if not ok:
            shared["camera_error"] = "Camera stopped delivering frames."
            stop.set()
            return
        with lock:
            shared["frame"] = frame
            shared["frame_seq"] += 1


def detection_loop(detector, shared: dict, lock: threading.Lock, stop: threading.Event,
                  image_size: int, detection_conf: float):
    """Run inference off the preview thread and always process the newest frame."""
    recent_counts = [deque(maxlen=SMOOTHING_SAMPLES) for _ in range(2)]
    smoothed_counts = [0, 0]
    last_seq = -1
    while not stop.is_set():
        with lock:
            seq = shared["frame_seq"]
            frame = shared["frame"]
            if frame is not None and seq != last_seq:
                frame = frame.copy()
        if frame is None or seq == last_seq:
            stop.wait(0.005)
            continue
        last_seq = seq
        try:
            frame_height, frame_width = frame.shape[:2]
            split_x = frame_width // 2
            overlap = max(1, frame_width // 20)
            crops = (
                (frame[:, :min(frame_width, split_x + overlap)], 0),
                (frame[:, max(0, split_x - overlap):], max(0, split_x - overlap)),
            )
            boxes = []
            counts = [0, 0]
            for bucket, (crop, offset_x) in enumerate(crops):
                prediction = detector.predict(
                    crop,
                    classes=[0],
                    conf=detection_conf,
                    imgsz=image_size,
                    max_det=100,
                    verbose=False,
                )[0]
                if prediction.boxes is None:
                    continue
                coordinates = prediction.boxes.xyxy.cpu().tolist()
                confidences = prediction.boxes.conf.cpu().tolist()
                for (x1, y1, x2, y2), confidence in zip(coordinates, confidences):
                    x1, y1, x2, y2 = map(int, (x1 + offset_x, y1, x2 + offset_x, y2))
                    center_x = (x1 + x2) // 2
                    if (bucket == 0 and center_x >= split_x) or (bucket == 1 and center_x < split_x):
                        continue
                    counts[bucket] += 1
                    boxes.append((x1, y1, x2, y2, float(confidence)))
            for index in range(2):
                recent_counts[index].append(counts[index])
                smoothed_counts[index] = round(statistics.median(recent_counts[index]))
            with lock:
                shared["boxes"] = boxes
                shared["counts"] = smoothed_counts.copy()
                shared["detected_at"] = time.monotonic()
        except Exception as error:
            shared["detection_error"] = str(error)
            stop.set()
            return


def upload_loop(base_url: str, api_key: str, zones: list[dict], shared: dict,
                lock: threading.Lock, stop: threading.Event):
    """Upload counts away from the UI loop so network delays do not freeze video."""
    while not stop.wait(SEND_INTERVAL_SECONDS):
        with lock:
            counts = shared["counts"].copy()
        for index, zone in enumerate(zones):
            try:
                received_count, updated_at = send_reading(
                    base_url, api_key, zone, counts[index]
                )
                print(
                    f"DB OK: {zone['id']} count={received_count}, updated_at={updated_at}",
                    flush=True,
                )
            except Exception as error:
                print(f"Supabase send failed for {zone['id']}: {error}", file=sys.stderr, flush=True)


def main() -> int:
    load_local_environment()
    headless = is_headless()
    base_url = os.environ.get("CAMPUSFLOW_SUPABASE_URL", "").strip()
    api_key = os.environ.get("CAMPUSFLOW_SUPABASE_KEY", "").strip()
    if not base_url or not api_key:
        print(
            "Set CAMPUSFLOW_SUPABASE_URL and CAMPUSFLOW_SUPABASE_KEY first.",
            file=sys.stderr,
        )
        return 2

    try:
        import cv2
    except ImportError:
        print(
            "OpenCV is not installed. Run: "
            "python -m pip install -r tools/requirements-sensor.txt",
            file=sys.stderr,
        )
        return 2

    try:
        # Keep Ultralytics settings inside the project instead of requiring
        # write access to the Windows-wide AppData\Roaming directory.
        os.environ.setdefault(
            "YOLO_CONFIG_DIR",
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        )
        from ultralytics import YOLO
    except ImportError:
        print(
            "The YOLO detector is not installed. Run: "
            "python -m pip install -r tools/requirements-sensor.txt",
            file=sys.stderr,
        )
        return 2

    try:
        zone_ids = selected_zone_ids()
        all_zones = get_json(
            base_url,
            api_key,
            "zones",
            {"select": "id,name,type,capacity", "active": "eq.true"},
        )
        zones_by_id = {row["id"]: row for row in all_zones}
        zones = []
        for zone_id in zone_ids:
            if zone_id not in zones_by_id:
                raise ValueError(f"Zone '{zone_id}' is missing or inactive in Supabase.")
            zone = dict(zones_by_id[zone_id])
            zone["node_id"] = NODE_FOR_ZONE[zone_id]
            zones.append(zone)

        camera_index = int(os.environ.get("CAMPUSFLOW_CAMERA_INDEX", "0"))
        backend = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY
        camera = cv2.VideoCapture(camera_index, backend)
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, REQUESTED_FRAME_WIDTH)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, REQUESTED_FRAME_HEIGHT)
        camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        if not camera.isOpened():
            print(
                f"Could not open camera {camera_index}. Check Windows camera privacy "
                "permission, close other camera apps, or try CAMPUSFLOW_CAMERA_INDEX=1.",
                file=sys.stderr,
            )
            return 1

        model_path = os.environ.get("CAMPUSFLOW_YOLO_MODEL", "yolo26s.pt").strip()
        if not model_path:
            model_path = "yolo26s.pt"
        image_size = int(os.environ.get("CAMPUSFLOW_IMAGE_SIZE", "768"))
        detection_conf = float(os.environ.get("CAMPUSFLOW_DETECTION_CONF", "0.20"))
        if image_size < 640:
            raise ValueError("CAMPUSFLOW_IMAGE_SIZE must be at least 640.")
        if not 0.05 <= detection_conf <= 0.90:
            raise ValueError("CAMPUSFLOW_DETECTION_CONF must be between 0.05 and 0.90.")
        print(f"Loading YOLO person model: {model_path}", flush=True)
        try:
            detector = YOLO(model_path)
        except Exception as error:
            camera.release()
            print(
                f"Could not load YOLO model '{model_path}': {error}\n"
                "On first run, check internet access so the model can download, "
                "or set CAMPUSFLOW_YOLO_MODEL to a local .pt file.",
                file=sys.stderr,
            )
            return 2
        actual_width = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_height = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))

        print("Webcam YOLO person-count simulator started.")
        print(f"Detector: {model_path}, inference size: {image_size}, confidence: {detection_conf:.2f}")
        print(f"Camera resolution: {actual_width}x{actual_height} (requested 1280x720).")
        if actual_width < 1280 or actual_height < 720:
            print("This camera is providing below-HD video; small/distant people may be missed.")
        print(f"Left half → {zones[0]['name']} ({zones[0]['id']})")
        print(f"Right half → {zones[1]['name']} ({zones[1]['id']})")
        print("Only these two zones will receive readings.")
        print("Camera frames stay on this laptop; only person counts are sent.")
        print(
            "Green boxes show detected people. The left/right halves must each "
            "show the actual area represented by that zone."
        )
        print("Counts are camera estimates; a fully hidden person cannot be seen by one camera.")
        print("Preview, detection, and Supabase uploads run separately so slow inference/network calls do not freeze the camera view.")
        print("Press Q in the camera preview or Ctrl+C here to stop.")
        print("Note: queue length is not measured by the webcam and is sent as 0.")

        shared = {
            "frame": None,
            "frame_seq": 0,
            "boxes": [],
            "counts": [0, 0],
            "detected_at": 0.0,
            "camera_error": None,
            "detection_error": None,
        }
        lock = threading.Lock()
        stop = threading.Event()
        workers = [
            threading.Thread(target=capture_loop, args=(camera, shared, lock, stop), daemon=True),
            threading.Thread(
                target=detection_loop,
                args=(detector, shared, lock, stop, image_size, detection_conf),
                daemon=True,
            ),
            threading.Thread(
                target=upload_loop,
                args=(base_url, api_key, zones, shared, lock, stop),
                daemon=True,
            ),
        ]
        for worker in workers:
            worker.start()

        if not headless:
            cv2.namedWindow("CampusFlow two-zone YOLO person simulator", cv2.WINDOW_NORMAL)
            cv2.resizeWindow("CampusFlow two-zone YOLO person simulator", 1000, 650)
        else:
            print("Headless mode: no preview window; status is written to tools/sensor_simulator.log.")
        try:
            while not stop.is_set():
                with lock:
                    frame = (
                        shared["frame"].copy()
                        if not headless and shared["frame"] is not None
                        else None
                    )
                    boxes = shared["boxes"].copy() if not headless else []
                    counts = shared["counts"].copy()
                    camera_error = shared["camera_error"]
                    detection_error = shared["detection_error"]
                if camera_error or detection_error:
                    print(camera_error or f"Detector stopped: {detection_error}", file=sys.stderr)
                    break
                if headless:
                    stop.wait(0.2)
                    continue
                if frame is not None:
                    frame_height, frame_width = frame.shape[:2]
                    split_x = frame_width // 2
                    for x1, y1, x2, y2, confidence in boxes:
                        cv2.rectangle(frame, (x1, y1), (x2, y2), (65, 190, 125), 2)
                        cv2.putText(frame, f"person {confidence:.2f}", (x1, max(18, y1 - 6)),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (65, 190, 125), 2)
                    cv2.line(frame, (split_x, 0), (split_x, frame_height), (255, 210, 40), 2)
                    cv2.putText(frame, f"LEFT: {zones[0]['name']} | people: {counts[0]}",
                                (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
                    cv2.putText(frame, f"RIGHT: {zones[1]['name']} | people: {counts[1]}",
                                (split_x + 10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
                    age = time.monotonic() - detected_at if detected_at else 0.0
                    status = f"Detection updated {age:.1f}s ago" if detected_at else "Detecting..."
                    cv2.putText(frame, status, (12, frame_height - 14),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
                    if frame_width > 1100:
                        preview_height = max(1, int(frame_height * 1100 / frame_width))
                        frame = cv2.resize(frame, (1100, preview_height), interpolation=cv2.INTER_AREA)
                    cv2.imshow("CampusFlow two-zone YOLO person simulator", frame)
                if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                    break
        finally:
            stop.set()
            for worker in workers:
                worker.join(timeout=1.0)
            camera.release()
            if not headless:
                cv2.destroyAllWindows()

        print("Webcam simulator stopped.")
        return 0
    except KeyboardInterrupt:
        print("Webcam simulator stopped.")
        return 0
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        print(f"Supabase returned HTTP {error.code}: {detail}", file=sys.stderr)
        return 1
    except (URLError, TimeoutError) as error:
        print(f"Could not reach Supabase: {error}", file=sys.stderr)
        return 1
    except RuntimeError as error:
        print(f"Supabase verification failed: {error}", file=sys.stderr)
        return 1
    except (ValueError, KeyError) as error:
        print(f"Simulator configuration error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    load_local_environment()
    if is_headless():
        configure_headless_log()
    raise SystemExit(main())

