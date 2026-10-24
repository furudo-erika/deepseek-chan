const test=require('node:test'),assert=require('node:assert/strict');
const {providers,normalize}=require('../src/usage/core.js');
const {UsageService,cursorCookie,credentials,openCodeHeaders}=require('../src/usage/service.cjs');
const fixtures=require('../../Tests/usage-fixtures.json');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
test('All provider payloads normalize to remaining quota or real currency, without identity fields',()=>{
 for(const p of providers){const result=normalize(p.id,{...fixtures[p.id],email:'PRIVATE',access_token:'SECRET'});assert.ok(result.meters.length+result.balances.length);assert.ok(!JSON.stringify(result).includes('PRIVATE'));assert.ok(!JSON.stringify(result).includes('SECRET'));}
 assert.equal(normalize('codex',fixtures.codex).meters[0].remaining,76);
 assert.equal(normalize('claude',fixtures.claude).meters[2].label,'Fable weekly');
 assert.equal(normalize('opencode',fixtures.opencode).meters[0].remaining,77);
 assert.deepEqual(providers.map(p=>p.id),['codex','claude','grok','cursor','opencode']);
});
test('Missing values are unavailable, never invented as zero; zero and overage are valid',()=>{
 for(const p of providers)assert.throws(()=>normalize(p.id,{}));
 for(const value of [null,'',true,'bad',-1,Infinity])assert.throws(()=>normalize('grok',{creditUsagePercent:value}));
 assert.equal(normalize('grok',{creditUsagePercent:0}).meters[0].remaining,100);
 assert.equal(normalize('grok',{creditUsagePercent:120}).meters[0].remaining,0);
 assert.equal(normalize('opencode',{usage:{rolling:{status:'rate-limited',percent:100}}}).meters[0].remaining,0);
 assert.throws(()=>normalize('opencode',{usage:{rolling:{status:'unavailable',percent:0}}}));
 assert.throws(()=>normalize('cursor',{individualUsage:{plan:{enabled:false,totalPercentUsed:0}}}));
});
test('Grok currency fallback and Claude scoped windows preserve reset time',()=>{
 assert.equal(normalize('grok',{monthlyLimit:{val:'100'},used:{val:'25'}}).meters[0].remaining,75);
 assert.equal(normalize('claude',{limits:[{kind:'weekly_scoped',percent:3,scope:{model:{display_name:'Fable'}},resets_at:1893456000}]}).meters[0].resetsAt,1893456000000);
});
function harness(fetcher){let now=1000000;const service=new UsageService({home:'unused',appData:'unused',readKey:async()=>null,credentialReader:async()=>({Authorization:'Bearer fixture'}),fetcher,now:()=>now});return {service,advance:()=>{now+=300001;}};}
test('Transport is GET-only, bounded, no redirects; refresh coalesces and throttles',async()=>{
 let calls=0;const h=harness(async(url,options)=>{calls++;assert.equal(options.method,'GET');assert.equal(options.redirect,'error');assert.ok(options.signal);const p=providers.find(p=>p.url===url);return new Response(JSON.stringify(fixtures[p.id]));});
 await Promise.all([h.service.refresh(),h.service.refresh()]);await h.service.refresh();assert.equal(calls,5);assert.ok(h.service.snapshot().rows.every(r=>r.status==='ok'));assert.ok(!JSON.stringify(h.service.snapshot()).includes('Authorization'));
});
test('Failures retain clearly marked last-known values, never overwrite with raw server errors',async()=>{
 let fail=false;const h=harness(async url=>fail?new Response('PRIVATE ERROR',{status:401}):new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id])));
 await h.service.refresh();fail=true;h.advance();await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status==='expired'&&r.updatedAt));assert.ok(!JSON.stringify(h.service.snapshot()).includes('PRIVATE ERROR'));
});
test('429 backoff, oversized responses and malformed JSON fail closed',async()=>{
 for(const response of [()=>new Response('{}',{status:429,headers:{'retry-after':'3600'}}),()=>new Response('x'.repeat(262145)),()=>new Response('{bad')]){let count=0;const h=harness(async()=>{count++;return response();});await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status!=='ok'));if(h.service.rows[0].status==='limited'){h.advance();await h.service.refresh();assert.equal(count,5);}}
});
test('Removing a key fences an in-flight response from repopulating its quota',async()=>{
 let release;const wait=new Promise(r=>release=r);const h=harness(async url=>{await wait;return new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id]));});
 const pending=h.service.refresh();await new Promise(r=>setImmediate(r));h.service.clear('opencode');release();await pending;const row=h.service.rows.find(r=>r.id==='opencode');assert.equal(row.status,'disconnected');assert.deepEqual(row.balances,[]);
});
test('Credential discovery is isolated, allowlisted, and does not disclose account identities',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'usage-test-'));try{
  await fs.mkdir(path.join(root,'.grok'));await fs.writeFile(path.join(root,'.grok/auth.json'),JSON.stringify({'https://auth.x.ai.evil.invalid':{key:'wrong-credential'},'https://auth.x.ai::fixture-account':{key:'fixture-credential',user_id:'fixture-account',email:'PRIVATE'}}));
  const h=await credentials('grok',root,root,async()=>null,{});assert.equal(h.Authorization,'Bearer fixture-credential');assert.ok(!JSON.stringify(h).includes('PRIVATE'));
  assert.equal(await credentials('claude',root,root,async()=>null,{}),null);
  const jwt='test.'+Buffer.from(JSON.stringify({sub:'fixture-user'})).toString('base64url')+'.signature';assert.ok(cursorCookie(jwt).startsWith('WorkosCursorSessionToken=fixture-user%3A%3A'));assert.equal(cursorCookie('bad token'),null);
 }finally{await fs.rm(root,{recursive:true,force:true});}
});
test('An account switch clears old quota even if the new account request is denied',async()=>{
 let who='A',fail=false;const h=harness(async url=>fail?new Response('{}',{status:401}):new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id])));h.service.credentialReader=async()=>({Authorization:'Bearer '+who});
 await h.service.refresh();assert.equal(h.service.rows[0].meters.length,2);who='B';fail=true;h.advance();await h.service.refresh();assert.ok(h.service.rows.every(r=>r.updatedAt===null && r.meters.length===0 && r.balances.length===0));assert.ok(!JSON.stringify(h.service.snapshot()).includes('Bearer'));
});
test('Account changes during a fetch discard the old result and queue the new account',async()=>{
 let who='A',release;const gate=new Promise(r=>release=r);const h=harness(async url=>{await gate;return new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id]));});h.service.credentialReader=async()=>({Authorization:'Bearer '+who});
 const first=h.service.refresh();await new Promise(r=>setImmediate(r));who='B';release();await first;
 // The queued fetch is asynchronous; no A response can have been accepted before it.
 assert.ok(h.service.rows.every(r=>r.updatedAt===null));
 for(let i=0;i<100 && h.service.busy;i++)await new Promise(r=>setTimeout(r,5));
 assert.ok(h.service.rows.every(r=>r.status==='ok'));
});
test('A provider backoff cannot carry another account quota across a sign-in change',async()=>{
 let who='A',limited=false;const h=harness(async url=>limited?new Response('{}',{status:429,headers:{'retry-after':'3600'}}):new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id])));h.service.credentialReader=async()=>({Authorization:'Bearer '+who});
 await h.service.refresh();h.advance();limited=true;await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status==='limited'));
 who='B';limited=false;h.advance();await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status==='ok' && r.retryAt===null));
});

