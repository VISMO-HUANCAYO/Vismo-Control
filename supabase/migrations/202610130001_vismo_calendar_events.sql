-- Vismo: calendario independiente. No modifica tablas ni funciones de asistencia.
create table if not exists public.vismo_calendar_events (
 id uuid primary key default gen_random_uuid(),
 title text not null check (length(trim(title)) between 1 and 180),
 description text not null default '',
 category text not null default 'laboral' check (category in ('laboral','reunion','capacitacion','inspeccion','fecha_especial','cumpleanos','aniversario','celebracion','otro')),
 start_date date not null,
 end_date date not null,
 all_day boolean not null default true,
 start_time time,
 end_time time,
 visibility text not null default 'assigned' check (visibility in ('team','assigned')),
 assigned_user_ids uuid[] not null default '{}',
 recurrence text not null default 'none' check (recurrence in ('none','daily','weekly','monthly','yearly')),
 recurrence_until date,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint vismo_calendar_dates_valid check (end_date >= start_date),
 constraint vismo_calendar_recurrence_valid check (recurrence <> 'none' or recurrence_until is null or recurrence_until >= start_date)
);
create index if not exists vismo_calendar_events_dates_idx on public.vismo_calendar_events (start_date,end_date);
create index if not exists vismo_calendar_events_assigned_idx on public.vismo_calendar_events using gin (assigned_user_ids);
alter table public.vismo_calendar_events enable row level security;
drop policy if exists "vismo_calendar_read_permitted" on public.vismo_calendar_events;
create policy "vismo_calendar_read_permitted" on public.vismo_calendar_events for select to authenticated
using (visibility='team' or auth.uid()=any(assigned_user_ids) or exists(select 1 from public.vismo_admins a where a.user_id=auth.uid()));
drop policy if exists "vismo_calendar_admin_insert" on public.vismo_calendar_events;
create policy "vismo_calendar_admin_insert" on public.vismo_calendar_events for insert to authenticated
with check (exists(select 1 from public.vismo_admins a where a.user_id=auth.uid()) and (created_by is null or created_by=auth.uid()));
drop policy if exists "vismo_calendar_admin_update" on public.vismo_calendar_events;
create policy "vismo_calendar_admin_update" on public.vismo_calendar_events for update to authenticated
using (exists(select 1 from public.vismo_admins a where a.user_id=auth.uid()))
with check (exists(select 1 from public.vismo_admins a where a.user_id=auth.uid()));
drop policy if exists "vismo_calendar_admin_delete" on public.vismo_calendar_events;
create policy "vismo_calendar_admin_delete" on public.vismo_calendar_events for delete to authenticated
using (exists(select 1 from public.vismo_admins a where a.user_id=auth.uid()));
grant select,insert,update,delete on public.vismo_calendar_events to authenticated;
