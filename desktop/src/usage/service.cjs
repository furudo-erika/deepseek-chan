'use strict';
const fs = require('node:fs/promises');
const constants = require('node:fs').constants;
const path = require('node:path');
const { providers, normalize } = require('./core.js');
const {createHash}=require('node:crypto');
function fingerprint(headers){return headers ? createHash('sha256').update(JSON.stringify(Object.entries(headers).sort())).digest('hex') : null;}
const MAX_BYTES = 256 * 1024;
async function readJSON(file) {
  let handle;
  try {
    const before=await fs.lstat(file);if(!before.isFile() || before.isSymbolicLink() || before.size>MAX_BYTES)return null;
    handle = await fs.open(file, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > MAX_BYTES || stat.ino!==before.ino || stat.dev!==before.dev) return null;
    const b = Buffer.alloc(MAX_BYTES+1); const {bytesRead} = await handle.read(b,0,b.length,0);
    return bytesRead <= MAX_BYTES ? JSON.parse(b.subarray(0,bytesRead).toString('utf8')) : null;
  } catch { return null; } finally { await handle?.close(); }
}
function token(value) { return typeof value === 'string' && value.length >= 10 && value.length < 16384 && !/[\s\r\n]/.test(value) ? value : null; }
function cursorCookie(raw) {
  if (!token(raw)) return null;
  try { const claims=JSON.parse(Buffer.from(raw.split('.')[1],'base64url')); if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length>256) return null; return 'WorkosCursorSessionToken='+encodeURIComponent(claims.sub)+'%3A%3A'+raw; } catch { return null; }
}
// Only OpenCode's own credential entries are read; provider URLs are never taken from local data.
function openCodeHeaders(value) {
  if (!value || typeof value!=='object') return null;
  const server=value.metadata?.server;
  if (server && !['https://opencode.ai/console','https://console.opencode.ai'].includes(String(server).replace(/\/$/,''))) return null;
  const key=value.type==='oauth'?value.access:['key','api'].includes(value.type)?value.key:null;
  if (!token(key)) return null;
  const headers={Authorization:'Bearer '+key,'User-Agent':'DeepSeek-chan'};
  const org=value.metadata?.orgID;
  if (typeof org==='string' && /^[A-Za-z0-9_-]{1,256}$/.test(org)) {headers['x-org-id']=org;headers['x-opencode-org-id']=org;}
  return headers;
}
async function openCodeCredentials(home, readKey, env) {
  const saved=await readKey('opencode');
  if (token(saved)) return openCodeHeaders({type:'key',key:saved});
  const root=path.join(env.XDG_DATA_HOME || path.join(home,'.local','share'),'opencode');
  let db;
  try {
    const file=path.join(root,'opencode.db'), info=await fs.lstat(file);
    if(info.isFile() && !info.isSymbolicLink()) {
      const {DatabaseSync}=require('node:sqlite'); db=new DatabaseSync(file,{readOnly:true});db.exec('PRAGMA busy_timeout=1000');
      const rows=db.prepare("SELECT value FROM credential WHERE integration_id IN ('opencode-go','opencode') AND (active=1 OR active IS NULL) ORDER BY CASE integration_id WHEN 'opencode-go' THEN 0 ELSE 1 END, active DESC, time_created DESC LIMIT 1").all();
      if(rows.length) {try{return typeof rows[0].value==='string' && rows[0].value.length<=262144 ? openCodeHeaders(JSON.parse(rows[0].value)) : null;}catch{return null;}}
      if(db.prepare("SELECT 1 FROM credential WHERE integration_id IN ('opencode-go','opencode') LIMIT 1").get())return null;
    }
  } catch {} finally {db?.close();}
  const legacy=await readJSON(path.join(root,'auth.json'));
  return openCodeHeaders(legacy?.['opencode-go'] ?? legacy?.opencode);
}
async function credentials(id, home, appData, readKey, env = process.env) {
  let value;
  if (id==='codex') {
    const d=await readJSON(path.join(env.CODEX_HOME || path.join(home,'.codex'),'auth.json')); const t=d?.tokens;
    if (token(t?.access_token)) { const h={Authorization:'Bearer '+t.access_token,'User-Agent':'codex-cli','OpenAI-Beta':'codex-1'}; if (token(t.account_id)) h['ChatGPT-Account-Id']=t.account_id; return h; }
  } else if (id==='claude') {
    const d=await readJSON(path.join(env.CLAUDE_CONFIG_DIR || path.join(home,'.claude'),'.credentials.json')); value=d?.claudeAiOauth?.accessToken;
    if (token(value)) return {Authorization:'Bearer '+value,'anthropic-beta':'oauth-2025-04-20','User-Agent':'claude-code/2.1.0'};
  } else if (id==='grok') {
    const d=await readJSON(path.join(env.GROK_HOME || path.join(home,'.grok'),'auth.json'));
    for (const [issuer,entry] of Object.entries(d || {})) {
      if (!(issuer==='https://auth.x.ai'||issuer.startsWith('https://auth.x.ai::')) || !token(entry?.key)) continue;
      const h={Authorization:'Bearer '+entry.key,'X-XAI-Token-Auth':'xai-grok-cli'};if(token(entry.user_id))h['x-userid']=entry.user_id;return h;
    }
  } else if (id==='cursor') {
    const root=process.platform==='win32'?path.join(appData,'Cursor'):path.join(home,'.cursor');
    const d=await readJSON(path.join(root,'auth.json'));value=d?.accessToken;
    if (!cursorCookie(value)) {
      const desktop=process.platform==='win32'?path.join(appData,'Cursor'):path.join(home,'Library','Application Support','Cursor');
      let db;
      try { const {DatabaseSync}=require('node:sqlite'); db=new DatabaseSync(path.join(desktop,'User','globalStorage','state.vscdb'),{readOnly:true});value=db.prepare("SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'").get()?.value; } catch {} finally { db?.close(); }
    }
    const cookie=cursorCookie(value);if(cookie)return {Cookie:cookie,Origin:'https://cursor.com',Referer:'https://cursor.com/dashboard'};
  } else if (id==='opencode') {
    return openCodeCredentials(home,readKey,env);
  }
  return null;
}
class UsageService {
  constructor({home, appData, readKey, fetcher=fetch, credentialReader=credentials, now=Date.now, notify=()=>{}}) {
    Object.assign(this,{home,appData,readKey,fetcher,credentialReader,now,notify});this.busy=false;this.lastAttempt=0;this.fingerprints=new Map();this.pending=false;this.rows=providers.map(p=>({...p,status:'disconnected',message:p.guide,meters:[],balances:[],updatedAt:null,attemptedAt:null,generation:0}));
  }
  snapshot() { return {busy:this.busy,rows:this.rows.map(({url,guide,...row})=>({...row,stale:row.updatedAt!==null && this.now()-row.updatedAt>600000}))}; }
  async sameAccount(row, headers, generation) {
    if(row.generation!==generation)return false;
    const current=await this.credentialReader(row.id,this.home,this.appData,this.readKey);
    if(row.generation!==generation)return false;
    if(fingerprint(current)===fingerprint(headers))return true;
    this.clear(row.id);row.message='Account changed. Refreshing…';this.pending=true;return false;
  }
  async refresh() {
    const now=this.now(); if(this.busy || (this.lastAttempt && now-this.lastAttempt<30000))return;
    this.lastAttempt=now;this.busy=true;this.notify();
    try { await Promise.all(this.rows.map(async(row)=>{
      const generation=row.generation;
      let status='error',message='Could not refresh. Try again later.';
      try {
        const h=await this.credentialReader(row.id,this.home,this.appData,this.readKey);
        if(row.generation!==generation)return;
        if(!h){this.fingerprints.delete(row.id);status='disconnected';message=row.guide;row.meters=[];row.balances=[];row.updatedAt=null;row.retryAt=null;return;}
        const identity=fingerprint(h);if(this.fingerprints.get(row.id)!==identity){row.meters=[];row.balances=[];row.updatedAt=null;row.retryAt=null;this.fingerprints.set(row.id,identity);}
        if(row.retryAt && now<row.retryAt){status=row.status;message=row.message;return;}
        const response=await this.fetcher(row.url,{method:'GET',headers:{...h,Accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(12000)});
        if(!(await this.sameAccount(row,h,generation))){await response.body?.cancel();return;}
        if(response.status===401 || response.status===403){await response.body?.cancel();status='expired';message='Sign-in expired or access denied. Reconnect in the provider app.';return;}
        if(response.status===429){await response.body?.cancel();status='limited';message='Provider is rate limiting requests. Retrying later.';const seconds=Number(response.headers.get('retry-after'));row.retryAt=now+Math.min(3600000,Math.max(300000,Number.isFinite(seconds)?seconds*1000:300000));return;}
        if(!response.ok){await response.body?.cancel();throw Error('request');}
        const reader=response.body.getReader();let total=0,chunks=[];
        while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>MAX_BYTES){await reader.cancel();throw Error('size');}chunks.push(Buffer.from(value));}
        const parsed=normalize(row.id,JSON.parse(Buffer.concat(chunks).toString('utf8')));
        if(!(await this.sameAccount(row,h,generation)))return;
        Object.assign(row,parsed,{updatedAt:this.now(),retryAt:null});status='ok';message='';
      } catch { /* No provider bodies in logs. Account changes also invalidate failed requests. */
        if(row.generation===generation){const current=await this.credentialReader(row.id,this.home,this.appData,this.readKey).catch(()=>null);if(fingerprint(current)!==(this.fingerprints.get(row.id)||null)){this.clear(row.id);this.pending=true;}}
      }
      finally {if(row.generation===generation){Object.assign(row,{status,message,attemptedAt:this.now()});this.notify();}}
    })); } finally {this.busy=false;this.notify();if(this.pending){this.pending=false;this.lastAttempt=0;void this.refresh();}}
  }
  clear(id) {if(this.busy)this.pending=true;this.fingerprints.delete(id);const row=this.rows.find(r=>r.id===id);if(row)Object.assign(row,{meters:[],balances:[],updatedAt:null,status:'disconnected',message:row.guide,retryAt:null,generation:row.generation+1});this.lastAttempt=0;this.notify();}
}
module.exports={UsageService,credentials,cursorCookie,readJSON,openCodeHeaders};
