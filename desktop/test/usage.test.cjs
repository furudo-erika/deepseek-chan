const test=require('node:test'),assert=require('node:assert/strict');
const {providers,normalize}=require('../src/usage/core.js');
const {UsageService,cursorCookie,credentials}=require('../src/usage/service.cjs');
const fixtures=require('../../Tests/usage-fixtures.json');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
test('All provider payloads normalize to remaining quota or real currency, without identity fields',()=>{
 for(const p of providers){const result=normalize(p.id,{...fixtures[p.id],email:'PRIVATE',access_token:'SECRET'});assert.ok(result.meters.length+result.balances.length);assert.ok(!JSON.stringify(result).includes('PRIVATE'));assert.ok(!JSON.stringify(result).includes('SECRET'));}
 assert.equal(normalize('codex',fixtures.codex).meters[0].remaining,76);
 assert.equal(normalize('claude',fixtures.claude).meters[2].label,'Fable weekly');
 assert.equal(normalize('openrouter',fixtures.openrouter).balances[0].amount,12.75);
});
test('Missing values are unavailable, never invented as zero; zero and overage are valid',()=>{
 for(const p of providers)assert.throws(()=>normalize(p.id,{}));
 for(const value of [null,'',true,'bad',-1,Infinity])assert.throws(()=>normalize('grok',{creditUsagePercent:value}));
 assert.equal(normalize('grok',{creditUsagePercent:0}).meters[0].remaining,100);
 assert.equal(normalize('grok',{creditUsagePercent:120}).meters[0].remaining,0);
 assert.equal(normalize('openrouter',{data:{total_credits:1,total_usage:2}}).balances[0].amount,-1);
 assert.throws(()=>normalize('cursor',{individualUsage:{plan:{enabled:false,totalPercentUsed:0}}}));
});
test('Grok currency fallback and Claude scoped windows preserve reset time',()=>{
 assert.equal(normalize('grok',{monthlyLimit:{val:'100'},used:{val:'25'}}).meters[0].remaining,75);
 assert.equal(normalize('claude',{limits:[{kind:'weekly_scoped',percent:3,scope:{model:{display_name:'Fable'}},resets_at:1893456000}]}).meters[0].resetsAt,1893456000000);
});
function harness(fetcher){let now=1000000;const service=new UsageService({home:'unused',appData:'unused',readKey:async()=>null,credentialReader:async()=>({Authorization:'Bearer fixture'}),fetcher,now:()=>now});return {service,advance:()=>{now+=300001;}};}
test('Transport is GET-only, bounded, no redirects; refresh coalesces and throttles',async()=>{
 let calls=0;const h=harness(async(url,options)=>{calls++;assert.equal(options.method,'GET');assert.equal(options.redirect,'error');assert.ok(options.signal);const p=providers.find(p=>p.url===url);return new Response(JSON.stringify(fixtures[p.id]));});
 await Promise.all([h.service.refresh(),h.service.refresh()]);await h.service.refresh();assert.equal(calls,6);assert.ok(h.service.snapshot().rows.every(r=>r.status==='ok'));assert.ok(!JSON.stringify(h.service.snapshot()).includes('Authorization'));
});
test('Failures retain clearly marked last-known values, never overwrite with raw server errors',async()=>{
 let fail=false;const h=harness(async url=>fail?new Response('PRIVATE ERROR',{status:401}):new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id])));
 await h.service.refresh();fail=true;h.advance();await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status==='expired'&&r.updatedAt));assert.ok(!JSON.stringify(h.service.snapshot()).includes('PRIVATE ERROR'));
});
test('429 backoff, oversized responses and malformed JSON fail closed',async()=>{
 for(const response of [()=>new Response('{}',{status:429,headers:{'retry-after':'3600'}}),()=>new Response('x'.repeat(262145)),()=>new Response('{bad')]){let count=0;const h=harness(async()=>{count++;return response();});await h.service.refresh();assert.ok(h.service.rows.every(r=>r.status!=='ok'));if(h.service.rows[0].status==='limited'){h.advance();await h.service.refresh();assert.equal(count,6);}}
});
test('Removing a key fences an in-flight response from repopulating its quota',async()=>{
 let release;const wait=new Promise(r=>release=r);const h=harness(async url=>{await wait;return new Response(JSON.stringify(fixtures[providers.find(p=>p.url===url).id]));});
 const pending=h.service.refresh();await new Promise(r=>setImmediate(r));h.service.clear('deepseek');release();await pending;const row=h.service.rows.find(r=>r.id==='deepseek');assert.equal(row.status,'disconnected');assert.deepEqual(row.balances,[]);
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
