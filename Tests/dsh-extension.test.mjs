import test from 'node:test';
import assert from 'node:assert/strict';
import { connectDsh } from '../integrations/dsh.mjs';

function harness(sender) {
  const handlers = {}, sent = [], session = { id: 'private-session' };
  const bridge = connectDsh({ on: (name, fn) => { handlers[name] = fn; } }, sender || (async (...args) => sent.push(args)));
  const event = async (type, data = {}) => { assert.equal(handlers['session/event'](session, { type, data }), undefined); await bridge.flush(); };
  const status = async value => { handlers['agent/status']({ agent: { session }, status: value }); await bridge.flush(); };
  return { handlers, sent, session, bridge, event, status };
}

test('dsh observes concurrent approvals and waits for driver idle before completion', async () => {
  const h = harness();
  try {
    await h.status('running');
    await h.event('turn/start');
    await h.event('approval/asked', { id: 'a', toolName: 'SECRET', args: 'PRIVATE' });
    await h.event('approval/asked', { id: 'b' });
    await h.event('approval/decided', { id: 'a', outcome: 'approved' });
    assert.equal(h.sent.at(-1)[1], 'waiting');
    await h.event('approval/decided', { id: 'b', outcome: 'approved' });
    assert.equal(h.sent.at(-1)[1], 'working');
    await h.event('turn/end', { reason: { kind: 'completed' } });
    assert.equal(h.sent.at(-1)[1], 'working');
    await h.status('idle');
    assert.equal(h.sent.at(-1)[1], 'completed');
    assert.ok(h.sent.every(([id]) => /^[a-f0-9]{64}$/.test(id)));
    assert.ok(!/SECRET|PRIVATE|private-session/.test(JSON.stringify(h.sent)));
  } finally { await h.bridge.dispose(); }
});

test('dsh handles questions, continuations, failure, cancellation, and disposal', async () => {
  const h = harness();
  try {
    await h.status('running');
    await h.event('turn/start');
    await h.event('tool/call', { name: 'ask_user_question', arguments: { question: 'SECRET' } });
    assert.equal(h.sent.at(-1)[1], 'waiting');
    await h.event('step/start');
    assert.equal(h.sent.at(-1)[1], 'working');
    await h.event('turn/end', { reason: { kind: 'completed' } });
    await h.event('turn/start'); // Driver continued, so earlier completion is not final.
    await h.event('turn/end', { reason: { kind: 'error' } });
    await h.status('idle');
    assert.equal(h.sent.at(-1)[1], 'failed');
    await h.status('running');
    await h.event('turn/end', { reason: { kind: 'aborted' } });
    await h.status('idle');
    assert.equal(h.sent.at(-1)[1], 'cancelled');
    await h.status('running');
    h.handlers['session/disposed'](h.session); await h.bridge.flush();
    assert.equal(h.sent.at(-1)[1], 'cancelled');
  } finally { await h.bridge.dispose(); }
});

test('dsh isolates sessions, recycles idle slots, and contains writer failure', async () => {
  const h = harness();
  try {
    for (let i = 0; i < 150; i++) {
      const agent = { session: { id: 'task-' + i } };
      h.handlers['agent/status']({ agent, status: 'running' }); await h.bridge.flush();
      h.handlers['agent/status']({ agent, status: 'idle' }); await h.bridge.flush();
    }
    assert.equal(new Set(h.sent.map(([id]) => id)).size, 150);
    assert.equal(h.sent.at(-1)[1], 'idle');
  } finally { await h.bridge.dispose(); }
  const failing = harness(async () => { throw Error('Writer unavailable'); });
  await failing.status('running');
  await failing.status('idle');
  await failing.bridge.dispose();
});
