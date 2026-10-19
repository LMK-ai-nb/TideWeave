#!/usr/bin/env node
import { readFileSync, writeFileSync, statSync } from 'node:fs';
const args = process.argv.slice(2);
if (args.length === 1 && ['--help','-h'].includes(args[0])) {
  console.log('Usage: node bin/tideweave.mjs <run|resume> <input.json|-> [--checkpoint output.json]\nExit: 0 accepted/duplicate; 1 rejected/conflict; 2 invalid input or I/O.');
  process.exit(0);
}
if (![2,4].includes(args.length) || !['run','resume'].includes(args[0]) || (args.length === 4 && args[2] !== '--checkpoint')) {
  console.error('Usage: node bin/tideweave.mjs <run|resume> <input.json|-> [--checkpoint output.json]');
  process.exit(2);
}
try {
  if (args[1] !== '-' && statSync(args[1]).size > 33554432) throw Error('input exceeds 32 MiB transport limit');
  const source = readFileSync(args[1] === '-' ? 0 : args[1], 'utf8');
  if (source.length > 8388608) throw Error('input exceeds 8 Mi UTF-16 units');
  const core = await import('../dist/engine.js');
  const raw = (args[0] === 'run' ? core.replay : core.resume_replay)(source);
  const result = JSON.parse(raw);
  if (result.error) { console.log(raw); process.exitCode = 2; }
  else {
    if (args.length === 4) writeFileSync(args[3], JSON.stringify(result.checkpoint, null, 2) + '\n');
    console.log(raw);
    process.exitCode = result.steps.some(s => ['rejected','conflict'].includes(s.status)) ? 1 : 0;
  }
} catch (error) {
  console.error(JSON.stringify({error:{code:'IO_OR_RUNTIME',message:error.message}}));
  process.exitCode = 2;
}

