import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Shared Pi / OMP lifecycle adapter. No transcript text or tool arguments leave the process.
export function connectPet(api, source, finalEvent, sendOverride) {
  const script = fileURLToPath(new URL('./chan.py', import.meta.url));
  let task = '', busy = false, timer, finalStatus = 'completed', queue = Promise.resolve();
  function send(status) {
    if (!task) return Promise.resolve();
    const id = task;
    queue = queue.then(() => sendOverride ? sendOverride(source, id, status) : new Promise(resolve => {
      execFile(process.env.DEEPSEEK_CHAN_PYTHON || 'python3', [script, 'emit', '--source', source, '--task', id, '--status', status],
        { timeout: 3000, maxBuffer: 4096 }, () => resolve());
    })).catch(() => {});
    return queue;
  }
  function stopTimer() { if (timer) clearInterval(timer); timer = undefined; }
  api.on('agent_start', async (_event, ctx) => {
    stopTimer();
    task = createHash('sha256').update(ctx.sessionManager.getSessionId()).digest('hex');
    busy = true; finalStatus = 'completed';
    timer = setInterval(() => { if (busy) void send('working'); }, 60000);
    timer.unref?.();
    await send('working');
  });
  api.on('agent_end', async event => {
    const last = [...(event.messages || [])].reverse().find(message => message.role === 'assistant');
    finalStatus = last?.stopReason === 'error' ? 'failed' : last?.stopReason === 'aborted' ? 'cancelled' : 'completed';
    if (finalEvent === 'agent_end') {
      busy = false; stopTimer(); await send(finalStatus);
    }
  });
  if (finalEvent !== 'agent_end') api.on(finalEvent, async () => {
    busy = false; stopTimer(); await send(finalStatus);
  });
  api.on('session_shutdown', async () => {
    stopTimer();
    if (busy) { busy = false; await send('cancelled'); }
    task = '';
  });
}
