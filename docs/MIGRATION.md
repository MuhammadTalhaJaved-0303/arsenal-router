# Moving your Claude Code setup to a new machine

This repo carries everything portable about a Claude Code install: agents,
commands, skills, rules, hooks, hook scripts, settings, the plugin list, and
local MCP server definitions. Credentials are deliberately **not** in here.

## On the new machine (macOS)

```bash
# 1. Prerequisites
brew install node git
npm install -g @anthropic-ai/claude-code   # or the installer from claude.com/claude-code

# 2. Clone and install
git clone https://github.com/MuhammadTalhaJaved-0303/arsenal-code.git
cd arsenal-code
chmod +x install.sh
./install.sh
```

`install.sh` will:

1. Back up any existing `~/.claude/{agents,commands,skills,rules,scripts,hooks}`
   to `~/.claude/backups/arsenal-<timestamp>/`
2. Copy this repo's versions into `~/.claude/`
3. Merge `config/settings.template.json` into `~/.claude/settings.json` —
   objects are merged key by key and machine-local keys survive, but **arrays
   are replaced wholesale**, so a machine-specific `permissions.allow` entry is
   overwritten by the template's list. The pre-merge file is kept in the backup
   directory if you need to re-add anything.
4. Add the marketplaces from `config/plugins.json` and install every plugin
5. Register every MCP server from `config/mcp-servers.json` at user scope

Useful flags:

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every action, change nothing |
| `--link` | Symlink `~/.claude/*` at the clone instead of copying, so edits flow straight back into git |
| `--no-plugins` | Skip marketplace + plugin installation |
| `--no-mcp` | Skip MCP registration |

## 3. Supply the secrets

Nothing in this repo contains a token. `config/mcp-servers.json` uses
`${ENV_VAR}` placeholders that Claude Code expands from your shell environment.

```bash
cp config/.env.example ~/arsenal-secrets.sh
$EDITOR ~/arsenal-secrets.sh          # fill in the real values
echo 'source ~/arsenal-secrets.sh' >> ~/.zshrc
source ~/.zshrc
```

Where to get each one:

| Variable | Source |
|----------|--------|
| `VERCEL_API_TOKEN` | https://vercel.com/account/tokens |
| `SENTRY_AUTH_TOKEN` | https://sentry.io/settings/account/api/auth-tokens/ |
| `GITHUB_MCP_TOKEN` | GitHub → Settings → Developer settings → Tokens (`repo`, `read:org`) |

Generate **fresh** tokens for the Mac rather than copying the Windows ones —
the old machine's copies stay valid and you can revoke either independently.

## 4. Re-authorize the claude.ai connectors

These are **account-level**, not files, so they are not in this repo and cannot
be. After signing in to Claude Code on the Mac, re-authorize them from your
claude.ai connector settings:

- Google Drive, Gmail, Google Calendar
- n8n
- Canva, Lovable, PlayMCP, Upwork

## 5. Verify

```bash
claude
```

then inside the session:

```
/plugin      # 15 plugins listed and enabled
/mcp         # local servers connected, connectors authorized
/agents      # 19 agents
/help        # slash commands present
```

## Keeping the two machines in sync

Whichever machine you changed last is the source of truth. On that machine:

```bash
node tools/sync.js            # pull ~/.claude back into the repo, secrets stripped
node tools/scan-secrets.js    # gate: fails if anything credential-shaped slipped in
git add -A && git commit -m "chore: sync claude config" && git push
```

Then on the other machine: `git pull && ./install.sh`.

`sync.js` never deletes by default. If you removed a skill locally and want the
repo to match, run `node tools/sync.js --prune`.

## What is intentionally not synced

| Not synced | Why |
|-----------|-----|
| `~/.claude/.credentials.json` | Auth token for your Anthropic account — machine-local |
| `~/.claude/projects/`, `sessions/`, `history.jsonl` | Per-machine conversation history |
| `~/.claude/plugins/cache/`, `marketplaces/` | Re-downloaded by `claude plugin install` |
| `~/.claude/{cache,debug,shell-snapshots,session-env,file-history}` | Transient runtime state |
| `~/.claude.json` | Mixed device state + telemetry; only its `mcpServers` block is portable, and `sync.js` extracts that |

## Known gap

`hooks/hooks.json` has two entries that call
`scripts/hooks/run-with-flags-shell.sh`, which does not exist in this repo (it
came from the `everything-claude-code` plugin). Those two hooks — the
`continuous-learning-v2` observe hooks — fail silently on both platforms. Either
supply that shell wrapper or delete the two `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks/run-with-flags-shell.sh"`
entries from `hooks/hooks.json`.
