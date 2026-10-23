#!/usr/bin/env node
import { readFileSync, writeFileSync, statSync } from 'node:fs';

const usage =
  'Usage: node bin/tideweave.mjs <run|resume|stream> [input.json|-] [--checkpoint output.json]\n' +
  '  run     replay a JSON request\n' +
  '  resume  apply commands to a saved checkpoint\n' +
  '  stream  consume newline-delimited JSON from stdin (or a file) and emit NDJSON outcomes\n' +
  'Exit: 0 accepted/duplicate; 1 rejected/conflict; 2 invalid input or I/O.';

const args = process.argv.slice(2);
if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
  console.log(usage);
  process.exit(0);
}

const command = args[0];
if (!['run', 'resume', 'stream'].includes(command)) {
  console.error(usage);
  process.exit(2);
}

let input = null;
let checkpointPath = null;
for (let i = 1; i < args.length; i++) {
  if (args[i] === '--checkpoint') {
    if (i + 1 >= args.length || checkpointPath !== null) {
      console.error(usage);
      process.exit(2);
    }
    checkpointPath = args[++i];
  } else if (input === null) {
    input = args[i];
  } else {
    console.error(usage);
    process.exit(2);
  }
}
if (command !== 'stream' && input === null) {
  console.error(usage);
  process.exit(2);
}
if (input === null) input = '-';

const fail = error => {
  console.error(JSON.stringify({ error: { code: 'IO_OR_RUNTIME', message: error.message } }));
  process.exitCode = 2;
};

const writeCheckpoint = summary => {
  if (checkpointPath !== null) {
    writeFileSync(checkpointPath, JSON.stringify(summary.checkpoint, null, 2) + '\n');
  }
};

try {
  if (input !== '-' && statSync(input).size > 33554432) throw Error('input exceeds 32 MiB transport limit');
  const source = readFileSync(input === '-' ? 0 : input, 'utf8');
  if (source.length > 8388608) throw Error('input exceeds 8 Mi UTF-16 units');
  const core = await import('../dist/engine.js');

  if (command === 'stream') {
    const raw = core.stream_ndjson(source);
    const lines = raw.split('\n');
    const head = JSON.parse(lines[0]);
    if (head && head.error) {
      console.log(raw);
      process.exitCode = 2;
    } else {
      const summary = JSON.parse(lines[lines.length - 1]).summary;
      writeCheckpoint(summary);
      console.log(raw);
      const rejected = lines
        .slice(0, -1)
        .map(line => JSON.parse(line))
        .some(outcome => ['rejected', 'conflict'].includes(outcome.status));
      process.exitCode = rejected ? 1 : 0;
    }
  } else {
    const raw = (command === 'run' ? core.replay : core.resume_replay)(source);
    const result = JSON.parse(raw);
    if (result.error) {
      console.log(raw);
      process.exitCode = 2;
    } else {
      writeCheckpoint(result);
      console.log(raw);
      process.exitCode = result.steps.some(s => ['rejected', 'conflict'].includes(s.status)) ? 1 : 0;
    }
  }
} catch (error) {
  fail(error);
}
