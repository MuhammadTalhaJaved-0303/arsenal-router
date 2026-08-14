#!/usr/bin/env node
/**
 * Pull the live Claude Code config out of ~/.claude and back into this repo,
 * stripping credentials on the way. Run it on whichever machine is currently
 * "source of truth", then commit and push.
 *
 *   node tools/sync.js             copy live config in, report repo-only orphans
 *   node tools/sync.js --prune     also delete repo files that no longer exist locally
 *   node tools/sync.js --dry-run   report only, write nothing
 *
 * Secrets never land in the repo: every value that looks like a credential is
 * rewritten to a ${ENV_VAR} placeholder and recorded in config/.env.example.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const CLAUDE = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const CLAUDE_JSON = path.join(os.homedir(), '.claude.json');

const PRUNE = process.argv.includes('--prune');
const DRY = process.argv.includes('--dry-run');

// Directories mirrored between ~/.claude and the repo.
const PAYLOAD = ['agents', 'commands', 'skills', 'rules', 'scripts', 'hooks'];

// Files that live only in the repo and must survive a sync.
const REPO_ONLY = new Set([
  'commands/arsenal.md',
  'skills/arsenal-code/SKILL.md',
  'hooks/hooks.json',
]);

const log = (...a) => console.log(' ', ...a);
const warn = (...a) => console.warn('  warn:', ...a);
const step = (m) => console.log(`\n${m}`);

// ---------------------------------------------------------------- utilities
function walk(dir, base = dir, out = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) walk(abs, base, out);
    else if (e.isFile()) out.push(path.relative(base, abs).split(path.sep).join('/'));
  }
  return out;
}

const readJson = (p) => {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
};

const writeJson = (p, obj) => {
  if (DRY) return log(`[dry-run] would write ${path.relative(REPO, p)}`);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
  log(`wrote ${path.relative(REPO, p)}`);
};

/** Hand-written stand-ins like REPLACE_WITH_YOUR_TOKEN — normalize these too. */
const isPlaceholder = (v) => typeof v === 'string' && /^(REPLACE_WITH|YOUR_|<|xxx)/i.test(v);

