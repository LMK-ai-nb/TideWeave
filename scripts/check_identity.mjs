#!/usr/bin/env node
// Refuse to commit or push under the wrong identity.
// The rejections from August included "repository contains another person's
// commits", so this repository pins one identity and fails loudly otherwise.
import { execFileSync } from 'node:child_process';

const EXPECTED_NAME = 'LMK-ai-nb';
const EXPECTED_EMAIL = '315346758+LMK-ai-nb@users.noreply.github.com';
const EXPECTED_REMOTE = 'github.com/LMK-ai-nb/TideWeave';

const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
};

const errors = [];
const name = git('config', '--local', '--get', 'user.name');
const email = git('config', '--local', '--get', 'user.email');
if (name !== EXPECTED_NAME) {
  errors.push(`repo-local user.name is "${name}", expected "${EXPECTED_NAME}"`);
}
if (email !== EXPECTED_EMAIL) {
  errors.push(`repo-local user.email is "${email}", expected "${EXPECTED_EMAIL}"`);
}

const remote = git('remote', 'get-url', 'origin');
if (!remote.includes(EXPECTED_REMOTE)) {
  errors.push(`origin is "${remote}", expected to contain "${EXPECTED_REMOTE}"`);
}

const log = git('log', '--no-merges', '--format=%an|%ae|%cn|%ce');
let total = 0;
let bad = 0;
for (const line of log.split('\n').filter(Boolean)) {
  total += 1;
  const [an, ae, cn, ce] = line.split('|');
  if (an !== EXPECTED_NAME || ae !== EXPECTED_EMAIL || cn !== EXPECTED_NAME || ce !== EXPECTED_EMAIL) {
    bad += 1;
    errors.push(`commit #${total}: ${an} <${ae}> / committer ${cn} <${ce}>`);
  }
}

if (errors.length > 0) {
  console.error('IDENTITY CHECK FAILED — refusing to proceed.');
  for (const error of errors.slice(0, 10)) console.error(`  - ${error}`);
  if (errors.length > 10) console.error(`  ... and ${errors.length - 10} more`);
  console.error(`\nFix: git config --local user.name "${EXPECTED_NAME}"`);
  console.error(`     git config --local user.email "${EXPECTED_EMAIL}"`);
  process.exit(1);
}

console.log(`Identity OK: ${EXPECTED_NAME} <${EXPECTED_EMAIL}>`);
console.log(`Remote OK:   ${remote}`);
console.log(`Commits OK:  ${total}/${total} authored and committed by the expected identity`);
