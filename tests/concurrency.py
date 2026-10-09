"""Concurrency integration test in a NEW disposable database inside the local test container.
Never connects to the production Supabase project; creates and drops only its own test database.
"""
import concurrent.futures
import json
from pathlib import Path
import secrets
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'medflow-operations-postgres'
DATABASE = 'medflow_concurrency_' + uuid.uuid4().hex[:12]

def command(*args, **kwargs):
    return subprocess.run(['podman','exec',*args], text=True, capture_output=True, **kwargs)

def sql(query, checked=True):
    result=command('-i',CONTAINER,'psql','-U','postgres','-d',DATABASE,'-v','ON_ERROR_STOP=1','-At',input=query)
    if checked and result.returncode:
        raise RuntimeError(result.stderr)
    return result

def identifier(): return str(uuid.uuid4())

def operation(actor,clinic,action,data):
    # UUIDs and action are generated locally; JSON is quoted as a SQL literal in this test fixture only.
    encoded=json.dumps(data).replace("'","''")
    return sql(f"set role authenticated;select set_config('request.jwt.claim.sub','{actor}',false);select public.clinic_operation('{clinic}','{action}','{encoded}'::jsonb);",False)

command(CONTAINER,'createdb','-U','postgres',DATABASE,check=True)
try:
    sql((ROOT/'tests/postgres-auth-stub.sql').read_text()+''.join(f.read_text() for f in sorted((ROOT/'supabase/migrations').glob('*.sql'))))
    admin,doctor,reception,clinic,specialty,room,queue=[identifier() for _ in range(7)]
    patient_ids=[identifier() for _ in range(17)]
    users=','.join(f"('{u}','concurrency-{i}@example.test',now(),false)" for i,u in enumerate([admin,doctor,reception]))
    members=','.join(f"('{clinic}','{u}','{role}')" for u,role in [(admin,'admin'),(doctor,'doctor'),(reception,'receptionist')])
    patients=','.join(f"('{u}','{clinic}','TEST Concurrency Patient {i}')" for i,u in enumerate(patient_ids))
    sql(f"""insert into auth.users(id,email,email_confirmed_at,is_anonymous) values {users};
insert into public.clinics(id,name) values('{clinic}','TEST Concurrency Clinic');
insert into public.clinic_members(clinic_id,user_id,role) values {members};
insert into public.specialties(id,clinic_id,name) values('{specialty}','{clinic}','TEST Specialty');
insert into public.rooms(id,clinic_id,name) values('{room}','{clinic}','TEST Room');
insert into public.queues(id,clinic_id,specialty_id,doctor_id,room_id) values('{queue}','{clinic}','{specialty}','{doctor}','{room}');
insert into public.patients(id,clinic_id,name) values {patients};""")
    def issue(patient):return operation(reception,clinic,'checkin',{'patient_id':patient,'queue_id':queue,'priority':False,'token':secrets.token_hex(32)})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: results=list(pool.map(issue,patient_ids[:16]))
    if any(r.returncode for r in results):raise RuntimeError('Concurrent issue failed: '+str([r.stderr for r in results if r.returncode]))
    numbers=[json.loads(r.stdout.strip().splitlines()[-1])['number'] for r in results]
    assert sorted(numbers)==list(range(1,17)),numbers
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: duplicates=list(pool.map(issue,[patient_ids[-1]]*2))
    assert sum(r.returncode==0 for r in duplicates)==1,'Duplicate checkin race was not blocked'
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: calls=list(pool.map(lambda _:operation(doctor,clinic,'call',{'queue_id':queue}),range(8)))
    assert sum(r.returncode==0 for r in calls)==1,'Concurrent doctor calls were not serialized'
    assert sql("select count(*) from public.queue_tickets where status='called';").stdout.strip()=='1'
    print('PASS: 16 concurrent ticket issues have unique sequential numbers')
    print('PASS: concurrent duplicate arrival produces exactly one ticket')
    print('PASS: 8 concurrent doctor calls produce exactly one active call')
finally:
    command(CONTAINER,'dropdb','-U','postgres',DATABASE,check=True)
