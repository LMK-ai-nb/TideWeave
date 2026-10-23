#!/usr/bin/env node
// Reproducible proof of why a correction layer is needed.
// Compares a typical incremental-aggregate implementation (merge on insert,
// subtract on retract, never re-split) against TideWeave on the same input.
import { replay } from '../dist/engine.js';

const scenario = {
  schema_version: 1,
  config: { window: { kind: 'session', gap: 10 }, lateness: 20 },
  commands: [
    { id: 'seed', kind: 'transaction', changes: [
      { op: 'put', event: { id: 'left', key: 'device-A', at: 0, value: 20 } },
      { op: 'put', event: { id: 'right', key: 'device-A', at: 16, value: 35 } },
    ] },
    { id: 'watermark-12', kind: 'watermark', to: 12 },
    { id: 'late-bridge', kind: 'transaction', changes: [
      { op: 'put', event: { id: 'bridge', key: 'device-A', at: 8, value: 12 } },
    ] },
    { id: 'retract-bridge', kind: 'transaction', changes: [
      { op: 'remove', event_id: 'bridge' },
    ] },
  ],
};

// A plausible hand-written implementation: keep one session per key range,
// merge when an insert bridges two sessions, and only subtract on retract.
const naive = (() => {
  let sessions = [];
  const observe = (event, sign) => {
    if (sign > 0) {
      const touching = sessions.filter(s => event.at >= s.start - 9 && event.at < s.end + 9);
      if (touching.length > 0) {
        const merged = {
          start: Math.min(...touching.map(s => s.start), event.at),
          end: Math.max(...touching.map(s => s.end), event.at + 10),
          count: touching.reduce((n, s) => n + s.count, 0) + 1,
          sum: touching.reduce((n, s) => n + s.sum, 0) + event.value,
          min: Math.min(...touching.map(s => s.min), event.value),
          max: Math.max(...touching.map(s => s.max), event.value),
          members: [...new Set(touching.flatMap(s => s.members).concat(event.id))].sort(),
        };
        sessions = sessions.filter(s => !touching.includes(s)).concat(merged);
        return;
      }
      sessions.push({ start: event.at, end: event.at + 10, count: 1, sum: event.value, min: event.value, max: event.value, members: [event.id] });
    } else {
      // Retraction only adjusts the aggregate: no boundary or membership rebuild.
      const target = sessions.find(s => s.members.includes(event.id));
      if (target) {
        target.sum -= event.value;
        target.count -= 1;
        target.members = target.members.filter(m => m !== event.id);
      }
    }
  };
  observe({ id: 'left', at: 0, value: 20 }, 1);
  observe({ id: 'right', at: 16, value: 35 }, 1);
  observe({ id: 'bridge', at: 8, value: 12 }, 1);
  observe({ id: 'bridge', at: 8, value: 12 }, -1);
  return sessions.filter(s => s.count > 0);
})();

const report = JSON.parse(replay(JSON.stringify(scenario)));
if (report.error) {
  console.error(report.error);
  process.exit(2);
}
const actual = report.rows.map(row => ({
  start: row.start, end: row.end, count: row.count, sum: Number(row.sum),
  min: row.min, max: row.max, members: row.members,
}));

const fmt = rows => rows
  .sort((a, b) => a.start - b.start)
  .map(r => `[${r.start},${r.end}) members=[${r.members.join(',')}] count=${r.count} sum=${r.sum} min=${r.min} max=${r.max}`)
  .join('<br>');

console.log('| 结果 | 增量聚合（不重建会话） | TideWeave（重建连通分量） |');
console.log('| --- | --- | --- |');
console.log(`| 窗口 | ${fmt(naive) || '（无）'} | ${fmt(actual)} |`);
console.log(`| 窗口数 | ${naive.length} | ${actual.length} |`);

const retract = report.steps.find(s => s.id === 'retract-bridge');
console.log(`| 撤回命令输出 | 无（只改数字） | ${retract.deltas.length} 条变更（1 delete + 2 upsert） |`);

const ok = actual.length === 2 &&
  actual.some(r => r.start === 0 && r.end === 10 && r.members.join() === 'left' && r.sum === 20) &&
  actual.some(r => r.start === 16 && r.end === 26 && r.members.join() === 'right' && r.sum === 35);
console.log(`\n判定：TideWeave ${ok ? '正确重建两个原始会话' : '结果与预期不符'}`);
process.exitCode = ok ? 0 : 1;
