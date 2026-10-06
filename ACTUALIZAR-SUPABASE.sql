-- ACTUALIZACIÓN: ejecutar una vez después del backend original. Conserva datos existentes.
begin;
create table if not exists public.vismo_access_requests (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null, name text not null, position text not null default '',
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default clock_timestamp(),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz
);
alter table public.vismo_access_requests enable row level security;
revoke all on public.vismo_access_requests from public,anon,authenticated;
create or replace function public.vismo_control(payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 d jsonb; w jsonb; s jsonb; p jsonb; m jsonb; result jsonb; admin boolean;
 mail text; day text; kind text; lat double precision; lng double precision; accuracy double precision; distance double precision;
 server_time timestamptz:=clock_timestamp();
 req public.vismo_access_requests%rowtype; action text:=coalesce(payload->>'action','read');
begin
 if auth.uid() is null then raise exception 'Inicia sesión.'; end if;
 select exists(select 1 from public.vismo_admins where user_id=auth.uid()) into admin;
 mail:=lower(auth.jwt()->>'email');
 -- Bloqueo de fila para no perder marcaciones simultáneas.
 select data into d from public.vismo_state where id=1 for update;
 if not admin then
  select value into w from jsonb_array_elements(d->'workers') where (value->>'user_id'=auth.uid()::text or (nullif(value->>'user_id','') is null and lower(value->>'email')=mail)) and (value->>'active')::boolean;
  if w is null then
   if action<>'read' then raise exception 'Tu acceso no está autorizado o está desactivado.'; end if;
   -- Solo registra una solicitud al entrar en ESTA aplicación; no hay triggers sobre otras cuentas.
   insert into public.vismo_access_requests(user_id,email,name,position)
    select id,lower(email),left(coalesce(nullif(btrim(raw_user_meta_data->>'full_name'),''),split_part(email,'@',1)),120),left(coalesce(raw_user_meta_data->>'position',''),100)
    from auth.users where id=auth.uid()
    on conflict(user_id) do nothing;
   select * into req from public.vismo_access_requests where user_id=auth.uid();
   return jsonb_build_object('role','pending','workspace','VISMO','email',mail,'accessStatus',
    case when exists(select 1 from jsonb_array_elements(d->'workers') where value->>'user_id'=auth.uid()::text or (nullif(value->>'user_id','') is null and lower(value->>'email')=mail)) or req.status='approved' then 'inactive' else req.status end,
    'data',jsonb_build_object('workers','[]'::jsonb,'places','[]'::jsonb,'shifts','[]'::jsonb,'marks','[]'::jsonb,'notes','[]'::jsonb));
  end if;
 end if;
 if action in ('approve','reject') then
  if not admin then raise exception 'Solo administración puede autorizar solicitudes.'; end if;
  select * into req from public.vismo_access_requests where user_id=(payload->>'user_id')::uuid for update;
  if req.user_id is null then raise exception 'Solicitud no encontrada.'; end if;
  if action='approve' then
   select value into w from jsonb_array_elements(d->'workers') where value->>'user_id'=req.user_id::text or (nullif(value->>'user_id','') is null and lower(value->>'email')=lower(req.email));
   w:=coalesce(w,jsonb_build_object('id',gen_random_uuid()::text,'name',req.name,'position',req.position,'contract','Fijo')) || jsonb_build_object('user_id',req.user_id::text,'email',req.email,'active',true);
   d:=jsonb_set(d,'{workers}',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'workers') where value->>'id'<>w->>'id'),'[]'::jsonb)||jsonb_build_array(w));
   update public.vismo_state set data=d where id=1;
  elsif req.status='approved' then raise exception 'Para quitar acceso a un trabajador aprobado usa Desactivar.';
  end if;
  update public.vismo_access_requests set status=case when action='approve' then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=clock_timestamp() where user_id=req.user_id;
  return jsonb_build_object('ok',true);
 elsif action='read' then
  if admin then result:=d;
  else result:=jsonb_build_object('workers',jsonb_build_array(w),'places',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'places') where value->>'id' in (select value->>'place' from jsonb_array_elements(d->'shifts') where value->>'worker'=w->>'id')),'[]'::jsonb),'shifts',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'shifts') where value->>'worker'=w->>'id'),'[]'::jsonb),'marks',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'marks') where value->>'worker'=w->>'id'),'[]'::jsonb),'notes',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'notes') where value->>'worker'=w->>'id'),'[]'::jsonb)); end if;
  return jsonb_build_object('data',result,'role',case when admin then 'admin' else 'worker' end,'workspace','VISMO','email',mail,'requests',case when admin then coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.vismo_access_requests r),'[]'::jsonb) else '[]'::jsonb end);
 elsif payload->>'action'='save' then
  if not admin then raise exception 'Solo administración puede modificar el equipo.'; end if;
  result:=payload->'data';
  if jsonb_typeof(result->'workers') is distinct from 'array' or jsonb_typeof(result->'places') is distinct from 'array' or jsonb_typeof(result->'shifts') is distinct from 'array' or jsonb_typeof(result->'notes') is distinct from 'array' then raise exception 'Datos inválidos.'; end if;
  -- Evita que un formulario anterior a una aprobación quite a la persona recién autorizada.
  if exists(select 1 from jsonb_array_elements(d->'workers') old_w where nullif(old_w->>'user_id','') is not null and not exists(select 1 from jsonb_array_elements(result->'workers') new_w where new_w->>'id'=old_w->>'id' and new_w->>'user_id'=old_w->>'user_id')) then raise exception 'El equipo cambió. Actualiza la página e intenta nuevamente.';end if;
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
