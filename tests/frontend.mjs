import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const root=new URL('../frontend/',import.meta.url);
// Execute the auth module with injected configuration and simulated transport.
const source=fs.readFileSync(new URL('js/auth.js',root),'utf8').replace("import { config } from './config.js';","const config={supabaseUrl:'https://test.supabase.co',publishableKey:'public'};");
const storage=new Map();globalThis.sessionStorage={getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};
const auth=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('login delegates password verification to Supabase',async()=>{globalThis.fetch=async(url,opts)=>{assert.match(url,/grant_type=password/);assert.equal(JSON.parse(opts.body).email,'owner@example.test');return {ok:true,json:async()=>({access_token:'token',refresh_token:'refresh',expires_in:3600})};};await auth.login('owner@example.test','password');assert.equal(auth.session().access_token,'token');assert.equal(JSON.stringify(auth.session()).includes('password'),false);});
test('expired sessions refresh before API access',async()=>{storage.set('medflow.session',JSON.stringify({access_token:'old',refresh_token:'refresh',expires_at:0}));globalThis.fetch=async(url)=>{assert.match(url,/grant_type=refresh_token/);return {ok:true,json:async()=>({access_token:'new',refresh_token:'next',expires_in:3600})};};assert.equal(await auth.accessToken(),'new');});
test('failed refresh clears local session',async()=>{storage.set('medflow.session',JSON.stringify({refresh_token:'expired',expires_at:0}));globalThis.fetch=async()=>({ok:false,status:401,json:async()=>({})});await assert.rejects(auth.accessToken());assert.equal(auth.session(),null);});

test('unconfirmed email explains the required confirmation',async()=>{globalThis.fetch=async()=>({ok:false,status:400,json:async()=>({code:'email_not_confirmed'})});await assert.rejects(auth.login('owner@example.test','password'),/Confirme seu e-mail/);});
test('invalid credentials have a specific message',async()=>{globalThis.fetch=async()=>({ok:false,status:400,json:async()=>({code:'invalid_credentials'})});await assert.rejects(auth.login('owner@example.test','password'),/E-mail ou senha incorretos/);});
