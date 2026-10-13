-- Calendario empresarial de Vismo: categorías corporativas y responsable.
alter table public.vismo_calendar_events
  add column if not exists responsible_person text not null default '';
alter table public.vismo_calendar_events
  alter column visibility set default 'team';
alter table public.vismo_calendar_events
  drop constraint if exists vismo_calendar_events_category_check;
alter table public.vismo_calendar_events
  add constraint vismo_calendar_events_category_check
  check (category in ('charla','capacitacion','confraternizacion','reunion','seguridad_salud','actividad_interna','otro','laboral','inspeccion','fecha_especial','cumpleanos','aniversario','celebracion'));
