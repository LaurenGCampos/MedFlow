begin;
create or replace function private.is_platform_admin() returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from public.platform_admins p join auth.users u on u.id=p.user_id where p.user_id=auth.uid() and u.email_confirmed_at is not null and not u.is_anonymous) $$;
alter table public.clinics add column timezone text not null default 'America/Sao_Paulo', add column contact_email text, add column city text;
alter table public.clinic_members add column active boolean not null default true;
alter table public.queues add column name text not null default 'Fila de atendimento', add column room_id uuid, add column expected_minutes integer not null default 15 check(expected_minutes between 1 and 240), add foreign key(clinic_id,room_id) references public.rooms(clinic_id,id);
alter table public.queue_tickets add column priority boolean not null default false;
create unique index one_active_ticket_per_patient on public.queue_tickets(clinic_id,patient_id) where status in ('waiting','called','in_service');
create unique index one_active_appointment_per_doctor on public.appointments(clinic_id,doctor_id) where status='in_service';
create index queues_doctor on public.queues(clinic_id,doctor_id);
create index tickets_patient on public.queue_tickets(clinic_id,patient_id);
create index appointments_doctor on public.appointments(clinic_id,doctor_id);
create table private.staff_invites(id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id), email text not null,role text not null check(role in ('admin','doctor','receptionist','patient')), token_hash text not null unique,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '7 days',accepted_at timestamptz,revoked_at timestamptz);
alter table private.staff_invites enable row level security;
create index invites_clinic on private.staff_invites(clinic_id,created_at);
create table private.ticket_tokens(token_hash text primary key,clinic_id uuid not null,ticket_id uuid not null,expires_at timestamptz not null default now()+interval '48 hours',foreign key(clinic_id,ticket_id) references public.queue_tickets(clinic_id,id));
alter table private.ticket_tokens enable row level security;
create index tokens_ticket on private.ticket_tokens(clinic_id,ticket_id);
revoke all on private.staff_invites,private.ticket_tokens from public,anon,authenticated;
create or replace function private.has_clinic_role(p_clinic uuid,p_roles text[]) returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from public.clinic_members m join public.clinics c on c.id=m.clinic_id where m.user_id=auth.uid() and m.clinic_id=p_clinic and m.active and m.role=any(p_roles) and c.status='active') $$;
create function private.require_clinic(p_clinic uuid,p_roles text[]) returns void language plpgsql stable security definer set search_path='' as $$ begin
 if not private.has_clinic_role(p_clinic,p_roles) or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not is_anonymous) then raise insufficient_privilege; end if;
