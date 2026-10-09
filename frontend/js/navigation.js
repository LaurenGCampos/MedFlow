export const roleRoutes={admin:'/admin/index.html',doctor:'/medico/index.html',receptionist:'/recepcao/index.html',patient:'/paciente/index.html'};
export function homeFor(me){
 if(sessionStorage.getItem('medflow.invite'))return '/convite.html';
 if(me.platform_admin)return '/superadmin/index.html';
 const memberships=me.memberships.filter(m=>m.clinics?.status==='active');
 const saved=sessionStorage.getItem('medflow.clinic');
 const selected=memberships.find(m=>m.clinic_id===saved)||memberships[0];
 if(!selected)return '/solicitacao.html';
 sessionStorage.setItem('medflow.clinic',selected.clinic_id);
 return roleRoutes[selected.role]||'/solicitacao.html';
}
