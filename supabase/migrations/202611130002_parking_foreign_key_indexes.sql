-- Cover the parking module's foreign keys and its active-session ordering.
create index if not exists parking_cameras_lot_id_idx
  on public.parking_cameras (lot_id);
create index if not exists parking_sessions_entry_camera_id_idx
  on public.parking_sessions (entry_camera_id);
create index if not exists parking_sessions_exit_camera_id_idx
  on public.parking_sessions (exit_camera_id);
create index if not exists parking_sessions_active_entered_idx
  on public.parking_sessions (entered_at desc)
  where exited_at is null;
create index if not exists parking_events_lot_id_idx
  on public.parking_events (lot_id);
create index if not exists parking_events_camera_id_idx
  on public.parking_events (camera_id);
drop index if exists public.parking_sessions_active_recent_idx;