end $$;
create function private.token_hash(p_token text) returns text language sql immutable set search_path='' as $$ select encode(sha256(convert_to(p_token,'UTF8')),'hex') $$;
create function private.can_read_patient(p_clinic uuid,p_patient uuid) returns boolean language sql stable security definer set search_path='' as $$ select private.has_clinic_role(p_clinic,array['admin','receptionist']) or (private.has_clinic_role(p_clinic,array['doctor']) and exists(select 1 from public.queue_tickets t join public.queues q on q.clinic_id=t.clinic_id and q.id=t.queue_id where t.clinic_id=p_clinic and t.patient_id=p_patient and q.doctor_id=auth.uid())) or exists(select 1 from public.patients p where p.clinic_id=p_clinic and p.id=p_patient and p.user_id=auth.uid() and private.has_clinic_role(p_clinic,array['patient'])) $$;
alter policy patient_visibility on public.patients using(private.can_read_patient(clinic_id,id));
create function private.ticket_summary(p_ticket uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',t.id,'number',t.number,'status',t.status,'priority',t.priority,'clinic',c.name,'queue',q.name,'room',r.name,'called_at',t.called_at,'created_at',t.created_at,'position',case when t.status='waiting' then 1+(select count(*) from public.queue_tickets ahead where ahead.clinic_id=t.clinic_id and ahead.queue_id=t.queue_id and ahead.status='waiting' and (ahead.priority>t.priority or (ahead.priority=t.priority and (ahead.created_at,ahead.id)<(t.created_at,t.id)))) else 0 end,'estimated_minutes',case when t.status='waiting' then q.expected_minutes*(1+(select count(*) from public.queue_tickets ahead where ahead.clinic_id=t.clinic_id and ahead.queue_id=t.queue_id and ahead.status='waiting' and (ahead.priority>t.priority or (ahead.priority=t.priority and (ahead.created_at,ahead.id)<(t.created_at,t.id))))) else 0 end)
 from public.queue_tickets t join public.queues q on q.clinic_id=t.clinic_id and q.id=t.queue_id join public.clinics c on c.id=t.clinic_id left join public.rooms r on r.clinic_id=t.clinic_id and r.id=t.room_id where t.id=p_ticket and c.status='active'
$$;
create function private.track_ticket(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_ticket uuid;v_result jsonb;begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid or expired token' using errcode='22023';end if;
 select ticket_id into v_ticket from private.ticket_tokens where token_hash=private.token_hash(p_token) and expires_at>now();
 v_result:=private.ticket_summary(v_ticket);
 if v_result is null then raise exception 'Invalid or expired token' using errcode='22023';end if;
 return v_result;
end $$;
create function private.accept_staff_invite(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_inv private.staff_invites;v_email text;begin
 select lower(email) into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null and not is_anonymous;
 if v_email is null then raise insufficient_privilege;end if;
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid invite' using errcode='22023';end if;
 select * into v_inv from private.staff_invites where token_hash=private.token_hash(p_token) for update;
 if not found or v_inv.email<>v_email or v_inv.expires_at<=now() or v_inv.accepted_at is not null or v_inv.revoked_at is not null or not exists(select 1 from public.clinic_members where clinic_id=v_inv.clinic_id and user_id=v_inv.created_by and active and role='admin') or not exists(select 1 from public.clinics where id=v_inv.clinic_id and status='active') then raise insufficient_privilege;end if;
 if exists(select 1 from public.clinic_members where clinic_id=v_inv.clinic_id and user_id=auth.uid()) then raise exception 'Membership already exists';end if;
 insert into public.clinic_members(clinic_id,user_id,role) values(v_inv.clinic_id,auth.uid(),v_inv.role);
 update private.staff_invites set accepted_at=now() where id=v_inv.id;
 insert into public.audit_logs(clinic_id,actor_id,action,target_id) values(v_inv.clinic_id,auth.uid(),'member.invite_accepted',v_inv.id);
 return v_inv.clinic_id;
end $$;
create function private.clinic_operation(p_clinic uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_role text;v_ticket public.queue_tickets;v_queue public.queues;v_num integer;v_day date;v_user uuid;v_result jsonb;v_name text;v_token text;v_email text;begin
 if jsonb_typeof(p_data)<>'object' then raise exception 'Invalid data' using errcode='22023';end if;
 if p_action in ('settings','specialty','room','queue','queue_status','invite','revoke_invite','member','specialty_edit','room_edit','queue_edit') then perform private.require_clinic(p_clinic,array['admin']);
 elsif p_action in ('patient','checkin','cancel','tracking','patient_edit') then perform private.require_clinic(p_clinic,array['admin','receptionist']);
 elsif p_action in ('call','start','finish','absent') then perform private.require_clinic(p_clinic,array['doctor']);
 else raise exception 'Invalid operation' using errcode='22023';end if;
 v_name:=trim(p_data->>'name');
 if p_action in ('settings','specialty','room','queue','patient','specialty_edit','room_edit','queue_edit','patient_edit') and (v_name is null or length(v_name) not between 2 and 120 or v_name ~ '[[:cntrl:]]') then raise exception 'Invalid name' using errcode='22023';end if;
 if p_action='settings' then
  if not exists(select 1 from pg_timezone_names where name=p_data->>'timezone') or length(coalesce(p_data->>'city',''))>120 or length(coalesce(p_data->>'contact_email',''))>254 then raise exception 'Invalid settings' using errcode='22023';end if;
  update public.clinics set name=v_name,timezone=p_data->>'timezone',city=trim(p_data->>'city'),contact_email=trim(p_data->>'contact_email') where id=p_clinic;v_id:=p_clinic;
 elsif p_action in ('specialty_edit','room_edit','patient_edit') then
  v_id:=(p_data->>'id')::uuid;
  if p_action='specialty_edit' then update public.specialties set name=v_name where id=v_id and clinic_id=p_clinic;
  elsif p_action='room_edit' then update public.rooms set name=v_name where id=v_id and clinic_id=p_clinic;
  else update public.patients set name=v_name where id=v_id and clinic_id=p_clinic;end if;
  if not found then raise exception 'Record not found';end if;
 elsif p_action='queue_edit' then
  v_id:=(p_data->>'id')::uuid;perform 1 from public.queues where id=v_id and clinic_id=p_clinic for update;
  if not found then raise exception 'Queue not found';end if;
  if exists(select 1 from public.queue_tickets where queue_id=v_id and clinic_id=p_clinic and status in ('waiting','called','in_service')) then raise exception 'Queue has active tickets';end if;
  update public.queues set name=v_name,room_id=(p_data->>'room_id')::uuid,expected_minutes=(p_data->>'expected_minutes')::integer where id=v_id and clinic_id=p_clinic;
 elsif p_action='specialty' then insert into public.specialties(clinic_id,name) values(p_clinic,v_name) returning id into v_id;
 elsif p_action='room' then insert into public.rooms(clinic_id,name) values(p_clinic,v_name) returning id into v_id;
 elsif p_action='queue' then
  if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=(p_data->>'doctor_id')::uuid and role='doctor' and active) then raise exception 'Invalid doctor' using errcode='22023';end if;
  insert into public.queues(clinic_id,name,specialty_id,doctor_id,room_id,expected_minutes) values(p_clinic,v_name,(p_data->>'specialty_id')::uuid,(p_data->>'doctor_id')::uuid,(p_data->>'room_id')::uuid,(p_data->>'expected_minutes')::integer) returning id into v_id;
 elsif p_action='queue_status' then
  v_id:=(p_data->>'id')::uuid;select * into v_queue from public.queues where id=v_id and clinic_id=p_clinic for update;
  if not found or p_data->>'status' not in ('open','closed') then raise exception 'Invalid queue' using errcode='22023';end if;
  if p_data->>'status'='closed' and exists(select 1 from public.queue_tickets where clinic_id=p_clinic and queue_id=v_id and status in ('waiting','called','in_service')) then raise exception 'Queue has active tickets';end if;
  update public.queues set status=p_data->>'status' where id=v_id;
 elsif p_action='invite' then
  v_email:=lower(trim(p_data->>'email'));v_token:=p_data->>'token';v_role:=p_data->>'role';
  if v_email is null or length(v_email)>254 or v_email !~ '^[^ @]+@[^ @]+\.[^ @]+$' or v_role is null or v_role not in ('admin','doctor','receptionist','patient') or v_token is null or v_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid invite' using errcode='22023';end if;
  insert into private.staff_invites(clinic_id,email,role,token_hash,created_by) values(p_clinic,v_email,v_role,private.token_hash(v_token),auth.uid()) returning id into v_id;
 elsif p_action='revoke_invite' then
  update private.staff_invites set revoked_at=now() where id=(p_data->>'id')::uuid and clinic_id=p_clinic and accepted_at is null returning id into v_id;
  if not found then raise exception 'Invite not available';end if;
 elsif p_action='member' then
  v_user:=(p_data->>'user_id')::uuid;v_role:=p_data->>'role';
  if v_role is null or v_role not in ('admin','doctor','receptionist','patient') or jsonb_typeof(p_data->'active')<>'boolean' then raise exception 'Invalid role' using errcode='22023';end if;
  -- Serialize roster mutations to preserve at least one active administrator.
  perform 1 from public.clinics where id=p_clinic for update;
  if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_user) then raise exception 'Member not found';end if;
  if exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_user and role='admin' and active) and (v_role<>'admin' or not (p_data->>'active')::boolean) and (select count(*) from public.clinic_members where clinic_id=p_clinic and role='admin' and active)<=1 then raise exception 'Last administrator';end if;
  if (v_role<>'doctor' or not (p_data->>'active')::boolean) and exists(select 1 from public.queues where clinic_id=p_clinic and doctor_id=v_user and status='open') then raise exception 'Close doctor queues first';end if;
  update public.clinic_members set role=v_role,active=(p_data->>'active')::boolean where clinic_id=p_clinic and user_id=v_user;v_id:=v_user;
 elsif p_action='patient' then
  v_email:=lower(trim(p_data->>'email'));
  if v_email is not null and v_email<>'' then
   if length(v_email)>254 or v_email !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'Invalid email' using errcode='22023';end if;
   select id into v_user from auth.users where lower(email)=v_email and email_confirmed_at is not null;
  end if;
  insert into public.patients(clinic_id,name,user_id) values(p_clinic,v_name,v_user) returning id into v_id;
  if v_user is not null then insert into public.clinic_members(clinic_id,user_id,role) values(p_clinic,v_user,'patient') on conflict(clinic_id,user_id) do nothing;end if;
 elsif p_action='checkin' then
  v_token:=p_data->>'token';if v_token is null or v_token !~ '^[a-f0-9]{64}$' or jsonb_typeof(p_data->'priority')<>'boolean' then raise exception 'Invalid tracking token' using errcode='22023';end if;
  select * into v_queue from public.queues where clinic_id=p_clinic and id=(p_data->>'queue_id')::uuid for update;
  if not found or v_queue.status<>'open' or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=v_queue.doctor_id and role='doctor' and active) then raise exception 'Queue unavailable';end if;
  select (now() at time zone timezone)::date into v_day from public.clinics where id=p_clinic;
  select coalesce(max(number),0)+1 into v_num from public.queue_tickets where clinic_id=p_clinic and queue_id=v_queue.id and ticket_date=v_day;
  insert into public.queue_tickets(clinic_id,queue_id,patient_id,number,ticket_date,priority) values(p_clinic,v_queue.id,(p_data->>'patient_id')::uuid,v_num,v_day,(p_data->>'priority')::boolean) returning id into v_id;
  insert into private.ticket_tokens(token_hash,clinic_id,ticket_id) values(private.token_hash(v_token),p_clinic,v_id);
  v_result:=jsonb_build_object('id',v_id,'number',v_num);
 elsif p_action='tracking' then
  v_id:=(p_data->>'id')::uuid;v_token:=p_data->>'token';
  if v_token is null or v_token !~ '^[a-f0-9]{64}$' or not exists(select 1 from public.queue_tickets where id=v_id and clinic_id=p_clinic) then raise exception 'Invalid ticket' using errcode='22023';end if;
  delete from private.ticket_tokens where ticket_id=v_id and clinic_id=p_clinic;
  insert into private.ticket_tokens(token_hash,clinic_id,ticket_id) values(private.token_hash(v_token),p_clinic,v_id);
 elsif p_action='cancel' then
  select * into v_ticket from public.queue_tickets where id=(p_data->>'id')::uuid and clinic_id=p_clinic for update;
  if not found or v_ticket.status not in ('waiting','called') then raise exception 'Ticket cannot be cancelled';end if;
  v_id:=v_ticket.id;update public.queue_tickets set status='cancelled' where id=v_id;
 elsif p_action='call' then
  -- Lock doctor roster row to serialize calls across multiple queues.
  perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for update;
  select * into v_queue from public.queues where id=(p_data->>'queue_id')::uuid and clinic_id=p_clinic and doctor_id=auth.uid();
  if not found or v_queue.status<>'open' or v_queue.room_id is null then raise exception 'Queue or room unavailable';end if;
  if exists(select 1 from public.queue_tickets t join public.queues q on q.id=t.queue_id where t.clinic_id=p_clinic and q.doctor_id=auth.uid() and t.status in ('called','in_service')) then raise exception 'Finish current ticket first';end if;
  select * into v_ticket from public.queue_tickets where clinic_id=p_clinic and queue_id=v_queue.id and status='waiting' order by priority desc,created_at,id limit 1 for update skip locked;
  if not found then raise exception 'No waiting tickets';end if;
  v_id:=v_ticket.id;update public.queue_tickets set status='called',called_at=now(),room_id=v_queue.room_id where id=v_id;
 elsif p_action in ('start','finish','absent') then
  perform 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() for update;
  select t.* into v_ticket from public.queue_tickets t join public.queues q on q.id=t.queue_id and q.clinic_id=t.clinic_id where t.id=(p_data->>'id')::uuid and t.clinic_id=p_clinic and q.doctor_id=auth.uid() for update of t;
  if not found then raise insufficient_privilege;end if;v_id:=v_ticket.id;
  if p_action='start' and v_ticket.status='called' then
   insert into public.appointments(clinic_id,ticket_id,doctor_id) values(p_clinic,v_id,auth.uid());
   update public.queue_tickets set status='in_service' where id=v_id;
  elsif p_action='finish' and v_ticket.status='in_service' then
   update public.appointments set status='completed',ended_at=now() where clinic_id=p_clinic and ticket_id=v_id and doctor_id=auth.uid();
   update public.queue_tickets set status='completed' where id=v_id;
  elsif p_action='absent' and v_ticket.status='called' then update public.queue_tickets set status='absent' where id=v_id;
  else raise exception 'Invalid ticket transition';end if;
 end if;
 insert into public.audit_logs(clinic_id,actor_id,action,target_id) values(p_clinic,auth.uid(),'clinic.'||p_action,v_id);
 return coalesce(v_result,jsonb_build_object('id',v_id));
