create policy deny_direct_invite_access on private.staff_invites for all to anon,authenticated using(false) with check(false);
create policy deny_direct_tracking_access on private.ticket_tokens for all to anon,authenticated using(false) with check(false);
create index requests_owner_created on public.clinic_requests(owner_id,created_at desc);
create index requests_clinic on public.clinic_requests(clinic_id);
create index requests_decider on public.clinic_requests(decided_by);
create index audit_actor on public.audit_logs(actor_id);
create index queues_specialty on public.queues(clinic_id,specialty_id);
create index queues_room on public.queues(clinic_id,room_id);
create index tickets_room on public.queue_tickets(clinic_id,room_id);
create index patients_clinic_created on public.patients(clinic_id,created_at desc);
create index queue_waiting_order on public.queue_tickets(clinic_id,queue_id,priority desc,created_at,id) where status='waiting';
create index invites_creator on private.staff_invites(created_by);
create or replace function private.decide_clinic_request(p_request_id uuid,p_decision text,p_reason text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v_request public.clinic_requests; v_clinic uuid; begin
 if not private.is_platform_admin() then raise insufficient_privilege; end if;
 select * into v_request from public.clinic_requests where id=p_request_id for update;
 if not found or v_request.status<>'pending' then raise exception 'Request is not pending'; end if;
 if p_decision='approve' then
  insert into public.clinics(name,contact_email,city) values(v_request.name,v_request.contact_email,v_request.city) returning id into v_clinic;
  insert into public.clinic_members(clinic_id,user_id,role) values(v_clinic,v_request.owner_id,'admin');
  update public.clinic_requests set status='active',clinic_id=v_clinic,decided_by=auth.uid(),decided_at=now() where id=p_request_id;
 elsif p_decision='reject' and length(trim(p_reason)) between 5 and 500 then
  update public.clinic_requests set status='rejected',reason=trim(p_reason),decided_by=auth.uid(),decided_at=now() where id=p_request_id;
 else raise exception 'Invalid decision'; end if;
 insert into public.audit_logs(actor_id,action,target_id,metadata) values(auth.uid(),'clinic_request.'||p_decision,p_request_id,jsonb_build_object('clinic_id',v_clinic));
 return coalesce(v_clinic,p_request_id);
end $$;
notify pgrst, 'reload schema';
