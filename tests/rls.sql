-- Execute only against a disposable Supabase test database. Everything rolls back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('10000000-0000-0000-0000-000000000001','owner-a@example.test',now(),false),
('10000000-0000-0000-0000-000000000002','owner-b@example.test',now(),false),
('10000000-0000-0000-0000-000000000003','platform@example.test',now(),false);
insert into public.platform_admins(user_id) values('10000000-0000-0000-0000-000000000003');
insert into public.clinics(id,name) values ('20000000-0000-0000-0000-000000000001','Test Clinic A'),('20000000-0000-0000-0000-000000000002','Test Clinic B');
insert into public.clinic_members(clinic_id,user_id,role) values
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin'),
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','admin');
insert into public.patients(clinic_id,name) values ('20000000-0000-0000-0000-000000000001','Test Patient A'),('20000000-0000-0000-0000-000000000002','Test Patient B');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ begin
 if (select count(*) from public.patients)<>1 then raise exception 'Tenant isolation failed'; end if;
 if exists(select 1 from public.patients where clinic_id='20000000-0000-0000-0000-000000000002') then raise exception 'BOLA failed'; end if;
 begin insert into public.platform_admins(user_id) values(auth.uid()); raise exception 'Self-promotion allowed'; exception when insufficient_privilege then null; end;
 begin perform public.decide_clinic_request(gen_random_uuid(),'approve',null); raise exception 'Owner approval allowed'; exception when insufficient_privilege then null; end;
end $$;
select public.submit_clinic_request('Requested Clinic','contact@example.test','São Paulo') as request_id \gset
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ begin if exists(select 1 from public.clinic_requests) then raise exception 'Other owner request exposed'; end if; end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ begin if exists(select 1 from public.patients) then raise exception 'Platform clinical access allowed'; end if; end $$;
select public.decide_clinic_request(:'request_id','approve',null) as clinic_id \gset
select set_config('test.request_id', :'request_id', true);
do $$ begin
 begin perform public.decide_clinic_request(current_setting('test.request_id')::uuid,'approve',null); raise exception 'Repeated approval allowed' using errcode='ZX001'; exception when raise_exception then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ begin if (select count(*) from public.clinic_members where user_id=auth.uid() and role='admin')<>2 then raise exception 'Atomic membership creation failed'; end if; end $$;
-- Rejection records actor, timestamp and reason without creating a membership.
select public.submit_clinic_request('Rejected Clinic','reject@example.test','City') as rejected_id \gset
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select public.decide_clinic_request(:'rejected_id','reject','Incomplete clinic information');
select set_config('test.rejected_id', :'rejected_id', true);
do $$ begin if not exists(select 1 from public.clinic_requests where id=current_setting('test.rejected_id')::uuid and status='rejected' and decided_by=auth.uid() and decided_at is not null and reason='Incomplete clinic information') then raise exception 'Rejection audit fields missing'; end if; end $$;
reset role;
update public.clinics set status='suspended' where id='20000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ begin if exists(select 1 from public.patients) then raise exception 'Suspended clinic exposed'; end if; end $$;
reset role;
insert into public.specialties(id,clinic_id,name) values('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','Test specialty');
do $$ begin
 begin insert into public.queues(clinic_id,specialty_id) values('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'); raise exception 'Cross-tenant FK allowed'; exception when foreign_key_violation then null; end;
end $$;
set local role anon;
do $$ begin
 begin perform public.submit_clinic_request('Anonymous Clinic','x@example.test','City'); raise exception 'Anonymous RPC allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'Authorization and tenant isolation assertions passed'
