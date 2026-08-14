#!/usr/bin/env node
/**
 * Scan the repo for anything that looks like a live credential.
 *
 *   node tools/scan-secrets.js            scan tracked working tree
 *   node tools/scan-secrets.js --history  also scan every commit reachable from any ref
 *
 * Exits 1 if a finding survives the allowlist, so it works as a pre-push gate.
 */
'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const SCAN_HISTORY = process.argv.includes('--history');

const PATTERNS = [
  { name: 'Anthropic API key', re: /sk-ant-[A-Za-z0-9_-]{20,}/g },
  { name: 'OpenAI API key', re: /\bsk-(?:proj-)?[A-Za-z0-9]{32,}/g },
  { name: 'GitHub token', re: /\bgh[pousr]_[A-Za-z0-9]{20,}/g },
  { name: 'GitHub fine-grained token', re: /\bgithub_pat_[A-Za-z0-9_]{40,}/g },
  { name: 'Slack token', re: /\bxox[baprs]-[A-Za-z0-9-]{10,}/g },
  { name: 'AWS access key id', re: /\bAKIA[0-9A-Z]{16}\b/g },
  { name: 'Google API key', re: /\bAIza[0-9A-Za-z_-]{35}\b/g },
  { name: 'Private key block', re: /-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/g },
  {
    name: 'Populated secret-ish field',
    // KEY/TOKEN/SECRET/PASSWORD assigned a long literal that is not a
    // ${PLACEHOLDER}, not REPLACE_WITH_..., and not an obvious example value.
    re: /["']?[A-Za-z0-9_]*(?:TOKEN|SECRET|PASSWORD|APIKEY|API_KEY)["']?\s*[:=]\s*["'](?!\$\{|REPLACE_WITH|YOUR_|xxx|<)[A-Za-z0-9_\-./+]{16,}["']/gi,
  },
];

// Paths that legitimately contain the patterns above (docs, this scanner).
const ALLOW_PATHS = [/^tools\/scan-secrets\.js$/, /^config\/\.env\.example$/];

const git = (...args) =>
  execFileSync('git', ['-C', REPO, ...args], { encoding: 'utf8', maxBuffer: 1 << 28 });

const findings = [];

function scanText(where, text) {
  if (ALLOW_PATHS.some((re) => re.test(where.replace(/\\/g, '/')))) return;
  for (const { name, re } of PATTERNS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null) {
      const line = text.slice(0, m.index).split('\n').length;
      const redacted = m[0].length > 12 ? `${m[0].slice(0, 6)}…${m[0].slice(-4)}` : m[0];
      findings.push({ where, line, name, redacted });
    }
  }
}

// ---- working tree ----------------------------------------------------------
const tracked = git('ls-files', '-z').split('\0').filter(Boolean);
for (const rel of tracked) {
  const abs = path.join(REPO, rel);
  let buf;
  try {
    buf = fs.readFileSync(abs);
  } catch {
    continue; // deleted or unreadable
  }
  if (buf.includes(0)) continue; // binary
  scanText(rel, buf.toString('utf8'));
}
console.log(`scanned ${tracked.length} tracked files`);

// ---- history ---------------------------------------------------------------
if (SCAN_HISTORY) {
  const revs = git('rev-list', '--all').split('\n').filter(Boolean);
  for (const rev of revs) {
    let listing;
    try {
      listing = git('ls-tree', '-r', '--name-only', '-z', rev).split('\0').filter(Boolean);
    } catch {
      continue;
    }
    for (const rel of listing) {
      let content;
      try {
        content = git('show', `${rev}:${rel}`);
      } catch {
        continue;
      }
      scanText(`${rev.slice(0, 8)}:${rel}`, content);
    }
  }
  console.log(`scanned ${revs.length} commits`);
}

// ---- report ----------------------------------------------------------------
if (findings.length === 0) {
  console.log('no secrets found');
  process.exit(0);
}

console.error(`\n${findings.length} potential secret(s):\n`);
for (const f of findings) {
  console.error(`  ${f.where}:${f.line}  ${f.name}  ${f.redacted}`);
}
console.error('\nRemove or templatize these before pushing.');
process.exit(1);
