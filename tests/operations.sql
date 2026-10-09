-- Disposable PostgreSQL / Supabase test database only. Fixtures are rolled back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('41000000-0000-0000-0000-000000000001','ops-admin@example.test',now(),false),
('41000000-0000-0000-0000-000000000002','ops-doctor@example.test',now(),false),
('41000000-0000-0000-0000-000000000003','ops-reception@example.test',now(),false),
('41000000-0000-0000-0000-000000000004','ops-patient@example.test',now(),false),
('41000000-0000-0000-0000-000000000005','ops-other@example.test',now(),false);
insert into public.clinics(id,name) values('42000000-0000-0000-0000-000000000001','TEST Operational Clinic'),('42000000-0000-0000-0000-000000000002','TEST Other Clinic');
insert into public.clinic_members(clinic_id,user_id,role) values
('42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001','admin'),
('42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000002','doctor'),
('42000000-0000-0000-0000-000000000002','41000000-0000-0000-0000-000000000005','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select public.clinic_operation('42000000-0000-0000-0000-000000000001','specialty','{"name":"TEST Specialty"}') ->> 'id' as specialty \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','room','{"name":"TEST Room"}') ->> 'id' as room \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','queue',jsonb_build_object('name','TEST Queue','specialty_id',:'specialty','room_id',:'room','doctor_id','41000000-0000-0000-0000-000000000002','expected_minutes',10)) ->> 'id' as queue \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','invite',jsonb_build_object('email','ops-reception@example.test','role','receptionist','token',repeat('a',64)));
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000004',true);
do $$ begin begin perform public.accept_staff_invite(repeat('a',64));raise exception 'Wrong account accepted invite' using errcode='ZX001';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
select public.accept_staff_invite(repeat('a',64));
do $$ begin begin perform public.accept_staff_invite(repeat('a',64));raise exception 'Invite reused' using errcode='ZX001';exception when insufficient_privilege then null;end;end $$;
select public.clinic_operation('42000000-0000-0000-0000-000000000001','patient','{"name":"TEST Patient One","email":"ops-patient@example.test"}') ->> 'id' as patient_one \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','patient','{"name":"TEST Patient Priority"}') ->> 'id' as patient_two \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','checkin',jsonb_build_object('queue_id',:'queue','patient_id',:'patient_one','priority',false,'token',repeat('b',64))) ->> 'id' as ticket_one \gset
select public.clinic_operation('42000000-0000-0000-0000-000000000001','checkin',jsonb_build_object('queue_id',:'queue','patient_id',:'patient_two','priority',true,'token',repeat('c',64))) ->> 'id' as ticket_two \gset
select set_config('test.queue',:'queue',true),set_config('test.patient',:'patient_one',true),set_config('test.ticket_one',:'ticket_one',true),set_config('test.ticket_two',:'ticket_two',true);
do $$ begin
 begin perform public.clinic_operation('42000000-0000-0000-0000-000000000001','checkin',jsonb_build_object('queue_id',current_setting('test.queue'),'patient_id',current_setting('test.patient'),'priority',false,'token',repeat('d',64)));raise exception 'Duplicate checkin allowed' using errcode='ZX001';exception when unique_violation then null;end;
 begin perform public.clinic_operation('42000000-0000-0000-0000-000000000001','room','{"name":"Unauthorized"}');raise exception 'Reception admin action allowed' using errcode='ZX001';exception when insufficient_privilege then null;end;
 begin perform public.clinic_workspace('42000000-0000-0000-0000-000000000002');raise exception 'Cross tenant workspace exposed' using errcode='ZX001';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000004',true);
do $$ declare v jsonb;begin
 v:=public.clinic_workspace('42000000-0000-0000-0000-000000000001');
 if jsonb_array_length(v->'tickets')<>1 or v ? 'patients' or (v->'tickets'->0) ? 'patient_name' then raise exception 'Patient privacy failed';end if;
 if (v->'tickets'->0->>'position')::integer<>2 then raise exception 'Priority ordering failed';end if;
 begin perform public.clinic_operation('42000000-0000-0000-0000-000000000001','call',jsonb_build_object('queue_id',current_setting('test.queue')));raise exception 'Patient called queue' using errcode='ZX001';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
do $$ declare v jsonb;begin
 v:=public.clinic_operation('42000000-0000-0000-0000-000000000001','call',jsonb_build_object('queue_id',current_setting('test.queue')));
 if v->>'id'<>current_setting('test.ticket_two') then raise exception 'Wrong ticket called';end if;
 begin perform public.clinic_operation('42000000-0000-0000-0000-000000000001','call',jsonb_build_object('queue_id',current_setting('test.queue')));raise exception 'Duplicate doctor call' using errcode='ZX001';exception when raise_exception then null;end;
 perform public.clinic_operation('42000000-0000-0000-0000-000000000001','start',jsonb_build_object('id',current_setting('test.ticket_two')));
 perform public.clinic_operation('42000000-0000-0000-0000-000000000001','finish',jsonb_build_object('id',current_setting('test.ticket_two')));
 perform public.clinic_operation('42000000-0000-0000-0000-000000000001','call',jsonb_build_object('queue_id',current_setting('test.queue')));
 perform public.clinic_operation('42000000-0000-0000-0000-000000000001','absent',jsonb_build_object('id',current_setting('test.ticket_one')));
end $$;
reset role;set local role anon;
do $$ declare v jsonb;begin
 v:=public.track_ticket(repeat('c',64));
 if v->>'status'<>'completed' or v->>'room'<>'TEST Room' or v ? 'patient_name' or v ? 'patient_id' then raise exception 'Public tracking failed';end if;
 begin perform public.track_ticket(repeat('f',64));raise exception 'Invalid tracking allowed' using errcode='ZX001';exception when invalid_parameter_value then null;end;
 begin perform private.ticket_summary(current_setting('test.ticket_two')::uuid);raise exception 'Anonymous helper allowed' using errcode='ZX001';exception when insufficient_privilege then null;end;
 begin perform public.clinic_workspace('42000000-0000-0000-0000-000000000001');raise exception 'Anonymous workspace allowed' using errcode='ZX001';exception when insufficient_privilege then null;end;
end $$;
reset role;
update private.ticket_tokens set expires_at=now()-interval '1 minute';
set local role anon;
do $$ begin begin perform public.track_ticket(repeat('b',64));raise exception 'Expired tracking allowed' using errcode='ZX001';exception when invalid_parameter_value then null;end;end $$;
reset role;set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
do $$ begin
 if (public.clinic_workspace('42000000-0000-0000-0000-000000000001')->'report'->>'completed')::integer<>1 then raise exception 'Report incorrect';end if;
 begin perform public.clinic_operation('42000000-0000-0000-0000-000000000001','member','{"user_id":"41000000-0000-0000-0000-000000000001","role":"admin","active":false}');raise exception 'Last admin disabled' using errcode='ZX001';exception when raise_exception then null;end;
end $$;
reset role;
rollback;
\echo 'Operational flow, transitions, invites and patient privacy passed'
