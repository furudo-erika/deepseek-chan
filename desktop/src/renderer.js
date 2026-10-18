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
  const action = data.actions.find(a => a.id === s.action) || data.actions[0];
  if (drawn !== action.id) { drawn = action.id; sprite(action).catch(() => { $('error').textContent = 'Artwork could not load.'; }); }
  $('pet').className = 'interactive ' + action.motion + (s.dancing ? ' dancing' : '') + (s.prefs.calm ? ' calm' : '') + (s.dragging ? ' dragging' : '');
  $('bubble').hidden = visiblePanel !== 'home' || (!s.line && !['reminding','resting'].includes(s.phase));
  $('line').textContent = s.phase === 'reminding' ? 'Eyes need a holiday. Five minutes? ♡' : s.phase === 'resting' ? 'Look far away. I’ll keep watch. ♡' : s.line;
  $('break-buttons').hidden = s.phase !== 'reminding';
  $('panel').hidden = visiblePanel === 'home';
  for (const name of ['chat','settings','actions','tasks']) $(name+'-panel').hidden = visiblePanel !== name;
  $('panel-title').textContent = { chat:'A little chat ♡', settings:'Make her comfy', actions:'279 little poses', tasks:'Task buddies' }[s.panel] || '';
  if (s.line) $('chat-line').textContent = s.line;
  $('chat-form').querySelector('button').disabled = s.chatBusy;
  $('error').textContent = s.error;
  for (const name of ['minutes','outfit']) if (document.activeElement !== $(name)) $(name).value = s.prefs[name];
  for (const name of ['chatter','calm','sound','tasks','ai']) $(name).checked = s.prefs[name];
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
$('chat-form').onsubmit=event=>{event.preventDefault();const value=$('chat-input').value;$('chat-input').value='';command('draft',false);command('chat',value);};
$('chat-input').oninput=()=>command('draft',!!$('chat-input').value.trim());
$('search').oninput=actionList;
for (const name of ['minutes','outfit','chatter','calm','sound','tasks','ai']) $(name).onchange=()=>command('settings',{[name]: name==='minutes'?Number($(name).value):name==='outfit'?$(name).value:$(name).checked});
$('save-key').onclick=async()=>{const key=$('api-key').value;$('api-key').value='';const result=await command('save-key',key);$('key-status').textContent=result?.ok?'Saved with Windows account encryption.':'Could not save this key.';};
$('remove-key').onclick=async()=>{await command('remove-key');$('api-key').value='';$('key-status').textContent='Key removed.';};
$('pet').onpointerdown=event=>{if(event.button!==0)return;down={x:event.screenX,y:event.screenY};dragging=false;$('pet').setPointerCapture(event.pointerId);command('drag-start');};
$('pet').onpointermove=event=>{if(down&&Math.hypot(event.screenX-down.x,event.screenY-down.y)>4)dragging=true;};
$('pet').onpointerup=()=>{command('drag-end');if(down&&!dragging)command('pat');down=null;dragging=false;};
$('pet').onpointercancel=()=>{down=null;dragging=false;command('drag-end');};
$('pet').oncontextmenu=event=>{event.preventDefault();command('panel','settings');};
$('pet').onkeydown=event=>{if(event.key==='Enter'||event.key===' ')command('pat');};
document.addEventListener('mousemove',event=>{const next=!event.target.closest('.interactive');if(next!==ignore){ignore=next;command('ignore',next);}});
document.addEventListener('keydown',event=>{if(event.key==='Escape')command('panel','home');});
api.load().then(value=>{data=value;actionList();render(data.state);api.onState(render);document.body.dataset.ready='true';}).catch(()=>{$('error').textContent='Could not start the companion.';});
