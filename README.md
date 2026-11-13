# CampusFlow

CampusFlow is a Flutter application for helping students and campus teams understand activity around shared campus spaces. It combines account access, live crowd information, historical trends, alerts, and planning in one mobile-first interface.

> **Project status:** This is an academic prototype. Authentication and the Module 3 crowd-monitoring experience are implemented. The parking and number-plate module is part of the project plan and should be treated as in progress until its code and hardware workflow are added and validated.

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
- View the signed-in account and sign out.

The repository also includes an **optional laptop-webcam demonstration**. It detects visible people, divides the image into two virtual halves, and sends only the resulting counts for two configured zones. This is a demonstration tool, not a deployed campus sensor system.

## Project status

| Area | Status |
| --- | --- |
| Authentication and Supabase connection | Implemented; requires the project’s Supabase settings and provider configuration |
| Crowd Home, zone details, charts, favourites | Implemented; needs configured zones and live/history data |
| Alerts, reports, planner, bottom navigation | Implemented; behaviour depends on database policies and available readings |
| Laptop webcam crowd-count demo | Optional prototype; estimates visible people and may miss occluded or distant people |
| Parking occupancy and number-plate recognition | Planned/in progress; not represented as a finished feature |

## How it is organised

```text
lib/
  core/                 Authentication, navigation, preferences, shared logic
  features/
    auth/                Sign-in, sign-up, and password recovery
    welcome/             Welcome and entry flow
    onboarding/          First-use introduction
    home/                Home, zone details, planner, alerts, settings
    placeholder/         Temporary pages for unfinished areas
  widgets/               Reusable interface components
  main.dart              App startup and Supabase initialization
tools/
  sensor_simulator.py    Optional two-zone webcam demonstration
  requirements-sensor.txt
android/, ios/, web/, windows/, macos/, linux/  Flutter platform runners
```

## Technology

- Flutter and Dart
- Supabase Auth, Postgres, and Realtime
- `fl_chart` for charts
- `flutter_local_notifications` for on-device foreground alert notifications
- Optional Python webcam demo using OpenCV and Ultralytics YOLO

Dependency versions are recorded in `pubspec.yaml`, `pubspec.lock`, and `tools/requirements-sensor.txt`.

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

Realtime must be enabled for the live data source if live updates are expected. Historical charts and forecasts require readings to exist. Alert notifications in this prototype are local; closed-app push notifications are not included.

## Privacy and security

- The Flutter app contains a Supabase publishable key. Publishable keys are intended for client apps, but database security depends on correctly configured RLS and grants.
- Never commit Supabase secret/service-role keys, Google OAuth client secrets, passwords, signing keys, private certificates, or real user data.
- Do not place privileged keys in Flutter, Python distributed to users, or public CI logs.
- The webcam simulator processes frames locally and sends counts. Review and obtain appropriate consent before using any camera-based system with real people.
- Parking number-plate recognition, if implemented, will process identifying information. Define consent, retention, access controls, and applicable institutional/legal requirements before collecting real plates.

## Team collaboration

For a three-person team, assign ownership by feature area (for example, crowd monitoring, parking, and integration/testing/documentation). Work on separate branches, open pull requests for review, and coordinate shared database changes through reviewed SQL migrations or versioned setup scripts. Avoid editing the same feature files concurrently. Keep secrets and local machine configuration out of commits.

Suggested branch names: `feature/crowd-dashboard`, `feature/parking`, and `docs/project-setup`.

## Known limitations

- Live data, authentication providers, and user-specific features require a correctly configured Supabase project and RLS policies.
- The webcam demo approximates two zones by splitting one camera image; it cannot reliably count fully hidden people and does not represent actual ESP32/hardware sensors.
- Historical trends and forecasts are limited by the amount and quality of stored readings.
- Local alerts do not guarantee delivery while the app is closed.
- Parking occupancy and number-plate recognition are not claimed as complete until the module is implemented and tested.