test('OpenCode accepts only its own key/OAuth formats and default host, without identity fields',()=>{
 const headers=openCodeHeaders({type:'oauth',access:'fixture-session',metadata:{server:'https://opencode.ai/console',orgID:'org_fixture',email:'PRIVATE',orgName:'PRIVATE'}});
 assert.equal(headers.Authorization,'Bearer fixture-session');assert.equal(headers['x-org-id'],'org_fixture');assert.equal(headers['x-opencode-org-id'],'org_fixture');assert.ok(!JSON.stringify(headers).includes('PRIVATE'));
 assert.equal(openCodeHeaders({type:'oauth',access:'fixture-session',metadata:{server:'https://example.invalid'}}),null);
 assert.equal(openCodeHeaders({type:'key',key:'bad\ncredential'}),null);
 assert.equal(openCodeHeaders({type:'external',key:'fixture-key'}),null);
 for(const id of ['deepseek','openrouter'])assert.throws(()=>normalize(id,{}));
});
test('OpenCode reads active scoped v2 credentials and legacy Go keys; removed providers never read keys',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'opencode-usage-'));
 try {
  const dir=path.join(root,'opencode');await fs.mkdir(dir);
  const env={XDG_DATA_HOME:root};let reads=0;const readKey=async id=>{reads++;assert.equal(id,'opencode');return null;};
  await fs.writeFile(path.join(dir,'auth.json'),JSON.stringify({'opencode-go':{type:'api',key:'legacy-go-key'},openai:{type:'api',key:'not-opencode'}}));
  assert.equal((await credentials('opencode',root,root,readKey,env)).Authorization,'Bearer legacy-go-key');
  const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync(path.join(dir,'opencode.db'));
  db.exec('CREATE TABLE credential (integration_id TEXT,value TEXT,active INTEGER,time_created INTEGER)');
  const put=db.prepare('INSERT INTO credential VALUES(?,?,?,?)');
  put.run('openai',JSON.stringify({type:'key',key:'not-opencode'}),1,4);
  put.run('opencode',JSON.stringify({type:'key',key:'inactive-key'}),0,3);
  put.run('opencode',JSON.stringify({type:'oauth',access:'active-session',metadata:{server:'https://opencode.ai/console',orgID:'org_fixture'}}),1,2);
  assert.equal((await credentials('opencode',root,root,readKey,env)).Authorization,'Bearer active-session');
  assert.equal((await credentials('opencode',root,root,async()=> 'explicit-go-key',env)).Authorization,'Bearer explicit-go-key');
  db.prepare('UPDATE credential SET value=? WHERE active=1 AND integration_id=?').run(JSON.stringify({type:'oauth',access:'custom-session',metadata:{server:'https://untrusted.invalid'}}),'opencode');
  assert.equal(await credentials('opencode',root,root,readKey,env),null,'Do not fall back to stale legacy identity');
  db.exec("UPDATE credential SET active=0 WHERE integration_id='opencode'");
  assert.equal(await credentials('opencode',root,root,readKey,env),null,'Inactive v2 entries must not revive a legacy sign-in');db.close();
  reads=0;for(const id of ['deepseek','openrouter'])assert.equal(await credentials(id,root,root,readKey,env),null);assert.equal(reads,0);
 } finally {await fs.rm(root,{recursive:true,force:true});}
});
