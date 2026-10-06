-- Ejecutar una sola vez en SQL Editor de Supabase.
begin;
create table public.vismo_admins (user_id uuid primary key references auth.users(id));
create table public.vismo_state (id integer primary key check(id=1), data jsonb not null);
insert into public.vismo_state values (1,'{"workers":[],"places":[],"shifts":[],"marks":[],"notes":[]}');
alter table public.vismo_admins enable row level security;
alter table public.vismo_state enable row level security;
revoke all on public.vismo_admins, public.vismo_state from anon, authenticated;
create or replace function public.vismo_control(payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 d jsonb; w jsonb; s jsonb; p jsonb; m jsonb; result jsonb; admin boolean;
 mail text; day text; kind text; lat double precision; lng double precision; accuracy double precision; distance double precision;
 server_time timestamptz:=clock_timestamp();
begin
 if auth.uid() is null then raise exception 'Inicia sesión.'; end if;
 select exists(select 1 from public.vismo_admins where user_id=auth.uid()) into admin;
 mail:=lower(auth.jwt()->>'email');
 -- Bloqueo de fila para no perder marcaciones simultáneas.
 select data into d from public.vismo_state where id=1 for update;
 if not admin then
  select value into w from jsonb_array_elements(d->'workers') where lower(value->>'email')=mail and (value->>'active')::boolean;
  if w is null then raise exception 'Tu correo no está registrado como trabajador activo.'; end if;
 end if;
 if coalesce(payload->>'action','read')='read' then
  if admin then result:=d;
  else result:=jsonb_build_object('workers',jsonb_build_array(w),'places',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'places') where value->>'id' in (select value->>'place' from jsonb_array_elements(d->'shifts') where value->>'worker'=w->>'id')),'[]'::jsonb),'shifts',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'shifts') where value->>'worker'=w->>'id'),'[]'::jsonb),'marks',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'marks') where value->>'worker'=w->>'id'),'[]'::jsonb),'notes',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'notes') where value->>'worker'=w->>'id'),'[]'::jsonb)); end if;
  return jsonb_build_object('data',result,'role',case when admin then 'admin' else 'worker' end,'workspace','VISMO','email',mail);
 elsif payload->>'action'='save' then
  if not admin then raise exception 'Solo administración puede modificar el equipo.'; end if;
  result:=payload->'data';
  if jsonb_typeof(result->'workers') is distinct from 'array' or jsonb_typeof(result->'places') is distinct from 'array' or jsonb_typeof(result->'shifts') is distinct from 'array' or jsonb_typeof(result->'notes') is distinct from 'array' then raise exception 'Datos inválidos.'; end if;
  -- Las horas reales no se pueden sobrescribir desde el navegador.
  result:=jsonb_set(result,'{marks}',d->'marks');
  update public.vismo_state set data=result where id=1;
  return jsonb_build_object('ok',true);
 elsif payload->>'action'='mark' then
  if admin then select value into w from jsonb_array_elements(d->'workers') where value->>'id'=payload->>'worker' and (value->>'active')::boolean;
  elsif w->>'id' is distinct from payload->>'worker' then raise exception 'No puedes marcar por otro trabajador.'; end if;
  if w is null then raise exception 'Trabajador inactivo.'; end if;
  kind:=payload->>'kind';if kind is null or kind not in ('in','out') then raise exception 'Marcación inválida.';end if;
  day:=to_char(server_time at time zone 'America/Lima','YYYY-MM-DD');
  select value into s from jsonb_array_elements(d->'shifts') where value->>'worker'=w->>'id' and value->>'date'=day;
  if s is null then raise exception 'No tienes turno para hoy.';end if;
  if exists(select 1 from jsonb_array_elements(d->'marks') where value->>'worker'=w->>'id' and value->>'date'=day and value->>'kind'=kind) then raise exception 'Ya registraste esta marcación.';end if;
  if kind='out' and not exists(select 1 from jsonb_array_elements(d->'marks') where value->>'worker'=w->>'id' and value->>'date'=day and value->>'kind'='in') then raise exception 'Primero marca la entrada.';end if;
  lat:=(payload->>'lat')::double precision;lng:=(payload->>'lng')::double precision;accuracy:=(payload->>'accuracy')::double precision;
  if lat is null or lng is null or accuracy is null or not(lat between -90 and 90) or not(lng between -180 and 180) or not(accuracy between 0 and 100) then raise exception 'GPS inválido o impreciso. Intenta al aire libre.';end if;
  select value into p from jsonb_array_elements(d->'places') where value->>'id'=s->>'place';
  if p is null or nullif(p->>'lat','') is null or nullif(p->>'lng','') is null then raise exception 'La obra no tiene ubicación configurada.';end if;
  distance:=6371000*2*asin(sqrt(least(1.0,power(sin(radians(lat-(p->>'lat')::double precision)/2),2)+cos(radians(lat))*cos(radians((p->>'lat')::double precision))*power(sin(radians(lng-(p->>'lng')::double precision)/2),2))));
  if distance>(p->>'radius')::double precision then raise exception 'Estás fuera del radio permitido de la obra.';end if;
  m:=jsonb_build_object('id',gen_random_uuid()::text,'worker',w->>'id','date',day,'kind',kind,'time',server_time,'lat',lat,'lng',lng,'accuracy',accuracy,'distance',round(distance::numeric));
  update public.vismo_state set data=jsonb_set(d,'{marks}',(d->'marks')||jsonb_build_array(m)) where id=1;
  return jsonb_build_object('ok',true,'mark',m);
 end if;
 raise exception 'Acción inválida.';
end;$$;
revoke all on function public.vismo_control(jsonb) from public, anon;
grant execute on function public.vismo_control(jsonb) to authenticated;
commit;
-- Después de crear TU usuario, reemplaza el correo y ejecuta SOLO esta línea:
-- insert into public.vismo_admins(user_id) select id from auth.users where lower(email)=lower('TU-CORREO-AQUI');
