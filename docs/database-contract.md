# Supabase database contract

This document lists the database objects used by the current Flutter code. It is an integration checklist, not a replacement for a reviewed schema migration. The project owner must compare it with the actual Supabase schema and policies before connecting a deployment.

## Read by the app

| Object | Fields read by CampusFlow | Purpose |
| --- | --- | --- |
| `zones` | `id`, `name`, `type`, `location`, `capacity`, `amber_pct`, `red_pct`, `active` | Active campus spaces and thresholds |
| `zone_live` | `zone_id`, `count`, `queue_len`, `est_wait_min`, `level`, `updated_at` | One current measurement per zone; the app subscribes to this table and also fetches a REST snapshot |
| `readings` | `zone_id`, `ts`, `count`, `queue_len`, `est_wait_min`, `level` | Historical chart and forecast inputs |
| `favourites` | `user_id`, `zone_id` | Per-account saved zones |
| `alert_rules` | `id`, `user_id`, `zone_id`, `condition`, `threshold`, `active`, `created_at` | Per-account crowd alert rules |

## Written by the app

| Object | Write behaviour |
| --- | --- |
| `favourites` | Insert or delete the current user's zone favourite |
| `alert_rules` | Insert, update, or delete the current user's alert rule |
| `reports` | Insert `zone_id`, `reason`, and optional `comment` |

Alert history and guest favourites/alerts are stored locally with `shared_preferences` in this version.

## Optional simulator contract

`tools/sensor_simulator.py` calls `public.ingest_reading` with `p_node_id`, `p_token`, `p_count`, `p_queue_len`, and `p_ts`. The function must validate each node credential, constrain readings, and update `readings` and `zone_live` safely. The simulator then reads back the corresponding `zone_live` row to verify delivery.

The current script's default virtual zones are `cafeteria_c1` and `cafeteria_c2`, mapped to `node_c1` and `node_c2`. The raw node credentials must be supplied through local environment variables and must never be committed.

## Security requirements

- Enable RLS on every exposed table and grant only the minimum required operations.
- Scope favourites and alert rules to `auth.uid()`; users must not read or change another user's rows.
- Treat reports according to the intended guest/authenticated access model and prevent public unrestricted access to private reports.
- Check Realtime publication and database grants separately from RLS. Both must permit the intended reads while retaining row restrictions.
- Review `SECURITY DEFINER` functions carefully: restrict who can call them, validate inputs and credentials, set a safe `search_path`, and avoid exposing privileged operations to anonymous callers.
- Never put a Supabase secret/service-role key in this Flutter app or the simulator.
