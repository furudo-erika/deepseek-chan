'use strict';
const $ = id => document.getElementById(id), api = window.pet;
let data, current, drawn = '', drawVersion = 0, lastTaskJSON = '', dragging = false, down, ignore = false;
const images = new Map();
const command = async (name, value) => { try { return await api.command(name, value); } catch { $('error').textContent = 'That little action could not finish. Try again.'; } };
async function sprite(action) {
  const version = ++drawVersion;
  let image = images.get(action.atlas);
  if (!image) {
    image = new Image(); image.src = data.assetURL + (action.atlas.startsWith('actions-') ? 'actions/' : '') + action.atlas + '.png';
    await image.decode(); images.set(action.atlas, image);
    if (images.size > 6) images.delete(images.keys().next().value);
  }
  if (version !== drawVersion) return;
  const canvas = $('pet'), ctx = canvas.getContext('2d'); ctx.clearRect(0, 0, 560, 560);
  const r = data.layouts[action.atlas]?.[action.frame] || [action.frame % 3 / 3, Math.floor(action.frame / 3) / 3, 1/3, 1/3];
  const scale = 520 / Math.max(r[2], r[3]), w = r[2] * scale, h = r[3] * scale, x = (560-w)/2, y = 550-h;
  ctx.save(); ctx.translate(x,y); ctx.beginPath(); ctx.rect(0,0,w,h);
  for (const cut of data.cutouts[action.atlas+':'+action.frame] || []) ctx.rect(cut[0]*w,cut[1]*h,cut[2]*w,cut[3]*h);
  ctx.clip('evenodd');
  const points = data.regions[action.atlas+':'+action.frame];
  if (points?.length) { ctx.beginPath(); points.forEach((p,i) => i ? ctx.lineTo(p[0]*w,p[1]*h) : ctx.moveTo(p[0]*w,p[1]*h)); ctx.closePath(); ctx.clip(); }
  ctx.drawImage(image,r[0]*image.width,r[1]*image.height,r[2]*image.width,r[3]*image.height,0,0,w,h); ctx.restore();
  canvas.dataset.action = action.id;
}
function render(s) {
  current = s;
  // A reminder temporarily covers panels without clearing the user's unsent draft.
  const visiblePanel = s.phase === 'reminding' ? 'home' : s.panel;
  document.body.dataset.panel = visiblePanel;
  $('quota-bubble').hidden = visiblePanel !== 'home' || ['resting','reminding'].includes(s.phase) || s.dancing;
  const action = data.actions.find(a => a.id === s.action) || data.actions[0];
  if (drawn !== action.id) { drawn = action.id; sprite(action).catch(() => { $('error').textContent = 'Artwork could not load.'; }); }
  $('pet').className = 'interactive ' + action.motion + (s.dancing ? ' dancing' : '') + (s.prefs.calm ? ' calm' : '') + (s.dragging ? ' dragging' : '');
  $('bubble').hidden = visiblePanel !== 'home' || (!s.line && !['reminding','resting'].includes(s.phase));
  $('line').textContent = s.phase === 'reminding' ? 'Eyes need a holiday. Five minutes? ♡' : s.phase === 'resting' ? 'Look far away. I’ll keep watch. ♡' : s.line;
  $('break-buttons').hidden = s.phase !== 'reminding';
  $('panel').hidden = visiblePanel === 'home';
  for (const name of ['usage','settings','actions','tasks']) $(name+'-panel').hidden = visiblePanel !== name;
  $('panel-title').textContent = { usage:'Coding Plan', settings:'Make her comfy', actions:'279 little poses', tasks:'Task buddies' }[s.panel] || '';
  renderUsage(s.usage);
  renderQuotaBubble(s.usage);
  $('error').textContent = s.error;
  for (const name of ['minutes','outfit']) if (document.activeElement !== $(name)) $(name).value = s.prefs[name];
  for (const name of ['chatter','calm','sound','tasks']) $(name).checked = s.prefs[name];
  $('pause').textContent = s.phase === 'paused' ? 'Resume timer' : 'Pause timer';
  const clock = Math.floor(s.remaining/60)+':'+String(s.remaining%60).padStart(2,'0');
  $('timer').textContent = { waiting:'Waiting for your mouse ♡', focusing:clock+' until an eye break', reminding:'A tiny eye-break dance', resting:clock+' · look far away', paused:'Eye timer paused' }[s.phase];
  const json = JSON.stringify(s.tasks);
  if (json !== lastTaskJSON) {
    lastTaskJSON = json; $('task-list').replaceChildren();
    if (!s.tasks.length) { const p = document.createElement('p'); p.textContent='Waiting for our first task. ♡'; $('task-list').append(p); }
    for (const task of s.tasks) { const row=document.createElement('div');row.className='task';const title=document.createElement('strong');title.textContent=task.title;const sub=document.createElement('small');sub.textContent=task.source+' · '+(task.stale?'No recent update':task.status);row.append(title,sub);$('task-list').append(row); }
  }
}
function actionList() {
  const query=$('search').value.toLowerCase(); $('action-list').replaceChildren();
  for (const action of data.actions.filter(a => (a.name+' '+a.category+' '+a.id).toLowerCase().includes(query))) { const button=document.createElement('button');button.textContent=action.name;button.onclick=()=>{ command('action',action.id);command('panel','home'); };$('action-list').append(button); }
}
document.querySelectorAll('[data-command]').forEach(button => button.onclick=()=>command(button.dataset.command));
document.querySelectorAll('[data-panel]').forEach(button => button.onclick=()=>command('panel',button.dataset.panel));
$('close-panel').onclick=()=>command('panel','home');
$('search').oninput=actionList;
for (const name of ['minutes','outfit','chatter','calm','sound','tasks']) $(name).onchange=()=>command('settings',{[name]: name==='minutes'?Number($(name).value):name==='outfit'?$(name).value:$(name).checked});
$('usage-save').onclick=async()=>{const value={id:$('usage-provider').value,key:$('usage-key').value};$('usage-key').value='';const result=await command('usage-save-key',value);$('usage-key-status').textContent=result?.ok?'Saved with Windows account encryption.':'Could not save this key.';};
$('usage-remove').onclick=async()=>{const result=await command('usage-remove-key',$('usage-provider').value);$('usage-key').value='';$('usage-key-status').textContent=result?.ok?'Key removed.':'Could not remove this key.';};
$('usage-provider').onchange=()=>{$('usage-key').value='';$('usage-key-status').textContent='';};
$('pet').onpointerdown=event=>{if(event.button!==0)return;down={x:event.screenX,y:event.screenY};dragging=false;$('pet').setPointerCapture(event.pointerId);command('drag-start');};
$('pet').onpointermove=event=>{if(down&&Math.hypot(event.screenX-down.x,event.screenY-down.y)>4)dragging=true;};
$('pet').onpointerup=()=>{command('drag-end');if(down&&!dragging)command('chatter-bubble');down=null;dragging=false;};
$('pet').onpointercancel=()=>{down=null;dragging=false;command('drag-end');};
$('pet').oncontextmenu=event=>{event.preventDefault();command('panel','settings');};
$('pet').onkeydown=event=>{if(event.key==='Enter'||event.key===' ')command('chatter-bubble');};
document.addEventListener('mousemove',event=>{const next=!event.target.closest('.interactive');if(next!==ignore){ignore=next;command('ignore',next);}});
document.addEventListener('keydown',event=>{if(event.key==='Escape')command('panel','home');});
let lastUsageJSON='';
function renderUsage(usage) {
  if(!usage)return;
  $('usage-refresh').disabled=usage.busy;
  $('usage-refresh').textContent=usage.busy?'Refreshing…':'Refresh';
  const json=JSON.stringify(usage.rows);if(json===lastUsageJSON)return;lastUsageJSON=json;
  $('usage-list').replaceChildren();
  function text(parent,tag,value,cls){const el=document.createElement(tag);el.textContent=value;if(cls)el.className=cls;parent.append(el);return el;}
  for(const row of usage.rows){
    const card=document.createElement('section');card.className='usage-card';card.dataset.provider=row.id;
    const header=document.createElement('div');header.className='usage-heading';text(header,'strong',row.name);text(header,'small',row.kind);card.append(header);
    for(const meter of row.meters){const line=document.createElement('div');line.className='usage-heading';text(line,'span',meter.label);text(line,'strong',Math.round(meter.remaining)+'% left');card.append(line);const bar=document.createElement('progress');bar.max=100;bar.value=meter.remaining;bar.setAttribute('aria-label',row.name+' '+meter.label+' remaining');if(meter.remaining<=10)bar.className='low';card.append(bar);if(meter.resetsAt)text(card,'small','Resets '+new Date(meter.resetsAt).toLocaleString());}
    for(const b of row.balances)text(card,'div',b.currency+' '+b.amount.toFixed(2),'usage-money');
    if(row.message)text(card,'p',row.message,'small');
    if(row.updatedAt)text(card,'small',(row.stale||row.status!=='ok'?'Last known · ':'Updated ')+new Date(row.updatedAt).toLocaleTimeString());
    $('usage-list').append(card);
  }
}
api.load().then(value=>{data=value;actionList();render(data.state);api.onState(render);document.body.dataset.ready='true';}).catch(()=>{$('error').textContent='Could not start the companion.';});

