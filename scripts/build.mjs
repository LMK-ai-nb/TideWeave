import { spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const result = spawnSync(process.platform === 'win32' ? 'moon.exe' : 'moon', ['build', 'api', '--target', 'js', '--release', '--deny-warn'], { cwd: root, stdio: 'inherit' });
if (result.error || result.status !== 0) { console.error('Install MoonBit 0.10.16+ and put moon on PATH.'); process.exit(2); }
for (const dir of ['dist', 'web', 'web/data', 'dist/licenses', 'web/licenses']) mkdirSync(resolve(root, dir), {recursive:true});
for (const dest of ['dist/engine.js', 'web/engine.js']) copyFileSync(resolve(root, '_build/js/release/build/api/api.js'), resolve(root, dest));
for (const file of readdirSync(resolve(root, 'examples')).filter(x => x.endsWith('.json'))) copyFileSync(resolve(root, 'examples', file), resolve(root, 'web/data', file));
for (const dir of ['dist/licenses', 'web/licenses']) for (const name of ['LICENSE', 'NOTICE']) copyFileSync(resolve(root, `third_party/MoonBit-core-${name}.txt`), resolve(root, dir, `MoonBit-core-${name}.txt`));
console.log('Built the shared MoonBit core for CLI and browser.');
