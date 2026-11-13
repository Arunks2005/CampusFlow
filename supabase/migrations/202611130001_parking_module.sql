-- CampusFlow parking module.
-- Plate/session data is admin-only; only anonymous occupancy is public.

create table if not exists public.parking_lots (
  id text primary key,
  name text not null,
  location text not null default '',
  capacity integer not null check (capacity > 0),
  current_vehicles integer not null default 0 check (current_vehicles >= 0),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint parking_lots_current_not_over_capacity
    check (current_vehicles <= capacity)
);

create table if not exists public.parking_cameras (
  id text primary key,
  lot_id text not null references public.parking_lots(id) on delete cascade,
  direction text not null check (direction in ('entry', 'exit')),
  token_hash text not null,
  enabled boolean not null default true,
  last_seen timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists parking_cameras_lot_id_idx on public.parking_cameras (lot_id);

create table if not exists public.parking_sessions (
  id bigint generated always as identity primary key,
  lot_id text not null references public.parking_lots(id),
  plate_number text not null check (plate_number ~ '^[A-Z0-9-]{5,12}$'),
  entered_at timestamptz not null default now(),
  exited_at timestamptz,
  last_seen timestamptz not null default now(),
  entry_confidence numeric(5,4) not null check (entry_confidence between 0 and 1),
  exit_confidence numeric(5,4) check (exit_confidence between 0 and 1),
  entry_camera_id text not null references public.parking_cameras(id),
  exit_camera_id text references public.parking_cameras(id),
  constraint parking_sessions_exit_after_entry check (exited_at is null or exited_at >= entered_at)
);

create unique index if not exists parking_sessions_one_active_plate_per_lot
  on public.parking_sessions (lot_id, plate_number)
  where exited_at is null;
create index if not exists parking_sessions_entry_camera_id_idx
  on public.parking_sessions (entry_camera_id);
create index if not exists parking_sessions_exit_camera_id_idx
  on public.parking_sessions (exit_camera_id);
create index if not exists parking_sessions_active_entered_idx
  on public.parking_sessions (entered_at desc)
  where exited_at is null;

create table if not exists public.parking_events (
  id bigint generated always as identity primary key,
  lot_id text not null references public.parking_lots(id),
  camera_id text not null references public.parking_cameras(id),
  event_type text not null check (event_type in ('entry', 'exit')),
  plate_number text not null check (plate_number ~ '^[A-Z0-9-]{5,12}$'),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  detected_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists parking_events_recent_idx
  on public.parking_events (detected_at desc);
create index if not exists parking_events_lot_id_idx on public.parking_events (lot_id);
create index if not exists parking_events_camera_id_idx on public.parking_events (camera_id);

alter table public.parking_lots enable row level security;
alter table public.parking_cameras enable row level security;
alter table public.parking_sessions enable row level security;
alter table public.parking_events enable row level security;

drop policy if exists "public can read active parking totals" on public.parking_lots;
create policy "public can read active parking totals"
  on public.parking_lots for select to anon, authenticated
  using (active);

drop policy if exists "admins read parking cameras" on public.parking_cameras;
create policy "admins read parking cameras"
  on public.parking_cameras for select to authenticated
  using (public.is_admin());
drop policy if exists "admins read parking sessions" on public.parking_sessions;
create policy "admins read parking sessions"
  on public.parking_sessions for select to authenticated
  using (public.is_admin());
drop policy if exists "admins read parking events" on public.parking_events;
create policy "admins read parking events"
  on public.parking_events for select to authenticated
  using (public.is_admin());

grant select on public.parking_lots to anon, authenticated;
grant select on public.parking_cameras, public.parking_sessions, public.parking_events to authenticated;
revoke all on public.parking_cameras, public.parking_sessions, public.parking_events from anon;
revoke insert, update, delete, truncate, references, trigger on public.parking_lots from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.parking_cameras, public.parking_sessions, public.parking_events from anon, authenticated;

insert into public.parking_lots (id, name, location, capacity)
values ('main_parking', 'Main parking', 'Set the real location and capacity in Supabase', 50)
on conflict (id) do nothing;

create or replace function public.ingest_parking_detection(
  p_camera_id text,
  p_camera_token text,
  p_plate_number text,
  p_confidence numeric,
  p_detected_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_camera public.parking_cameras%rowtype;
  v_plate text;
  v_detected_at timestamptz := coalesce(p_detected_at, now());
  v_session_id bigint;
  v_current integer;
begin
  if p_camera_id is null or length(p_camera_id) > 80
     or p_camera_token is null or length(p_camera_token) < 24 then
    raise exception 'Invalid camera credentials';
  end if;

  v_plate := upper(regexp_replace(coalesce(p_plate_number, ''), '[^A-Za-z0-9-]', '', 'g'));
  if v_plate !~ '^[A-Z0-9-]{5,12}$' then
    raise exception 'Plate text is not in an accepted format';
  end if;
  if p_confidence is null or p_confidence < 0.50 or p_confidence > 1 then
    raise exception 'Detection confidence must be between 0.50 and 1.00';
  end if;
  if v_detected_at < now() - interval '10 minutes'
     or v_detected_at > now() + interval '1 minute' then
    raise exception 'Detection timestamp is outside the accepted time window';
  end if;

  select c.* into v_camera
  from public.parking_cameras c
  where c.id = p_camera_id
    and c.enabled
    and c.token_hash = encode(extensions.digest(p_camera_token, 'sha256'), 'hex');
  if not found then
    raise exception 'Camera is not registered, disabled, or token is invalid';
  end if;

  -- Lock the lot row so simultaneous cameras cannot overcount the same plate.
  select l.current_vehicles into v_current
  from public.parking_lots l
  where l.id = v_camera.lot_id and l.active
  for update;
  if not found then
    raise exception 'Parking lot is inactive or missing';
  end if;

  -- Ignore repeated frames from the same camera for a short debounce period.
  if exists (
    select 1 from public.parking_events e
    where e.camera_id = v_camera.id
      and e.event_type = v_camera.direction
      and e.plate_number = v_plate
      and e.detected_at > now() - interval '30 seconds'
  ) then
    update public.parking_cameras set last_seen = now() where id = v_camera.id;
    return jsonb_build_object('status', 'duplicate', 'plate', v_plate, 'current_vehicles', v_current);
  end if;

  insert into public.parking_events (lot_id, camera_id, event_type, plate_number, confidence, detected_at)
  values (v_camera.lot_id, v_camera.id, v_camera.direction, v_plate, p_confidence, v_detected_at);

  if v_camera.direction = 'entry' then
    select s.id into v_session_id from public.parking_sessions s
    where s.lot_id = v_camera.lot_id and s.plate_number = v_plate and s.exited_at is null
    for update;
    if found then
      update public.parking_sessions set last_seen = now() where id = v_session_id;
    else
      insert into public.parking_sessions (lot_id, plate_number, entry_confidence, entry_camera_id)
      values (v_camera.lot_id, v_plate, p_confidence, v_camera.id);
      update public.parking_lots
      set current_vehicles = least(capacity, current_vehicles + 1), updated_at = now()
      where id = v_camera.lot_id
      returning current_vehicles into v_current;
    end if;
  else
    select s.id into v_session_id from public.parking_sessions s
    where s.lot_id = v_camera.lot_id and s.plate_number = v_plate and s.exited_at is null
    order by s.entered_at desc limit 1
    for update;
    if found then
      update public.parking_sessions
      set exited_at = greatest(v_detected_at, entered_at), last_seen = now(),
          exit_confidence = p_confidence, exit_camera_id = v_camera.id
      where id = v_session_id;
      update public.parking_lots
      set current_vehicles = greatest(0, current_vehicles - 1), updated_at = now()
      where id = v_camera.lot_id
      returning current_vehicles into v_current;
    end if;
  end if;

  update public.parking_cameras set last_seen = now() where id = v_camera.id;
  return jsonb_build_object('status', 'recorded', 'event', v_camera.direction,
    'plate', v_plate, 'current_vehicles', v_current);
end;
$function$;

revoke all on function public.ingest_parking_detection(text, text, text, numeric, timestamptz) from public;
grant execute on function public.ingest_parking_detection(text, text, text, numeric, timestamptz) to anon;

do $publication$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'parking_lots') then
      execute 'alter publication supabase_realtime add table public.parking_lots';
    end if;
  end if;
end;
$publication$;

