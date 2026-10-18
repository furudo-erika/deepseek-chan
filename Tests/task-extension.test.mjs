import test from 'node:test';
import assert from 'node:assert/strict';
import { connectPet } from '../integrations/pet-extension.mjs';

for (const [source, finalEvent] of [['pi', 'agent_settled'], ['omp', 'agent_end']]) {
  test(`${source} lifecycle, failure, cancellation and private metadata`, async () => {
    const handlers = {}, sent = [];
    const api = { on: (name, fn) => { handlers[name] = fn; } };
    connectPet(api, source, finalEvent, async (...args) => { sent.push(args); });
    const ctx = { sessionManager: { getSessionId: () => 'private-session' } };
    await handlers.agent_start({}, ctx);
    assert.equal(sent.at(-1)[2], 'working');
    await handlers.agent_end({ messages: [{ role: 'assistant', content: 'SECRET', stopReason: 'stop' }] });
    if (finalEvent === 'agent_settled') {
      assert.equal(sent.at(-1)[2], 'working');
      await handlers.agent_settled({});
    }
    assert.equal(sent.at(-1)[2], 'completed');
    await handlers.agent_start({}, ctx);
    await handlers.agent_end({ messages: [{ role: 'assistant', stopReason: 'error' }] });
    if (finalEvent === 'agent_settled') await handlers.agent_settled({});
    assert.equal(sent.at(-1)[2], 'failed');
    await handlers.agent_start({}, ctx);
    await handlers.session_shutdown({});
    assert.equal(sent.at(-1)[2], 'cancelled');
    assert.ok(!JSON.stringify(sent).includes('SECRET'));
    assert.ok(!JSON.stringify(sent).includes('private-session'));
    assert.ok(sent.every(([name, id]) => name === source && id.length === 64));
  });
}
