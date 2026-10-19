import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { replay, resume_replay } from '../dist/engine.js';
const root = resolve(import.meta.dirname, '..');
const fixture = name => readFileSync(resolve(root, 'examples', name), 'utf8');
const run = (...args) => spawnSync(process.execPath, ['bin/tideweave.mjs', ...args], {cwd:root,encoding:'utf8'});
test('session bridge, retraction and finality produce exact public outcomes', () => {
  const r = JSON.parse(replay(fixture('session-correction.json')));
  assert.equal(r.version,5);
  assert.deepEqual(r.steps.map(s=>s.status),['accepted','accepted','accepted','accepted','accepted','rejected']);
  assert.equal(r.steps[2].deltas.filter(d=>d.kind==='delete').length,2);
  assert.equal(r.steps[3].deltas.filter(d=>d.kind==='upsert').length,2);
  assert.deepEqual(r.rows.map(w=>w.sum),['20','35']);
  assert.ok(r.rows.every(w=>w.phase==='final'));
});
test('all synthetic use cases produce valid, restorable checkpoints', () => {
  for (const name of ['session-correction.json','order-amendment.json','sensor-backfill.json']) {
    const result=JSON.parse(replay(fixture(name)));
    const restored=JSON.parse(resume_replay(JSON.stringify({schema_version:1,checkpoint:result.checkpoint,commands:[]})));
    assert.deepEqual(restored.rows,result.rows);
    assert.deepEqual(restored.events,result.events);
    assert.equal(restored.version,result.version);
  }
});
test('raw duplicate keys and exact-looking fractions fail before JS can round them', () => {
  const source=fixture('order-amendment.json');
  for (const malformed of [source.replace('"schema_version": 1','"schema_version": 1,"schema_versio\\u006e":1'), source.replace('"size": 60','"size": 60.00000000000000000001'),source.replace('"size": 60','"size": 6e1')]) {
    assert.equal(JSON.parse(replay(malformed)).error.code,'INVALID_INPUT');
  }
});
test('public CLI exit codes distinguish domain rejections and syntax errors', () => {
  assert.equal(run('run','examples/order-amendment.json').status,0);
  assert.equal(run('run','examples/session-correction.json').status,1);
  assert.equal(run('run','missing-file.json').status,2);
  assert.equal(run('--help').status,0);
  assert.equal(run('bad','examples/order-amendment.json').status,2);
});
test('CLI preserves raw stdin and does not normalize duplicate objects', () => {
  const source=fixture('sensor-backfill.json');
  const result=spawnSync(process.execPath,['bin/tideweave.mjs','run','-'],{cwd:root,input:source,encoding:'utf8'});
  assert.equal(result.status,0);
  assert.equal(JSON.parse(result.stdout).rows.length,3);
  const invalid=spawnSync(process.execPath,['bin/tideweave.mjs','run','-'],{cwd:root,input:'{"a":1,"a":2}',encoding:'utf8'});
  assert.equal(invalid.status,2);
  assert.equal(JSON.parse(invalid.stdout).error.code,'INVALID_INPUT');
});
test('CLI checkpoint export and resume preserve idempotency across processes', () => {
  const dir=mkdtempSync(resolve(tmpdir(),'tideweave-'));
  try {
    const checkpoint=resolve(dir,'checkpoint.json');
    assert.equal(run('run','examples/order-amendment.json','--checkpoint',checkpoint).status,0);
    const saved=JSON.parse(readFileSync(checkpoint,'utf8'));
    const original=JSON.parse(fixture('order-amendment.json'));
    const input=resolve(dir,'resume.json');
    writeFileSync(input,JSON.stringify({schema_version:1,checkpoint:saved,commands:[original.commands[0]]}));
    const outcome=run('resume',input);
    assert.equal(outcome.status,0,outcome.stderr);
    assert.equal(JSON.parse(outcome.stdout).steps[0].status,'duplicate');
  } finally { rmSync(dir,{recursive:true,force:true}); }
});
test('invalid JSON and unsupported checkpoint versions return structured errors', () => {
  assert.equal(JSON.parse(replay('{')).error.code,'INVALID_INPUT');
  const result=JSON.parse(replay(fixture('order-amendment.json')));
  result.checkpoint.schema_version=999;
  assert.equal(JSON.parse(resume_replay(JSON.stringify({schema_version:1,checkpoint:result.checkpoint,commands:[]}))).error.code,'INVALID_INPUT');
});
test('Unicode event IDs, keys and literal markup stay data across the bridge', () => {
  const event={id:'<img src=x onerror=alert(1)>',key:'汉字/🔧',at:1,value:-1};
  const r=JSON.parse(replay(JSON.stringify({schema_version:1,config:{window:{kind:'session',gap:5}},commands:[{id:'a',kind:'transaction',changes:[{op:'put',event}]}]})));
  assert.deepEqual(r.events,[event]);
  assert.equal(r.rows[0].sum,'-1');
});
