import { config } from './config.js';
const key = 'medflow.session';
export function session() { try { return JSON.parse(sessionStorage.getItem(key)); } catch { return null; } }
function save(data) { if (data?.access_token) sessionStorage.setItem(key, JSON.stringify({...data, expires_at: Math.floor(Date.now()/1000) + data.expires_in})); }
export async function authRequest(path, body, token, method = 'POST') {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/${path}`, { method, headers: { apikey: config.publishableKey, 'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {}) }, ...(body ? {body:JSON.stringify(body)} : {}) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(response.status === 429 ? 'Muitas tentativas. Aguarde e tente novamente.' : 'Não foi possível autenticar. Confira os dados ou solicite um novo link.');
  return data;
}
let refreshing;
export async function accessToken() {
  let data = session(); if (!data) throw new Error('Faça login para continuar.');
  if (data.expires_at < Date.now()/1000 + 60) {
    refreshing ||= authRequest('token?grant_type=refresh_token', {refresh_token:data.refresh_token}).then(result => {save(result); return result;}).catch(error => {sessionStorage.removeItem(key); throw error;}).finally(() => {refreshing = null;});
    data = await refreshing;
  }
  return data.access_token;
}
export async function login(email,password) { save(await authRequest('token?grant_type=password',{email,password})); }
export async function signup(email,password,name) { const data = await authRequest(`signup?redirect_to=${encodeURIComponent(location.origin+'/login.html')}`,{email,password,data:{display_name:name}}); save(data); }
export async function logout() { try { await authRequest('logout',null,await accessToken()); } finally {sessionStorage.removeItem(key); location.assign('/login.html');} }
export async function recover(email) { await authRequest(`recover?redirect_to=${encodeURIComponent(location.origin+'/recuperar.html')}`,{email}); }
export async function changePassword(password) { await authRequest('user',{password},await accessToken(),'PUT'); }
export async function callback() {
 const hash = new URLSearchParams(location.hash.slice(1));
 if (!hash.has('access_token')) return false;
 const token=hash.get('access_token');
 const user=await authRequest('user',null,token,'GET');
 save({access_token:token,refresh_token:hash.get('refresh_token'),expires_in:Number(hash.get('expires_in')||3600),user});
 history.replaceState(null,'',location.pathname); return true;
}
