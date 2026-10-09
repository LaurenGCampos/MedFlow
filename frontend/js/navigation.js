export const roleRoutes={admin:'/admin/index.html',doctor:'/medico/index.html',receptionist:'/recepcao/index.html',patient:'/paciente/index.html'};
export function homeFor(me,area='auto'){
 if(sessionStorage.getItem('medflow.invite'))return '/convite.html';
 if(area==='platform'){
  if(!me.platform_admin)throw new Error('Sua conta não possui acesso de superadministrador. Escolha outra área ou use a opção automática.');
  return '/superadmin/index.html';
 }
 if(area==='auto'&&me.platform_admin)return '/superadmin/index.html';
 const memberships=me.memberships.filter(m=>m.clinics?.status==='active'&&(area==='auto'||m.role===area));
 if(area!=='auto'&&!memberships.length)throw new Error('Sua conta não possui vínculo ativo com a área escolhida. Escolha outra área ou peça ao administrador da clínica para verificar seu vínculo.');
 const saved=sessionStorage.getItem('medflow.clinic');
 const selected=memberships.find(m=>m.clinic_id===saved)||memberships[0];
 if(!selected)return '/solicitacao.html';
 sessionStorage.setItem('medflow.clinic',selected.clinic_id);
 return roleRoutes[selected.role]||'/solicitacao.html';
}
