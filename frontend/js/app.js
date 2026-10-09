import {login,signup,logout,recover,changePassword,callback,session} from './auth.js';
import {api} from './api.js';
import {homeFor} from './navigation.js';
const page=document.body.dataset.page;
document.querySelector('#cancel-decision')?.addEventListener('click',()=>document.querySelector('#decision-dialog').close());
const message=document.querySelector('#message');
function tell(text,error=false){ message.textContent=text; message.className=error?'notice error':'notice'; }
function el(tag,text,className){ const node=document.createElement(tag); if(text!==undefined) node.textContent=text; if(className)node.className=className; return node; }
function row(values){ const tr=el('tr'); for(const value of values)tr.append(el('td',value));return tr; }
const labels={pending:'Em análise',active:'Aprovada',rejected:'Rejeitada',suspended:'Suspensa',admin:'Administrador',doctor:'Médico',receptionist:'Recepcionista',patient:'Paciente'};
function pendingEntry(request){
 const tr=row([request.name,request.contact_email,request.city,new Date(request.created_at).toLocaleDateString('pt-BR')]);
 const td=el('td'); const approve=el('button','Aprovar'); const reject=el('button','Rejeitar','secondary');
 approve.onclick=()=>openDecision(request,'approve');reject.onclick=()=>openDecision(request,'reject');td.append(approve,reject);tr.append(td);return tr;
}
function openDecision(request,decision){
 const dialog=document.querySelector('#decision-dialog'); const form=dialog.querySelector('form');
 dialog.querySelector('h2').textContent=`${decision==='approve'?'Aprovar':'Rejeitar'} ${request.name}`;
 const reason=form.elements.reason;reason.value='';reason.required=decision==='reject';reason.closest('label').hidden=decision!=='reject';
 form.onsubmit=async event=>{event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;try{await api(`/requests/${request.id}/decision`,{decision,reason:reason.value});dialog.close();await dashboard();tell('Decisão registrada.');}catch(error){dialog.querySelector('[role=alert]').textContent=error.message;}finally{button.disabled=false;}};
 dialog.querySelector('[role=alert]').textContent='';dialog.showModal();
}
async function dashboard(){
 const data=await api('/platform/dashboard');
 document.querySelector('#pending-count').textContent=data.requests.length;
 document.querySelector('#active-count').textContent=data.clinics.filter(c=>c.status==='active').length;
 document.querySelector('#clinic-count').textContent=data.clinics.length;
 const list=document.querySelector('#pending');list.replaceChildren(...data.requests.map(pendingEntry));
 if(!data.requests.length)list.append(row(['Nenhuma solicitação pendente.','','','','']));
 document.querySelector('#clinics').replaceChildren(...data.clinics.map(c=>{const tr=row([c.name,labels[c.status],new Date(c.created_at).toLocaleDateString('pt-BR')]);const td=el('td');const b=el('button',c.status==='active'?'Suspender':'Ativar','secondary');b.onclick=()=>{const dialog=document.querySelector('#decision-dialog');const form=dialog.querySelector('form');dialog.querySelector('h2').textContent=`${c.status==='active'?'Suspender':'Ativar'} ${c.name}`;const reason=form.elements.reason;reason.value='';reason.required=true;reason.closest('label').hidden=false;form.onsubmit=async event=>{event.preventDefault();const submit=form.querySelector('[type=submit]');submit.disabled=true;try{await api(`/clinics/${c.id}/status`,{status:c.status==='active'?'suspended':'active',reason:reason.value});dialog.close();await dashboard();tell('Situação da clínica atualizada.');}catch(e){dialog.querySelector('[role=alert]').textContent=e.message;}finally{submit.disabled=false;}};dialog.querySelector('[role=alert]').textContent='';dialog.showModal();};td.append(b);tr.append(td);return tr;}));
 document.querySelector('#audit').replaceChildren(...data.audit.map(a=>row([a.action,a.target_id,new Date(a.created_at).toLocaleString('pt-BR')])));
}
async function owner(){
 const requests=await api('/requests');document.querySelector('#requests').replaceChildren(...requests.map(r=>row([r.name,labels[r.status],r.reason||'—'])));
 if(!requests.length)document.querySelector('#requests').append(row(['Você ainda não enviou uma solicitação.','','']));
}
async function start(){
 if(page==='landing')return;
 const fromCallback=await callback();
 if(fromCallback&&page==='login'){const me=await api('/me');location.assign(homeFor(me));return;}
 document.querySelector('#logout')?.addEventListener('click',()=>logout().catch(error=>tell(error.message,true)));
 if(['owner','platform','clinic'].includes(page)){
  if(!session()){location.replace('/login.html');return;}
  const me=await api('/me');document.querySelector('#identity').textContent=me.email;
  if(page==='platform'){if(!me.platform_admin){location.replace('/solicitacao.html');return;}await dashboard();}
  if(page==='owner'){document.querySelector('#platform-link').hidden=!me.platform_admin;await owner();}
  if(page==='clinic'){
   const select=document.querySelector('#clinic-select');const memberships=me.memberships.filter(m=>m.clinics?.status==='active');
   for(const m of memberships){const option=el('option',`${m.clinics.name} · ${labels[m.role]}`);option.value=m.clinic_id;select.append(option);}
   const selected=sessionStorage.getItem('medflow.clinic');if(memberships.some(m=>m.clinic_id===selected))select.value=selected;
   select.onchange=()=>sessionStorage.setItem('medflow.clinic',select.value);
   if(!memberships.length)tell('Nenhum vínculo com clínica ativa. Envie ou acompanhe sua solicitação.');
  }
 }
 document.querySelector('#main-form')?.addEventListener('submit',async event=>{
  event.preventDefault();const form=event.currentTarget;const body=Object.fromEntries(new FormData(form));const button=form.querySelector('[type=submit]');button.disabled=true;tell('Processando…');
  try{
   if(page==='login'){await login(body.email,body.password);const me=await api('/me');location.assign(homeFor(me,body.area||'auto'));}
   if(page==='signup'){await signup(body.email,body.password,body.name);form.reset();tell('Cadastro recebido. Confira seu e-mail para confirmar a conta e depois faça login.');}
   if(page==='recover'){if(session()&&new URLSearchParams(location.search).get('mode')==='password'){await changePassword(body.password);tell('Senha atualizada.');}else{await recover(body.email);tell('Se o e-mail estiver cadastrado, você receberá um link para recuperar a senha.');}}
   if(page==='owner'){await api('/requests',body);form.reset();await owner();tell('Solicitação enviada para análise.');}
  }catch(error){tell(error.message,true);}finally{button.disabled=false;}
 });
 if(page==='recover'&&session()){
  document.querySelector('#recovery-email').hidden=true;document.querySelector('#recovery-email input').required=false;
  document.querySelector('#recovery-password').hidden=false;document.querySelector('#recovery-password input').required=true;
  history.replaceState(null,'',location.pathname+'?mode=password');
 }
 tell(message.textContent==='Carregando…'?'':message.textContent);
}
start().catch(error=>tell(error.message,true));