end $$;
create function private.clinic_workspace(p_clinic uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text;v_data jsonb;v_members jsonb;v_patients jsonb;v_tickets jsonb;v_invites jsonb;v_report jsonb;begin
 perform private.require_clinic(p_clinic,array['admin','doctor','receptionist','patient']);
 select role into v_role from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid() and active;
 if v_role='patient' then
  select coalesce(jsonb_agg(private.ticket_summary(t.id) order by t.created_at desc),'[]') into v_tickets from public.queue_tickets t join public.patients p on p.id=t.patient_id where t.clinic_id=p_clinic and p.user_id=auth.uid() and t.created_at>now()-interval '30 days';
  return jsonb_build_object('role',v_role,'tickets',v_tickets);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'user_id',p.user_id) order by p.name),'[]') into v_patients from (select * from public.patients p where clinic_id=p_clinic and (v_role<>'doctor' or private.can_read_patient(p_clinic,p.id)) order by created_at desc limit 500) p;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'number',t.number,'status',t.status,'priority',t.priority,'patient_name',p.name,'queue_id',t.queue_id,'queue_name',q.name,'room',r.name,'created_at',t.created_at,'called_at',t.called_at) order by t.priority desc,t.created_at),'[]') into v_tickets from public.queue_tickets t join public.patients p on p.id=t.patient_id join public.queues q on q.id=t.queue_id left join public.rooms r on r.id=t.room_id where t.clinic_id=p_clinic and (v_role<>'doctor' or q.doctor_id=auth.uid()) and (t.status in ('waiting','called','in_service') or t.created_at>now()-interval '2 days');
 if v_role='admin' then
  select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role,'active',m.active,'name',p.display_name) order by m.created_at),'[]') into v_members from public.clinic_members m join public.profiles p on p.id=m.user_id where m.clinic_id=p_clinic;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'expires_at',expires_at,'accepted_at',accepted_at,'revoked_at',revoked_at) order by created_at desc),'[]') into v_invites from (select * from private.staff_invites where clinic_id=p_clinic order by created_at desc limit 100) i;
  select jsonb_build_object('total',count(*),'completed',count(*) filter(where t.status='completed'),'cancelled',count(*) filter(where t.status='cancelled'),'absent',count(*) filter(where t.status='absent'),'average_wait_minutes',round(avg(extract(epoch from(t.called_at-t.created_at))/60)::numeric,1),'average_service_minutes',round(avg(extract(epoch from(a.ended_at-a.started_at))/60)::numeric,1)) into v_report from public.queue_tickets t left join public.appointments a on a.ticket_id=t.id where t.clinic_id=p_clinic and t.created_at>now()-interval '30 days';
 end if;
 select jsonb_build_object('role',v_role,'clinic',(select to_jsonb(c) from public.clinics c where id=p_clinic),'specialties',(select coalesce(jsonb_agg(to_jsonb(s) order by name),'[]') from public.specialties s where clinic_id=p_clinic),'rooms',(select coalesce(jsonb_agg(to_jsonb(r) order by name),'[]') from public.rooms r where clinic_id=p_clinic),'queues',(select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('doctor_name',p.display_name,'room_name',r.name,'specialty_name',s.name) order by q.name),'[]') from public.queues q join public.specialties s on s.id=q.specialty_id left join public.rooms r on r.id=q.room_id left join public.profiles p on p.id=q.doctor_id where q.clinic_id=p_clinic and (v_role<>'doctor' or q.doctor_id=auth.uid())),'patients',v_patients,'tickets',v_tickets,'members',coalesce(v_members,'[]'),'invites',coalesce(v_invites,'[]'),'report',v_report) into v_data;
 return v_data;
