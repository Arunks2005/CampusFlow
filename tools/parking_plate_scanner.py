#!/usr/bin/env python3
"""Local parking plate scanner: YOLOv11 detector + RapidOCR, without saving frames.

Required environment variables:
  CAMPUSFLOW_SUPABASE_URL, CAMPUSFLOW_SUPABASE_KEY
  CAMPUSFLOW_PARKING_CAMERA_ID, CAMPUSFLOW_PARKING_CAMERA_TOKEN
Optional:
  CAMPUSFLOW_CAMERA_SOURCE=0 (a webcam index or an RTSP/HTTP stream URL)
  CAMPUSFLOW_CAMERA_INDEX=0 (legacy webcam-index setting)
  CAMPUSFLOW_PLATE_MODEL=license-plate-finetune-v1s.onnx
  CAMPUSFLOW_PLATE_CONFIDENCE=0.35
  CAMPUSFLOW_OCR_MIN_CONFIDENCE=0.55
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


MODEL_REPO = "morsetechlab/yolov11-license-plate-detection"
DEFAULT_MODEL = "license-plate-finetune-v1s.onnx"
MIN_VOTES = 3
VOTE_WINDOW_SECONDS = 2.5
UPLOAD_COOLDOWN_SECONDS = 30
MIN_PLATE_LENGTH = 5
MAX_PLATE_LENGTH = 12


def api_request(base_url: str, api_key: str, path: str, body: dict) -> dict:
    url = f"{base_url.rstrip('/')}/rest/v1/{path}"
    request = Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "apikey": api_key,
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urlopen(request, timeout=15) as response:
        payload = response.read()
        data = json.loads(payload.decode("utf-8")) if payload else {}
        if isinstance(data, list):
            return data[0] if data else {}
        return data


def normalize_plate(value: str) -> str:
    return re.sub(r"[^A-Z0-9-]", "", value.upper())


def extract_ocr_result(result) -> list[tuple[str, float]]:
    """Support current RapidOCR output objects and older tuple/list wrappers."""
    if result is None:
        return []
    if hasattr(result, "txts"):
        texts, scores = result.txts or [], result.scores or []
        return [(str(text), float(scores[i])) for i, text in enumerate(texts) if i < len(scores)]
    if isinstance(result, tuple) and result:
        result = result[0]
    output = []
    for item in result or []:
        if isinstance(item, (tuple, list)) and len(item) >= 3:
            output.append((str(item[1]), float(item[2])))
    return output


def choose_plate(ocr, crop, cv2) -> tuple[str, float] | None:
    # Upscaling and local contrast help OCR on plates that occupy only a small
    # part of the webcam frame. Original colour crop is tried first.
    candidates = []
    for image in (crop, cv2.resize(crop, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)):
        for text, score in extract_ocr_result(ocr(image)):
            plate = normalize_plate(text)
            if MIN_PLATE_LENGTH <= len(plate) <= MAX_PLATE_LENGTH:
                candidates.append((plate, score))
        if candidates and max(score for _, score in candidates) >= 0.75:
            break
    if not candidates:
        return None
    # Prefer high-confidence strings with enough letters and digits, typical of
    # registration marks, while leaving the exact country format configurable.
    return max(candidates, key=lambda item: item[1] + min(len(item[0]), 10) * 0.006)


def main() -> int:
    base_url = os.environ.get("CAMPUSFLOW_SUPABASE_URL", "").strip()
    api_key = os.environ.get("CAMPUSFLOW_SUPABASE_KEY", "").strip()
    camera_id = os.environ.get("CAMPUSFLOW_PARKING_CAMERA_ID", "").strip()
    camera_token = os.environ.get("CAMPUSFLOW_PARKING_CAMERA_TOKEN", "").strip()
    if not all((base_url, api_key, camera_id, camera_token)):
        print("Set CAMPUSFLOW_SUPABASE_URL, CAMPUSFLOW_SUPABASE_KEY, CAMPUSFLOW_PARKING_CAMERA_ID and CAMPUSFLOW_PARKING_CAMERA_TOKEN.", file=sys.stderr)
        return 2

    try:
        import cv2
        from huggingface_hub import hf_hub_download
        from rapidocr import RapidOCR
        from ultralytics import YOLO
    except ImportError as error:
        print(f"Missing parking-scanner package: {error}\nInstall with: python -m pip install -r tools/requirements-parking.txt", file=sys.stderr)
        return 2

    os.environ.setdefault("YOLO_CONFIG_DIR", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    model_name = os.environ.get("CAMPUSFLOW_PLATE_MODEL", DEFAULT_MODEL).strip()
    try:
        model_path = hf_hub_download(repo_id=MODEL_REPO, filename=model_name)
        model = YOLO(model_path, task="detect")
        ocr = RapidOCR()
    except Exception as error:
        print(f"Could not load detector/OCR model: {error}", file=sys.stderr)
        return 2

    try:
        plate_conf = float(os.environ.get("CAMPUSFLOW_PLATE_CONFIDENCE", "0.35"))
        ocr_min_conf = float(os.environ.get("CAMPUSFLOW_OCR_MIN_CONFIDENCE", "0.55"))
    except ValueError:
        print("Confidence settings must be numeric.", file=sys.stderr)
        return 2
    if not 0.1 <= plate_conf <= 0.9 or not 0.1 <= ocr_min_conf <= 0.99:
        print("Use plate confidence 0.10–0.90 and OCR confidence 0.10–0.99.", file=sys.stderr)
        return 2

    camera_source = os.environ.get(
        "CAMPUSFLOW_CAMERA_SOURCE", os.environ.get("CAMPUSFLOW_CAMERA_INDEX", "0")
    ).strip() or "0"
    is_device_index = camera_source.isdigit()
    source = int(camera_source) if is_device_index else camera_source
    backend = cv2.CAP_DSHOW if os.name == "nt" and is_device_index else cv2.CAP_ANY
    camera = cv2.VideoCapture(source, backend) if is_device_index else cv2.VideoCapture(source)
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not camera.isOpened():
        print("Could not open the configured camera source. Check camera access, stream URL, and network connection.", file=sys.stderr)
        return 1

    votes: dict[str, deque[tuple[float, float]]] = defaultdict(deque)
    last_sent: dict[str, float] = {}
    print(f"Parking plate scanner ready using {model_name}; frames stay on this computer.")
    print("The entry/exit direction comes from this camera's Supabase configuration. Press Q to stop.")
    frame_number = 0
    try:
        cv2.namedWindow("CampusFlow parking plate scanner", cv2.WINDOW_NORMAL)
        while True:
            ok, frame = camera.read()
            if not ok:
                print("Camera stopped delivering frames.", file=sys.stderr)
                return 1
            frame_number += 1
            # Limit expensive detection to about 5 frames per second.
            if frame_number % 4 == 0:
                result = model.predict(frame, imgsz=960, conf=plate_conf, max_det=20, verbose=False)[0]
                if result.boxes is not None:
                    for box in result.boxes:
                        x1, y1, x2, y2 = (int(value) for value in box.xyxy[0].tolist())
                        h, w = frame.shape[:2]
                        x1, y1, x2, y2 = max(0, x1), max(0, y1), min(w, x2), min(h, y2)
                        if x2 <= x1 or y2 <= y1:
                            continue
                        plate_crop = frame[y1:y2, x1:x2]
                        candidate = choose_plate(ocr, plate_crop, cv2)
                        det_score = float(box.conf[0])
                        if candidate is None:
                            label, score = "Plate detected · OCR unreadable", 0.0
                        else:
                            label, ocr_score = candidate
                            score = det_score * ocr_score
                            now = time.monotonic()
                            if ocr_score >= ocr_min_conf and score >= 0.50:
                                history = votes[label]
                                history.append((now, score))
                                while history and now - history[0][0] > VOTE_WINDOW_SECONDS:
                                    history.popleft()
                                if len(history) >= MIN_VOTES and now - last_sent.get(label, 0) >= UPLOAD_COOLDOWN_SECONDS:
                                    try:
                                        response = api_request(base_url, api_key, "rpc/ingest_parking_detection", {
                                            "p_camera_id": camera_id,
                                            "p_camera_token": camera_token,
                                            "p_plate_number": label,
                                            "p_confidence": round(sum(s for _, s in history) / len(history), 4),
                                            "p_detected_at": datetime.now(timezone.utc).isoformat(),
                                        })
                                        last_sent[label] = now
                                        print(f"Supabase {response.get('status', 'OK')}: plate={label}, direction configured in DB, occupancy={response.get('current_vehicles', 'unchanged')}", flush=True)
                                    except (HTTPError, URLError, TimeoutError, ValueError) as error:
                                        detail = error.read().decode("utf-8", errors="replace") if isinstance(error, HTTPError) else str(error)
                                        print(f"Supabase send failed: {detail}", file=sys.stderr, flush=True)
                        cv2.rectangle(frame, (x1, y1), (x2, y2), (60, 210, 145), 2)
                        cv2.putText(frame, label[:32], (x1, max(22, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (60, 210, 145), 2)
            cv2.imshow("CampusFlow parking plate scanner", frame)
            if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                break
    except KeyboardInterrupt:
        pass
    finally:
        camera.release()
        cv2.destroyAllWindows()
    print("Parking scanner stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

