'use strict';
const crypto = require('node:crypto');
class FocusTimer {
  constructor(minutes = 20) { this.minutes = minutes; this.phase = 'waiting'; this.deadline = null; this.completed = 0; }
  reset() { this.phase = 'waiting'; this.deadline = null; }
  tick(now, moved, idle) {
    if (this.phase === 'resting') { if (now >= this.deadline) { this.completed++; this.reset(); } return; }
    if (this.phase === 'paused') return;
    if (idle >= 300) { this.reset(); return; }
    if (this.phase === 'waiting' && moved) { this.phase = 'focusing'; this.deadline = now + this.minutes * 60000; }
    if (this.phase === 'focusing' && now >= this.deadline) { this.phase = 'reminding'; this.deadline = null; }
  }
  rest(now) { this.phase = 'resting'; this.deadline = now + 300000; }
  snooze(now) { this.phase = 'focusing'; this.deadline = now + 300000; }
  pause() { if (this.phase === 'paused') this.reset(); else { this.phase = 'paused'; this.deadline = null; } }
  wake(now) { if (this.phase === 'resting') this.tick(now, false, 0); else if (this.phase !== 'paused') this.reset(); }
  interval(minutes, now) { this.minutes = minutes; if (this.phase === 'focusing') this.deadline = now + minutes * 60000; }
}
function shuffle(values) {
  const bag = [...values];
  for (let i = bag.length - 1; i > 0; i--) { const j = crypto.randomInt(i + 1); [bag[i], bag[j]] = [bag[j], bag[i]]; }
  return bag;
}
class Deck {
  constructor() { this.bag = []; this.key = ''; this.last = null; }
  next(values) {
    const key = values.join('|');
    if (!this.bag.length || key !== this.key) { this.key = key; this.bag = shuffle(values); }
    if (this.bag.at(-1) === this.last && this.bag.length > 1) [this.bag[0], this.bag[this.bag.length - 1]] = [this.bag.at(-1), this.bag[0]];
    this.last = this.bag.pop(); return this.last;
  }
}
const SOURCES = ['codex', 'claude', 'cursor', 'pi', 'omp', 'grok', 'dsh', 't3', 'other'];
const STATES = ['working', 'waiting', 'completed', 'failed', 'cancelled', 'idle'];
function validTask(t, now = Date.now()) {
  const age = now / 1000 - t?.updated_at;
  return t?.version === 1 && SOURCES.includes(t.source) && STATES.includes(t.status) && Number.isFinite(t.updated_at) && age >= -30 && age < 86400 &&
    ['task_id', 'event_id', 'title'].every(k => typeof t[k] === 'string' && t[k].length > 0 && t[k].length <= (k === 'title' ? 80 : 128) && !/[\u0000-\u001f\u007f]/.test(t[k]));
}
class TaskQueue {
  constructor(now = Date.now()) { this.tasks = new Map(); this.pending = new Map(); this.started = now; this.last = -Infinity; }
  ingest(rows, now = Date.now()) {
    for (const t of rows) {
      if (!validTask(t, now)) continue;
      const id = t.source + ':' + t.task_id, old = this.tasks.get(id);
      if (old && old.updated_at >= t.updated_at) continue;
      this.tasks.set(id, t);
      if (t.updated_at * 1000 >= this.started && (!old || old.status !== t.status)) this.pending.set(id, t);
    }
    for (const [id, task] of this.tasks) if (!validTask(task, now)) { this.tasks.delete(id); this.pending.delete(id); }
    while (this.tasks.size > 128) { const id = this.tasks.keys().next().value; this.tasks.delete(id); this.pending.delete(id); }
    while (this.pending.size > 32) this.pending.delete(this.pending.keys().next().value);
  }
  next(now, blocked) {
    for (const [id, task] of this.pending) if (now - task.updated_at * 1000 > 120000) this.pending.delete(id);
    if (blocked || now - this.last < 12000) return;
    const rank = { failed: 3, waiting: 3, completed: 2, cancelled: 1, idle: 0, working: 0 };
    const t = [...this.pending.values()].sort((a, b) => rank[b.status] - rank[a.status] || b.updated_at - a.updated_at)[0];
    if (t) { this.pending.delete(t.source + ':' + t.task_id); this.last = now; } return t;
  }
}
function clamp(bounds, work) {
  return { x: Math.round(Math.max(work.x, Math.min(bounds.x, work.x + Math.max(0, work.width - bounds.width)))), y: Math.round(Math.max(work.y, Math.min(bounds.y, work.y + Math.max(0, work.height - bounds.height)))), width: bounds.width, height: bounds.height };
}
function cleanReply(text) { return typeof text === 'string' && text.trim().length <= 110 && !/[<>`\n\r]/.test(text) ? text.trim() : ''; }
module.exports = { FocusTimer, Deck, TaskQueue, validTask, clamp, cleanReply };
