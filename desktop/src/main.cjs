'use strict';
const { app, BrowserWindow, ipcMain, Menu, Tray, screen, powerMonitor, nativeImage, safeStorage, shell, session, clipboard } = require('electron');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { FocusTimer, Deck, TaskQueue, validTask, clamp, cleanReply } = require('./core.cjs');
app.setName('DeepSeek-chan');
const testing = process.env.DEEPSEEK_CHAN_TEST === '1';
if (testing && process.env.DEEPSEEK_CHAN_TEST_HOME) app.setPath('userData', process.env.DEEPSEEK_CHAN_TEST_HOME);
const assets = app.isPackaged ? path.join(process.resourcesPath, 'assets') : path.join(__dirname, '../../Assets');
const integrations = app.isPackaged ? path.join(process.resourcesPath, 'integrations') : path.join(__dirname, '../../integrations');
const actions = JSON.parse(fs.readFileSync(path.join(assets, 'action-library.json'))).actions;
const actionMap = new Map(actions.map(a => [a.id, a]));
const configFile = path.join(app.getPath('userData'), 'preferences.json');
const keyFile = path.join(app.getPath('userData'), 'ai-key.bin');
const defaults = { minutes: 20, outfit: 'classic', chatter: true, calm: false, tasks: true, sound: true, ai: false };
let prefs = { ...defaults };
try { const p = JSON.parse(fs.readFileSync(configFile)); for (const k of Object.keys(defaults)) if (typeof p[k] === typeof defaults[k]) prefs[k] = p[k]; } catch {}
if (![15, 20, 25, 30, 45, 60].includes(prefs.minutes)) prefs.minutes = 20;
if (!['classic', 'halloween'].includes(prefs.outfit)) prefs.outfit = 'classic';
const timer = new FocusTimer(prefs.minutes), deck = new Deck(), storyDeck = new Deck();
let tasks = new TaskQueue(), win, tray, homeBounds, drag, moving, lastPointer, pollBusy = false, hidden = false;
let action = 'wave', line = 'Your little companion is here. ♡', lineUntil = Date.now() + 7000, panel = 'home', draft = false, lastTyped = 0;
let nextPose = 0, nextChatter = Date.now() + 120000, danceUntil = 0, routine = [], nextBeat = 0, chatBusy = false, lastAI = 0, aiCalls = [];
let lastFailure = '', saveTimer;
function save() { clearTimeout(saveTimer); saveTimer = setTimeout(() => { try { fs.mkdirSync(path.dirname(configFile), { recursive: true }); const tmp = configFile + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(prefs)); fs.renameSync(tmp, configFile); } catch { lastFailure = 'Could not save preferences.'; } }, 200); }
function themed(id) {
  if (prefs.outfit !== 'halloween' || id.startsWith('halloween_')) return id;
  const map = { nap: 'rest', wave: 'hat_hello', hug: 'ghost_cuddle', cookie: 'cookie', laugh: 'giggle', wand: 'wand', disco: 'dance_right', ballet: 'twirl', conductor: 'dance_left', shy_peek: 'shy' };
  return 'halloween_' + (map[id] || 'hat_hello');
}
function pose(id, words, duration = 6500) { action = themed(actionMap.has(id) ? id : 'wave'); if (words) { line = words; lineUntil = Date.now() + duration; } nextPose = Date.now() + duration; }
function state() {
  const now = Date.now();
  let visibleAction = action;
  if (timer.phase === 'resting') visibleAction = themed('nap');
  else if (timer.phase === 'reminding' || now < danceUntil) visibleAction = themed(['conductor', 'disco', 'ballet'][Math.floor(now / 420) % 3]);
  return { action: visibleAction, line: now < lineUntil ? line : '', panel, prefs, phase: timer.phase, remaining: Math.max(0, Math.ceil(((timer.deadline || now + prefs.minutes * 60000) - now) / 1000)), completed: timer.completed,
    dancing: timer.phase === 'reminding' || now < danceUntil, dragging: !!drag, chatBusy, error: lastFailure,
    tasks: [...tasks.tasks.values()].sort((a, b) => b.updated_at - a.updated_at).slice(0, 20).map(t => ({ ...t, stale: ['working','waiting'].includes(t.status) && now / 1000 - t.updated_at > 300 })) };
}
function broadcast() { if (win && !win.isDestroyed()) win.webContents.send('pet:state', state()); }
function speakTask(t) {
  const phrases = { working: ['Tiny keyboard buddy, reporting for duty! ⌨', '开工啦，我陪你。♡'], waiting: ['Psst… your task needs you. ♡', '轮到你啦～'], completed: ['A little victory dance for you! ✧', 'できた！おつかれさま ♡'], failed: ['A tiny snag. I’m staying with you. ♡', '先抱一下，再一起修。'], cancelled: ['Paused adventure. Tea break? ☕'], idle: ['Quiet for a moment. I’ll stay here. ♡'] };
  const poses = { working: 'relax', waiting: 'wave', completed: 'disco', failed: 'hug', cancelled: 'nap', idle: 'nap' };
  const options = phrases[t.status]; pose(poses[t.status], options[Math.floor(Math.random() * options.length)]);
}
function stories() {
  const pool = actions.filter(a => prefs.outfit === 'halloween' ? a.id.startsWith('halloween_') : a.atlas.startsWith('actions-extra-'));
  return Array.from({ length: Math.floor(pool.length / 3) }, (_, i) => pool.slice(i * 3, i * 3 + 3));
}
function startStory() { const list = stories(); const index = storyDeck.next(list.map((_, i) => String(i))); routine = [...(list[Number(index)] || [])]; nextBeat = 0; }
function restorePosition() { if (homeBounds && win && !drag) win.setBounds(clamp(homeBounds, screen.getDisplayMatching(homeBounds).workArea)); }
function centerDance() {
  if (!win || hidden) return;
  const before = win.getBounds(); homeBounds = before;
  const work = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  const to = clamp({ ...before, x: work.x + (work.width - before.width) / 2, y: work.y + (work.height - before.height) / 2 }, work);
  const started = Date.now(); clearInterval(moving); win.showInactive();
  moving = setInterval(() => { const t = Math.min(1, (Date.now() - started) / 700), ease = 1 - Math.pow(1 - t, 3); if (drag || win.isDestroyed()) { clearInterval(moving); return; } win.setPosition(Math.round(before.x + (to.x - before.x) * ease), Math.round(before.y + (to.y - before.y) * ease)); if (t === 1) clearInterval(moving); }, 16);
  pose('disco', 'Eyes need a little holiday. Five minutes? ♡', 30000);
  if (prefs.sound) shell.beep();
}
async function pollTasks() {
  if (!prefs.tasks || pollBusy) return;
  pollBusy = true;
  try {
    const dir = path.join(process.env.DEEPSEEK_CHAN_HOME || path.join(app.getPath('home'), '.deepseek-chan'), 'tasks');
    let names; try { names = (await fsp.readdir(dir)).slice(0, 256); } catch (e) { if (e.code === 'ENOENT') return; throw e; }
    const rows = [];
    for (const name of names) {
      if (!name.endsWith('.json')) continue;
      let handle;
      try {
        const file = path.join(dir, name), info = await fsp.lstat(file);
        if (!info.isFile() || info.isSymbolicLink() || info.size > 8192) continue;
        handle = await fsp.open(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
        const opened = await handle.stat();
        if (!opened.isFile() || opened.size > 8192 || opened.ino !== info.ino || opened.dev !== info.dev) continue;
        const buffer = Buffer.alloc(8193); const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
        if (bytesRead <= 8192) { const row = JSON.parse(buffer.subarray(0, bytesRead)); if (validTask(row)) rows.push(row); }
      } catch {} finally { await handle?.close().catch(() => {}); }
    }
    tasks.ingest(rows);
  } catch { lastFailure = 'Cannot read the local task inbox.'; } finally { pollBusy = false; }
}
function tick() {
  if (!win || win.isDestroyed()) return;
  const now = Date.now(), pointer = screen.getCursorScreenPoint(), phase = timer.phase;
  const moved = lastPointer && (pointer.x !== lastPointer.x || pointer.y !== lastPointer.y); lastPointer = pointer;
  timer.tick(now, !!moved, powerMonitor.getSystemIdleTime());
  if (phase !== 'reminding' && timer.phase === 'reminding') { routine = []; centerDance(); }
  if (phase === 'resting' && timer.phase === 'waiting') { restorePosition(); pose('wave', 'Welcome back, fresh little eyes! ♡'); }
  const blocked = hidden || drag || draft || now - lastTyped < 30000 || ['reminding', 'resting', 'paused'].includes(timer.phase) || ['settings', 'actions', 'tasks'].includes(panel) || chatBusy;
  if (!blocked) {
    const task = prefs.tasks && tasks.next(now, false);
    if (task) { routine = []; speakTask(task); }
    else if (routine.length && now >= nextBeat) { const beat = routine.shift(); pose(beat.id, beat.line, 4500); nextBeat = now + 4500; }
    else if (!routine.length && prefs.chatter && now >= nextChatter && powerMonitor.getSystemIdleTime() < 600) { startStory(); nextChatter = now + 120000 + Math.random() * 60000; }
    else if (!routine.length && now > nextPose && now > danceUntil) { const pool = actions.filter(a => a.id.startsWith('halloween_') === (prefs.outfit === 'halloween')); action = deck.next(pool.map(a => a.id)); nextPose = now + (prefs.calm ? 18000 : 7000 + Math.random() * 6000); }
  }
  broadcast();
}
async function aiReply(message) {
  if (!prefs.ai || !fs.existsSync(keyFile)) return '';
  const now = Date.now(); aiCalls = aiCalls.filter(t => now - t < 3600000);
  if (now - lastAI < 12000 || aiCalls.length >= 40) return '';
  lastAI = now; aiCalls.push(now);
  try {
    const key = safeStorage.decryptString(await fsp.readFile(keyFile));
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000), headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key }, body: JSON.stringify({ model: 'deepseek/deepseek-v4.1-flash', max_tokens: 120, temperature: .95, messages: [{ role: 'system', content: 'You are DeepSeek-chan, a tiny blue-haired desktop companion. Reply with one cute short sentence under 90 characters. English, occasional Chinese/Japanese. No markdown. Never claim access to files or screens.' }, { role: 'user', content: message }] }) });
    if (!response.ok) throw Error('Unavailable');
    const reader = response.body.getReader(); let size = 0, chunks = [];
    while (true) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > 16384) { await reader.cancel(); throw Error('Oversize'); } chunks.push(Buffer.from(part.value)); }
    return cleanReply(JSON.parse(Buffer.concat(chunks)).choices?.[0]?.message?.content);
  } catch { lastFailure = 'AI is unavailable. Local little replies still work.'; return ''; }
}
async function chat(message) {
  if (chatBusy || typeof message !== 'string' || !message.trim() || message.length > 300) return;
  chatBusy = true; routine = []; lastFailure = '';
  const text = message.trim(), lower = text.toLowerCase();
  let id = 'wave', words = ['I saved a tiny cloud just for you. ☁', '今日もいっしょ。♡', '摸摸头，烦恼飞走～'][Math.floor(Math.random() * 3)];
  if (/stop|停|やめ/.test(lower)) { danceUntil = 0; words = 'Okay, quiet little company. ♡'; }
  else if (/dance|跳舞|踊/.test(lower)) { id = 'disco'; words = 'One, two… tiny whale shuffle! ♪'; danceUntil = Date.now() + 10000; }
  else if (/food|feed|snack|cookie|吃|喂/.test(lower)) { id = 'cookie'; words = 'Nom nom… saving you the bigger half. ♡'; }
  else if (/hug|抱|摸/.test(lower)) { id = 'hug'; words = 'ぎゅー！ A pocket-sized hug. ♡'; }
  else if (/joke|笑话/.test(lower)) { id = 'laugh'; words = 'My code has bugs. I named them all Mochi. 🐛'; }
  else if (/magic|魔法/.test(lower)) { id = 'wand'; words = 'ぽん！ Your tiredness is now a marshmallow. ✧'; }
  else if (/again|再来/.test(lower)) { id = action; words = line || words; }
  else { const reply = await aiReply(text); if (reply) words = reply; }
  pose(id, words, 10000); chatBusy = false; broadcast();
}
function trusted(event) { return win && event.sender === win.webContents && event.senderFrame === win.webContents.mainFrame; }
ipcMain.handle('pet:load', event => { if (!trusted(event)) throw Error('Unknown sender'); return { actions, layouts: JSON.parse(fs.readFileSync(path.join(assets, 'atlas-layout.json'))), cutouts: JSON.parse(fs.readFileSync(path.join(assets, 'atlas-cutouts.json'))), regions: JSON.parse(fs.readFileSync(path.join(assets, 'atlas-regions.json'))), assetURL: pathToFileURL(assets + path.sep).href, integrationPath: integrations, state: state() }; });
ipcMain.handle('pet:command', async (event, name, value) => {
  if (!trusted(event)) throw Error('Unknown sender');
  switch (name) {
    case 'test-reminder': if (testing) { timer.phase = 'reminding'; timer.deadline = null; centerDance(); } break;
    case 'panel': if (['home','chat','settings','actions','tasks'].includes(value)) { panel = value; broadcast(); } break;
    case 'draft': draft = value === true; lastTyped = Date.now(); break;
    case 'chat': await chat(value); break;
    case 'pat': pose('hug', 'Head pats recharge my tiny heart. ♡'); break;
    case 'dance': routine = []; danceUntil = Date.now() + 10000; pose('disco', 'Tiny dance delivery! ♪'); break;
    case 'story': startStory(); break;
    case 'action': if (actionMap.has(value)) { routine = []; pose(value, actionMap.get(value).line); } break;
    case 'rest': timer.rest(Date.now()); routine = []; restorePosition(); pose('nap', 'Look far away. I’ll keep watch. ♡', 300000); break;
    case 'snooze': timer.snooze(Date.now()); restorePosition(); break;
    case 'pause': timer.pause(); routine = []; restorePosition(); break;
    case 'settings':
      if (!value || typeof value !== 'object') break;
      if ([15,20,25,30,45,60].includes(value.minutes)) { prefs.minutes = value.minutes; timer.interval(value.minutes, Date.now()); }
      if (['classic','halloween'].includes(value.outfit)) { prefs.outfit = value.outfit; routine = []; action = value.outfit === 'halloween' ? 'halloween_hat_hello' : 'wave'; }
      for (const k of ['chatter','calm','tasks','sound','ai']) if (typeof value[k] === 'boolean') { prefs[k] = value[k]; if (k === 'tasks') tasks = new TaskQueue(); }
      save(); break;
    case 'save-key':
      if (typeof value !== 'string' || value.length < 20 || value.length > 512 || /\s/.test(value) || !safeStorage.isEncryptionAvailable()) return { ok: false };
      await fsp.mkdir(path.dirname(keyFile), { recursive: true }); await fsp.writeFile(keyFile, safeStorage.encryptString(value)); return { ok: true };
    case 'remove-key': await fsp.rm(keyFile, { force: true }); prefs.ai = false; save(); break;
    case 'guide': await shell.openExternal('https://github.com/furudo-erika/deepseek-chan/blob/main/docs/windows.md'); break;
    case 'copy-connector': clipboard.writeText(JSON.stringify({ mcpServers: { 'deepseek-chan': { command: 'py', args: ['-3', path.join(integrations, 'chan.py'), 'mcp', '--source', 'codex'] } } }, null, 2)); return { ok: true };
    case 'ignore': if (typeof value === 'boolean' && !drag) win.setIgnoreMouseEvents(value, { forward: true }); break;
    case 'drag-start': clearInterval(moving); drag = { cursor: screen.getCursorScreenPoint(), bounds: win.getBounds(), started: Date.now() }; win.setIgnoreMouseEvents(false); break;
    case 'drag-end': drag = null; homeBounds = win.getBounds(); break;
    case 'hide': hidden = true; win.hide(); break;
    case 'quit': app.quit(); break;
    default: throw Error('Unsupported command');
  }
  broadcast(); return { ok: true };
});
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { hidden = false; win?.show(); });
  app.whenReady().then(() => {
    app.setAppUserModelId('io.github.furudo-erika.deepseek-chan');
    session.defaultSession.setPermissionRequestHandler((_, __, callback) => callback(false));
    session.defaultSession.setPermissionCheckHandler(() => false);
    const work = screen.getPrimaryDisplay().workArea;
    win = new BrowserWindow({ width: 420, height: 470, x: work.x + work.width - 440, y: work.y + work.height - 490, transparent: true, frame: false, resizable: false, alwaysOnTop: true, skipTaskbar: true, hasShadow: false, show: false, icon: path.join(assets, 'companion-icon-dark.png'), webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: false, devTools: testing } });
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    win.webContents.on('will-navigate', event => event.preventDefault());
    win.on('blur', () => { drag = null; });
    win.loadFile(path.join(__dirname, 'index.html')); win.once('ready-to-show', () => win.showInactive()); homeBounds = win.getBounds();
    if (!testing) { tray = new Tray(nativeImage.createFromPath(path.join(assets, 'companion-icon-dark.png')).resize({ width: 32, height: 32 })); tray.setToolTip('DeepSeek-chan'); tray.setContextMenu(Menu.buildFromTemplate([{ label: 'Show DeepSeek-chan', click: () => { hidden = false; win.show(); } }, { label: 'Rest my eyes', click: () => { timer.rest(Date.now()); hidden = false; win.showInactive(); broadcast(); } }, { label: 'Quit', click: () => app.quit() }])); tray.on('double-click', () => { hidden = false; win.show(); }); }
    setInterval(tick, 250); setInterval(pollTasks, 2000); pollTasks();
    setInterval(() => { if (!drag || win.isDestroyed()) return; if (Date.now() - drag.started > 15000) { drag = null; return; } const point = screen.getCursorScreenPoint(); const b = { ...drag.bounds, x: drag.bounds.x + point.x - drag.cursor.x, y: drag.bounds.y + point.y - drag.cursor.y }; const next = clamp(b, screen.getDisplayNearestPoint(point).workArea), current = win.getBounds(); if (next.x !== current.x || next.y !== current.y) win.setPosition(next.x, next.y); }, 16);
    powerMonitor.on('resume', () => { timer.wake(Date.now()); lastPointer = null; restorePosition(); });
    powerMonitor.on('unlock-screen', () => { timer.wake(Date.now()); lastPointer = null; });
    screen.on('display-removed', () => { drag = null; win.setBounds(clamp(win.getBounds(), screen.getPrimaryDisplay().workArea)); homeBounds = win.getBounds(); });
  });
  app.on('window-all-closed', () => app.quit());
}
