import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const name = 'deepseek-chan-pet';
export const inject = ['sessions'];

// Observe committed session facts, never participate in approval/answer waterfalls.
export function connectDsh(ctx, sendOverride) {
  const script = fileURLToPath(new URL('./chan.py', import.meta.url));
  const states = new Map(), pending = new Map();
  let draining = false, disposed = false, drainPromise = Promise.resolve();
  const send = sendOverride || ((id, status) => new Promise(resolve => {
    execFile(process.env.DEEPSEEK_CHAN_PYTHON || 'python3', [script, 'emit', '--source', 'dsh', '--task', id, '--status', status],
      { timeout: 3000, maxBuffer: 4096 }, () => resolve());
  }));
  function state(session) {
    if (!session || typeof session.id !== 'string') return;
    const id = createHash('sha256').update(session.id).digest('hex');
    if (!states.has(id)) {
      if (states.size >= 128) {
        const inactive = [...states.values()].find(s => !s.active);
        if (inactive) states.delete(inactive.id);
      }
      if (states.size >= 128) return;
      states.set(id, { id, active: false, waiting: new Set(), question: false, final: 'idle', last: null });
    }
    return states.get(id);
  }
  function publish(s, status, heartbeat = false) {
    if (disposed || (!heartbeat && s.last === status)) return;
    s.last = status; pending.set(s.id, status);
    if (draining) return;
    draining = true;
    drainPromise = (async () => {
      try {
        while (!disposed && pending.size) {
          const [id, value] = pending.entries().next().value;
          pending.delete(id);
          try { await send(id, value); } catch { /* Pet failure cannot stop the agent. */ }
        }
      } finally { draining = false; }
    })();
  }
  function working(s, heartbeat = false) { publish(s, s.waiting.size || s.question ? 'waiting' : 'working', heartbeat); }
  ctx.on('agent/status', ({ agent, status }) => {
    if (!['running', 'idle'].includes(status)) return;
    const s = state(agent?.session); if (!s) return;
    s.active = status === 'running';
    if (s.active) { s.final = 'idle'; working(s); }
    else { s.waiting.clear(); s.question = false; publish(s, s.final); }
  });
  ctx.on('session/event', (session, event) => {
    if (!['turn/start', 'turn/end', 'step/start', 'approval/asked', 'approval/decided', 'tool/call'].includes(event?.type)) return;
    const s = state(session); if (!s) return;
    const data = event.data || {};
    if (event.type === 'turn/start') {
      s.active = true; s.final = 'idle'; s.waiting.clear(); s.question = false; working(s);
    } else if (event.type === 'turn/end') {
      s.final = { completed: 'completed', error: 'failed', aborted: 'cancelled', blocked: 'cancelled', 'max-tokens': 'failed' }[data.reason?.kind] || 'idle';
      // Do not announce completion until the entire agent driver actually becomes idle.
    } else if (event.type === 'step/start') {
      s.question = false; if (s.active) working(s);
    } else if (event.type === 'approval/asked' && s.active && typeof data.id === 'string') {
      s.waiting.add(data.id); working(s);
    } else if (event.type === 'approval/decided') {
      s.waiting.delete(data.id); if (s.active) working(s);
    } else if (event.type === 'tool/call' && data.name === 'ask_user_question' && s.active) {
      s.question = true; working(s);
    }
  });
  ctx.on('session/disposed', session => {
    const s = state(session); if (!s) return;
    if (s.active) publish(s, 'cancelled');
    states.delete(s.id);
  });
  const timer = setInterval(() => { for (const s of states.values()) if (s.active) working(s, true); }, 60000);
  timer.unref?.();
  const dispose = async () => { disposed = true; clearInterval(timer); pending.clear(); states.clear(); await drainPromise; };
  ctx.on('dispose', dispose);
  return { flush: () => drainPromise, dispose };
}

export function apply(ctx) { connectDsh(ctx); }