end $$;
create function private.platform_clinic_status(p_clinic uuid,p_status text,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$ begin
 if not private.is_platform_admin() then raise insufficient_privilege;end if;
 if p_status is null or p_status not in ('active','suspended') or p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'Invalid decision' using errcode='22023';end if;
 update public.clinics set status=p_status where id=p_clinic and status in ('active','suspended');
 if not found then raise exception 'Clinic not found';end if;
 insert into public.audit_logs(actor_id,action,target_id,metadata) values(auth.uid(),'clinic.'||p_status,p_clinic,jsonb_build_object('reason',trim(p_reason)));
 return p_clinic;
end $$;
revoke all on function private.require_clinic(uuid,text[]) from public,anon,authenticated;
revoke all on function private.token_hash(text) from public,anon,authenticated;
revoke all on function private.can_read_patient(uuid,uuid) from public,anon,authenticated;
grant execute on function private.can_read_patient(uuid,uuid) to authenticated;
revoke all on function private.ticket_summary(uuid) from public,anon,authenticated;
revoke all on function private.track_ticket(text) from public,anon,authenticated;
grant execute on function private.track_ticket(text) to authenticated,anon;
create function public.track_ticket(p_token text) returns jsonb language sql security invoker set search_path='' as $$ select private.track_ticket(p_token) $$;
revoke all on function public.track_ticket(text) from public,anon,authenticated;
grant execute on function public.track_ticket(text) to authenticated,anon;
revoke all on function private.accept_staff_invite(text) from public,anon,authenticated;
grant execute on function private.accept_staff_invite(text) to authenticated;
create function public.accept_staff_invite(p_token text) returns uuid language sql security invoker set search_path='' as $$ select private.accept_staff_invite(p_token) $$;
revoke all on function public.accept_staff_invite(text) from public,anon,authenticated;
grant execute on function public.accept_staff_invite(text) to authenticated;
revoke all on function private.clinic_operation(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.clinic_operation(uuid,text,jsonb) to authenticated;
create function public.clinic_operation(p_clinic uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.clinic_operation(p_clinic,p_action,p_data) $$;
revoke all on function public.clinic_operation(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.clinic_operation(uuid,text,jsonb) to authenticated;
revoke all on function private.clinic_workspace(uuid) from public,anon,authenticated;
grant execute on function private.clinic_workspace(uuid) to authenticated;
create function public.clinic_workspace(p_clinic uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.clinic_workspace(p_clinic) $$;
revoke all on function public.clinic_workspace(uuid) from public,anon,authenticated;
grant execute on function public.clinic_workspace(uuid) to authenticated;
revoke all on function private.platform_clinic_status(uuid,text,text) from public,anon,authenticated;
grant execute on function private.platform_clinic_status(uuid,text,text) to authenticated;
create function public.platform_clinic_status(p_clinic uuid,p_status text,p_reason text) returns uuid language sql security invoker set search_path='' as $$ select private.platform_clinic_status(p_clinic,p_status,p_reason) $$;
revoke all on function public.platform_clinic_status(uuid,text,text) from public,anon,authenticated;
grant execute on function public.platform_clinic_status(uuid,text,text) to authenticated;
grant usage on schema private to anon;
notify pgrst, 'reload schema';
commit;
