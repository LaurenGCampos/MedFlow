import {config} from './config.js';
import {accessToken} from './auth.js';
export async function api(path, body) {
 const response = await fetch(config.apiUrl+path,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${await accessToken()}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 const result=await response.json();
 if(!response.ok) { if(response.status===401) {sessionStorage.removeItem('medflow.session'); location.assign('/login.html');} throw new Error(result.error?.message||'Falha na comunicação.'); }
 return result.data;
}
