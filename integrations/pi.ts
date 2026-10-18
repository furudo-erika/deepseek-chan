import { connectPet } from './pet-extension.mjs';
// Current Pi exposes agent_settled after retries and queued work have finished.
export default function (pi: any) { connectPet(pi, 'pi', 'agent_settled'); }
