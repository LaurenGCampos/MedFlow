import {config} from './config.js';
import {accessToken} from './auth.js';
export async function api(path, body) {
 const token = await accessToken();
 let response;
 try {
  response = await fetch(config.apiUrl+path,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 } catch {
  throw new Error('Não foi possível conectar à API MedFlow. Verifique se o servidor PHP está ativo na porta 8080.');
 }
 const result=await response.json();
 if(!response.ok) { if(response.status===401) {sessionStorage.removeItem('medflow.session'); location.assign('/login.html');} throw new Error(result.error?.message||'Falha na comunicação.'); }
 return result.data;
}
