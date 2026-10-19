import { performance } from 'node:perf_hooks';
import { mkdirSync, writeFileSync } from 'node:fs';
import { replay } from '../dist/engine.js';
const commands=[];
for(let start=0;start<4096;start+=128){const changes=[];for(let i=start;i<start+128;i++) changes.push({op:'put',event:{id:`event-${i}`,key:`device-${i%64}`,at:Math.floor(i/64)*8,value:(i%101)-50}});commands.push({id:`batch-${start/128}`,kind:'transaction',changes});}
const request=JSON.stringify({schema_version:1,config:{window:{kind:'session',gap:10},lateness:20},commands});
for(let i=0;i<3;i++)replay(request);
const samples=[];let result;
for(let i=0;i<10;i++){const begin=performance.now();result=replay(request);samples.push(performance.now()-begin);}
const report=JSON.parse(result);if(report.error||report.events.length!==4096||report.rows.length!==64||report.version!==32)throw Error('benchmark result assertion failed');
samples.sort((a,b)=>a-b);
const stats={runtime:process.version,platform:process.platform,arch:process.arch,events:4096,keys:64,transactions:32,window:'session gap=10 lateness=20',warmups:3,samples_ms:samples,median_ms:(samples[4]+samples[5])/2,max_ms:samples[9],output_bytes:Buffer.byteLength(result),includes:'input decode, state transitions, deltas, checkpoint and complete JSON serialization'};
mkdirSync('artifacts',{recursive:true});writeFileSync('artifacts/benchmark.json',JSON.stringify(stats,null,2)+'\n');console.log(JSON.stringify(stats,null,2));
