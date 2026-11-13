# CampusFlow

CampusFlow is a Flutter application for helping students and campus teams understand activity around shared campus spaces. It combines account access, live crowd information, historical trends, alerts, and planning in one mobile-first interface.

> **Project status:** This is an academic prototype. Authentication, lift/cafeteria crowd monitoring, and the first parking dashboard/scanner workflow are implemented. Validate camera placement, OCR quality, Supabase settings, and local privacy rules before using it operationally.

## Contents

- [What it does](#what-it-does)
- [Project status](#project-status)
- [How it is organised](#how-it-is-organised)
- [Technology](#technology)
- [Run the Flutter app](#run-the-flutter-app)
- [Optional webcam simulator](#optional-webcam-simulator)
- [Supabase setup](#supabase-setup)
- [Privacy and security](#privacy-and-security)
- [Team collaboration](#team-collaboration)
- [Known limitations](#known-limitations)

## What it does

- Sign up, sign in, password recovery, and persistent Supabase authentication.
- Show live crowd status for configured campus zones, with favourites, filters, sorting, and recent-update indicators.
- Open zone details with current statistics, historical charts, and estimated quieter periods.
- Create and manage crowd alerts, view alert history, and receive local notifications while the app is running.
- Plan a cafeteria or lift visit using available historical readings.
- Submit a report about a zone reading.
- View/edit the signed-in display name, see the sign-in method, and sign out.
- View separate Lift Lobby, Cafeteria, and Parking areas from the bottom navigation.
- Show live parking availability to users, with plate/session history visible only to administrators.

The repository also includes an **optional laptop-webcam demonstration**. It detects visible people, divides the image into two virtual halves, and sends only the resulting counts for two configured zones. This is a demonstration tool, not a deployed campus sensor system.

## Project status

| Area | Status |
| --- | --- |
| Authentication and Supabase connection | Implemented; requires the project’s Supabase settings and provider configuration |
| Crowd Home, zone details, charts, favourites | Implemented; needs configured zones and live/history data |
| Alerts, reports, planner, bottom navigation | Implemented; behaviour depends on database policies and available readings |
| Laptop webcam crowd-count demo | Optional prototype; estimates visible people and may miss occluded or distant people |
| Parking dashboard and separate plate scanner | Implemented as an academic prototype; needs camera credentials and real-world validation |

## How it is organised

```text
lib/
  core/                 Authentication, navigation, preferences, shared logic
  features/
    auth/                Sign-in, sign-up, and password recovery
    welcome/             Welcome and entry flow
    onboarding/          First-use introduction
    home/                Home, zone details, planner, alerts, settings
    parking/             Parking availability and admin-only plate/session history
    placeholder/         Temporary pages for unfinished areas
  widgets/               Reusable interface components
  main.dart              App startup and Supabase initialization
tools/
  sensor_simulator.py    Optional two-zone webcam demonstration
  requirements-sensor.txt
  parking_plate_scanner.py  Separate parking plate detector + OCR prototype
  requirements-parking.txt
supabase/migrations/      Parking tables, access policies, and camera-ingestion RPC
android/, ios/, web/, windows/, macos/, linux/  Flutter platform runners
```

## Technology

- Flutter and Dart
- Supabase Auth, Postgres, and Realtime
- `fl_chart` for charts
- `flutter_local_notifications` for on-device foreground alert notifications
- Optional Python webcam demo using OpenCV and Ultralytics YOLO

Flutter dependency versions are recorded in `pubspec.yaml` and `pubspec.lock`. The crowd-count and plate-scanner Python dependencies are kept in separate requirement files.

## Run the Flutter app

### Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`
- Android Studio/Android SDK or another configured Flutter target
- A Supabase project configured for this app

### Steps

1. Clone the repository and open its folder.
2. Review `lib/core/supabase_config.dart`. Set the project URL and **publishable** key for your own Supabase project, or update the app to load them from your chosen local configuration method.
3. In Supabase, create/configure the tables, functions, Realtime publication, Auth providers, and row-level security policies expected by the app. Do not use a service-role or secret key in Flutter.
4. From the project folder run:

   ```powershell
   flutter pub get
   flutter run
   ```

Google sign-in also requires Google OAuth credentials and matching callback/redirect settings in Google Cloud and Supabase. Credentials are configured in the provider dashboard; never commit an OAuth client secret.

> Database schema and RLS are deployment-specific. Before connecting a new Supabase project, inspect the queries and repository methods in `lib/features/home/campus_data.dart` and confirm that every exposed table has appropriate RLS policies. Do not make tables publicly writable to get the app working.

## Optional webcam simulator

The simulator uses a webcam connected to the computer running the script. By default it maps the left and right halves of the image to `cafeteria_c1` and `cafeteria_c2`. It sends aggregate counts only; frames are not saved or uploaded by the script. The camera preview is local to the computer.

1. Install Python and create/activate a virtual environment.
2. Install the optional dependencies:

   ```powershell
   python -m venv .venv-sensor
   .\.venv-sensor\Scripts\Activate.ps1
   python -m pip install -r .\tools\requirements-sensor.txt
   ```

3. Set the Supabase project URL, a publishable/legacy anon key, and each configured sensor's raw token in the current PowerShell session (use the credentials configured for your `nodes`; never use a service-role/secret key):

   ```powershell
   $env:CAMPUSFLOW_SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co'
   $env:CAMPUSFLOW_SUPABASE_KEY = 'YOUR-PUBLISHABLE-OR-ANON-KEY'
   $env:CAMPUSFLOW_NODE_TOKEN_C1 = 'YOUR_NODE_C1_TOKEN'
   $env:CAMPUSFLOW_NODE_TOKEN_C2 = 'YOUR_NODE_C2_TOKEN'
   ```

4. Start the simulator:

   ```powershell
   python .\tools\sensor_simulator.py
   ```

The script reports successful database updates in its terminal. Compare the reported zone/count and timestamp with the corresponding `zone_live` record and app card. Press **Q** in the preview or **Ctrl+C** in the terminal to stop.

The webcam prototype is an estimate, not an accuracy guarantee. Results depend on camera placement, lighting, resolution, distance, occlusion, and the detector model. It is not suitable for safety-critical occupancy decisions. The demo's virtual image halves are not physical zone sensors. Sensor tokens were previously embedded in the local simulator source and have been removed from this repository. If those values were ever shared outside your private development setup or reused elsewhere, rotate them in Supabase; otherwise provide the configured raw node tokens through local environment variables. The script no longer contains sensor tokens.

## Supabase setup

The app expects the Supabase database objects and policies referenced by its repository code. At a minimum, review the live zone data, zone metadata, readings/history, favourites, alert rules, and reports used in `lib/features/home/campus_data.dart`. The simulator calls the configured ingestion endpoint/function. Confirm the expected schema and function signature against your own Supabase project before running it.

### Parking schema and access

Apply the SQL files under `supabase/migrations/` to the CampusFlow project in filename order. The first creates separate `parking_lots`, `parking_cameras`, `parking_sessions`, and `parking_events` tables; the second adds indexes for their relations and the active-session list. The seeded `main_parking` row is a placeholder: change its name, location, and capacity to match the actual car park. The app reads only current lot counts for ordinary users; session/plate/event data is RLS-protected for admin accounts. The first migration also registers `parking_lots` for Realtime when that publication is available.

Register each physical camera in `parking_cameras` with an entry or exit direction and a SHA-256 token hash. Keep the raw camera token on the scanner computer only. Example SQL to add one after generating a long random token locally:

```sql
insert into public.parking_cameras (id, lot_id, direction, token_hash)
values ('gate_entry_1', 'main_parking', 'entry', 'PASTE_SHA256_HASH_HERE');
```

Generate a token hash in PowerShell without putting the raw token in project files:

```powershell
$token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$bytes = [System.Text.Encoding]::UTF8.GetBytes($token)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
$sha.Dispose()
"Save this token on the scanner: $token"
"Put this hash in Supabase: $hash"
```

Copy the token and hash to a secure temporary place before closing that terminal. For an exit gate, create a separate camera row with a distinct ID, direction `exit`, and its own token/hash. Enable admin access by assigning the existing `profiles.role = 'admin'` role only to a trusted operator.

### Parking scanner setup (Windows)

The scanner uses the linked YOLOv11 model to locate plate rectangles and RapidOCR to read text. It does not save or upload frames. It runs on a computer that can open a local webcam/USB camera or an OpenCV-compatible RTSP/HTTP CCTV stream; stream access, firewall, and network setup are separate from the Flutter app.

1. Create a separate environment so the crowd simulator dependencies stay independent. Your regular Python 3.14 installation can be used with current compatible wheels; if `pip` reports that a package has no matching wheel, install Python 3.12 or 3.13 and repeat these steps with that interpreter:

   ```powershell
   python -m venv .venv-parking
   .\.venv-parking\Scripts\Activate.ps1
   python -m pip install --upgrade pip
   python -m pip install -r .\tools\requirements-parking.txt
   ```

2. Set the Supabase URL, publishable key, camera ID, and that camera’s raw token in the same PowerShell window. Never use a Supabase secret/service-role key:

   ```powershell
   $env:CAMPUSFLOW_SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co'
   $env:CAMPUSFLOW_SUPABASE_KEY = 'YOUR-PUBLISHABLE-OR-ANON-KEY'
   $env:CAMPUSFLOW_PARKING_CAMERA_ID = 'gate_entry_1'
   $env:CAMPUSFLOW_PARKING_CAMERA_TOKEN = 'THE-RAW-TOKEN-FOR-THIS-CAMERA'
   # For CCTV, use its RTSP or HTTP stream URL instead of the default webcam:
   # $env:CAMPUSFLOW_CAMERA_SOURCE = 'rtsp://CAMERA-ADDRESS/STREAM-PATH'
   ```

3. Start the scanner:

   ```powershell
   python .\tools\parking_plate_scanner.py
   ```

   On first run it downloads the small `v1s` ONNX detector from Hugging Face. The preview draws plate boxes and the OCR guess. It waits for a plate to be read consistently across three frames before sending it. A successful send prints `Supabase recorded` or `Supabase duplicate`; then check `parking_events`, the active `parking_sessions`, and the Parking tab’s current count. Press **Q** to stop. The local preview may show uncertain OCR guesses; do not treat them as verified identity without an operator review.

4. Set the real lot location/capacity in Supabase before relying on the displayed empty-space number. The migration seeds an example capacity of 50 only so the UI is visible immediately.

The linked model is a **detector**, not an OCR reader. Its model page says the public dataset has train/test contamination, so its reported precision/recall may overstate field accuracy; small/distant plates, glare, motion blur, non-Latin and unusual plate formats may fail. Validate on consented, representative footage and tune thresholds before any real deployment. The model is published under **AGPL-3.0**; review that license before distributing a product that incorporates it. No weights or footage belong in this repository.

Realtime must be enabled for the live data source if live updates are expected. Historical charts and forecasts require readings to exist. Alert notifications in this prototype are local; closed-app push notifications are not included.

## Privacy and security

- The Flutter app contains a Supabase publishable key. Publishable keys are intended for client apps, but database security depends on correctly configured RLS and grants.
- Never commit Supabase secret/service-role keys, Google OAuth client secrets, passwords, signing keys, private certificates, or real user data.
- Do not place privileged keys in Flutter, Python distributed to users, or public CI logs.
- The webcam simulator processes frames locally and sends counts. Review and obtain appropriate consent before using any camera-based system with real people.
- The parking scanner processes frames locally but sends recognized plate text to Supabase. Plate numbers identify people/vehicles: restrict operator access, set a retention period, obtain institutional approval/consent where required, and follow applicable local rules before collecting real data. The migration keeps individual plate events and sessions admin-only; it does not yet implement automatic record expiry.

## Team collaboration

For a three-person team, assign ownership by feature area (for example, crowd monitoring, parking, and integration/testing/documentation). Work on separate branches, open pull requests for review, and coordinate shared database changes through reviewed SQL migrations or versioned setup scripts. Avoid editing the same feature files concurrently. Keep secrets and local machine configuration out of commits.

Suggested branch names: `feature/crowd-dashboard`, `feature/parking`, and `docs/project-setup`.

## Known limitations

- Live data, authentication providers, and user-specific features require a correctly configured Supabase project and RLS policies.
- The webcam demo approximates two zones by splitting one camera image; it cannot reliably count fully hidden people and does not represent actual ESP32/hardware sensors.
- Historical trends and forecasts are limited by the amount and quality of stored readings.
- Local alerts do not guarantee delivery while the app is closed.
- Parking occupancy and number-plate recognition are not claimed as complete until the module is implemented and tested.