let lastQuotaJSON='';
function renderQuotaBubble(usage){
 if(!usage)return;
 const json=JSON.stringify(usage);if(json===lastQuotaJSON)return;lastQuotaJSON=json;
 $('quota-grid').replaceChildren();
 for(const row of usage.rows){
  const cell=document.createElement('div');cell.className='quota-cell';cell.dataset.quotaProvider=row.id;
  const meter=[...row.meters].sort((a,b)=>a.remaining-b.remaining)[0], old=row.status!=='ok'||row.stale;
  const heading=document.createElement('div');heading.className='quota-heading';const name=document.createElement('strong');name.textContent=row.name;heading.append(name);cell.append(heading);
  const caption=document.createElement('small');
  if(meter){
   const value=document.createElement('span');value.textContent=Math.round(meter.remaining)+'%';heading.append(value);
   const bar=document.createElement('progress');bar.max=100;bar.value=meter.remaining;bar.className=old?'stale':meter.remaining<=10?'low':'';bar.setAttribute('aria-label',row.name+' '+meter.label+' remaining'+(old?', last known':''));cell.append(bar);
   caption.textContent=meter.label+(old?' · old':'');
  }else if(row.balances.length){
   const value=document.createElement('span');value.className='quota-money';value.textContent=row.balances.map(b=>b.currency+' '+b.amount.toFixed(2)).join(' · ');cell.append(value);caption.textContent='API credits'+(old?' · old':'');
  }else caption.textContent=usage.busy?'Checking…':row.status==='disconnected'?'Not connected':'Unavailable';
  cell.append(caption);$('quota-grid').append(cell);
 }
}