/** True for values that look like a live credential rather than a placeholder. */
const looksSecret = (v) =>
  typeof v === 'string' && v.length >= 12 && !/^\$\{/.test(v) && !isPlaceholder(v);

const envVarNames = new Set();

/** Rewrite credential-looking values to ${ENV_VAR}, recording the var names. */
function sanitize(node, serverName) {
  if (Array.isArray(node)) return node.map((v) => sanitize(v, serverName));
  if (!node || typeof node !== 'object') return node;

  const out = {};
  for (const [k, v] of Object.entries(node)) {
    if (k === 'env' && v && typeof v === 'object') {
      out.env = {};
      for (const [ek, ev] of Object.entries(v)) {
        if (looksSecret(ev) || isPlaceholder(ev)) {
          envVarNames.add(ek);
          out.env[ek] = '${' + ek + '}';
        } else {
          out.env[ek] = ev;
        }
      }
    } else if (k === 'headers' && v && typeof v === 'object') {
      out.headers = {};
      for (const [hk, hv] of Object.entries(v)) {
        const m = typeof hv === 'string' && hv.match(/^(Bearer|Basic|token)\s+(.+)$/i);
        // _MCP_TOKEN rather than _TOKEN so it cannot collide with widely-used
        // vars like GITHUB_TOKEN that other tools (gh, CI) already own.
        const varName = `${serverName.toUpperCase().replace(/[^A-Z0-9]+/g, '_')}_MCP_TOKEN`;
        if (m && looksSecret(m[2])) {
          envVarNames.add(varName);
          out.headers[hk] = `${m[1]} \${${varName}}`;
        } else if (looksSecret(hv)) {
          envVarNames.add(varName);
          out.headers[hk] = '${' + varName + '}';
        } else {
          out.headers[hk] = hv;
        }
      }
    } else {
      out[k] = sanitize(v, serverName);
    }
  }
  return out;
}

// ------------------------------------------------------------ mirror payload
step(`Mirroring ${CLAUDE} -> repo`);
const orphans = [];

for (const dir of PAYLOAD) {
  const src = path.join(CLAUDE, dir);
  const dst = path.join(REPO, dir);
  if (!fs.existsSync(src)) {
    warn(`${dir}/ not present in ${CLAUDE} — skipped`);
    continue;
  }

  const live = walk(src);
  let copied = 0;
  for (const rel of live) {
    const from = path.join(src, ...rel.split('/'));
    const to = path.join(dst, ...rel.split('/'));
    const same =
      fs.existsSync(to) && fs.readFileSync(to).equals(fs.readFileSync(from));
    if (same) continue;
    if (DRY) {
      log(`[dry-run] would copy ${dir}/${rel}`);
    } else {
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(from, to);
    }
    copied++;
  }

  const liveSet = new Set(live);
  for (const rel of walk(dst)) {
    const key = `${dir}/${rel}`;
    if (liveSet.has(rel) || REPO_ONLY.has(key)) continue;
    orphans.push(key);
    if (PRUNE && !DRY) fs.unlinkSync(path.join(dst, ...rel.split('/')));
  }

  log(`${dir}/  ${live.length} live, ${copied} updated`);
}

if (orphans.length) {
  step(PRUNE ? 'Pruned repo-only files' : 'Repo-only files (not in ~/.claude)');
  for (const o of orphans) log(PRUNE ? `deleted ${o}` : o);
  if (!PRUNE) log('re-run with --prune to delete them');
}

// ---------------------------------------------------------------- settings
step('Regenerating config/settings.template.json');
const liveSettings = readJson(path.join(CLAUDE, 'settings.json'));
if (!liveSettings) {
  warn('~/.claude/settings.json unreadable — template left unchanged');
} else {
  const { mcpServers, ...rest } = liveSettings;
  const tpl = sanitize(rest, 'settings');
  // This toolkit is installed by cloning, not from a marketplace, so a
  // self-reference in enabledPlugins would dangle on the new machine.
  if (tpl.enabledPlugins) {
    tpl.enabledPlugins = Object.fromEntries(
      Object.entries(tpl.enabledPlugins).filter(([id]) => !id.startsWith('arsenal-'))
    );
  }
  writeJson(path.join(REPO, 'config/settings.template.json'), {
    $schema: 'https://json.schemastore.org/claude-code-settings.json',
    ...tpl,
  });
  if (mcpServers) log('mcpServers moved to config/mcp-servers.json');
}

// -------------------------------------------------------------------- mcp
step('Regenerating config/mcp-servers.json');
const fromSettings = (liveSettings && liveSettings.mcpServers) || {};
const fromClaudeJson = (readJson(CLAUDE_JSON) || {}).mcpServers || {};
// ~/.claude.json is what the running CLI actually loads, so it wins on conflict.
const merged = { ...fromSettings, ...fromClaudeJson };

const servers = {};
for (const [name, spec] of Object.entries(merged)) servers[name] = sanitize(spec, name);

const existingMcp = readJson(path.join(REPO, 'config/mcp-servers.json'));
writeJson(path.join(REPO, 'config/mcp-servers.json'), {
  $comment: (existingMcp && existingMcp.$comment) || [
    'Local MCP servers, registered at user scope by install.sh / install.ps1.',
    'Secrets are ${ENV_VAR} placeholders — never commit real tokens here.',
  ],
  servers,
});
log(`${Object.keys(servers).length} server(s): ${Object.keys(servers).join(', ')}`);

// ---------------------------------------------------------------- plugins
step('Regenerating config/plugins.json');
const installed = readJson(path.join(CLAUDE, 'plugins/installed_plugins.json'));
const known = readJson(path.join(CLAUDE, 'plugins/known_marketplaces.json'));

if (!installed || !known) {
  warn('plugin manifests unreadable — config/plugins.json left unchanged');
} else {
  const marketplaces = Object.entries(known).map(([name, v]) => {
    const s = (v && v.source) || {};
    return { name, source: s.repo || s.url || s.source || name };
  });
  // Plugins shipped by this repo itself are installed by cloning, not from a
  // marketplace, so they are excluded from the restore list.
  const plugins = Object.keys(installed.plugins || {}).filter(
    (id) => !id.startsWith('arsenal-')
  );
  writeJson(path.join(REPO, 'config/plugins.json'), {
    $comment:
      'Marketplaces + plugins to restore on a fresh machine. Consumed by install.sh / install.ps1.',
    marketplaces,
    plugins,
  });
  log(`${marketplaces.length} marketplace(s), ${plugins.length} plugin(s)`);
}

// -------------------------------------------------------------- env example
if (envVarNames.size) {
  step('Secrets templatized');
  for (const v of [...envVarNames].sort()) log(`\${${v}}`);
  log('make sure each is listed in config/.env.example');
}

step('Done');
log('next: node tools/scan-secrets.js && git add -A && git commit');
