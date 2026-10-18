import { connectPet } from './pet-extension.mjs';
// OMP's installed extension contract exposes agent_end for a completed run.
export default function (omp: any) { connectPet(omp, 'omp', 'agent_end'); }
