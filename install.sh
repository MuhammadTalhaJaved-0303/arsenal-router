#!/usr/bin/env bash
#
# Arsenal Code — restore a full Claude Code setup on macOS / Linux.
#
#   ./install.sh              copy everything into ~/.claude
#   ./install.sh --link       symlink instead of copy (edits flow back to the repo)
#   ./install.sh --dry-run    show what would happen, change nothing
#   ./install.sh --no-plugins skip marketplace/plugin installation
#   ./install.sh --no-mcp     skip MCP server registration
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/arsenal-$STAMP"

MODE="copy"
DRY_RUN=0
DO_PLUGINS=1
DO_MCP=1

# Payload directories mirrored from the repo into ~/.claude.
PAYLOAD=(agents commands skills rules scripts)

for arg in "$@"; do
  case "$arg" in
    --link)       MODE="link" ;;
    --dry-run)    DRY_RUN=1 ;;
    --no-plugins) DO_PLUGINS=0 ;;
    --no-mcp)     DO_MCP=0 ;;
    -h|--help)    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

info()  { printf '  %s\n' "$*"; }
step()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn()  { printf '  \033[33mwarn:\033[0m %s\n' "$*" >&2; }
fail()  { printf '  \033[31mfail:\033[0m %s\n' "$*" >&2; }
run()   { if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $*"; else "$@"; fi; }

# ---------------------------------------------------------------- preflight
step "Preflight"
MISSING=0
for bin in node git; do
  if command -v "$bin" >/dev/null 2>&1; then
    info "$bin  $("$bin" --version 2>&1 | head -n1)"
  else
    fail "$bin not found — required (hooks are Node scripts)"
    MISSING=1
  fi
done
if command -v claude >/dev/null 2>&1; then
  info "claude  $(claude --version 2>&1 | head -n1)"
else
  warn "claude CLI not found — plugin and MCP steps will be skipped."
  warn "install it first: https://claude.com/claude-code"
  DO_PLUGINS=0
  DO_MCP=0
fi
[ "$MISSING" -eq 1 ] && exit 1

# ------------------------------------------------------------------ payload
step "Installing config into $CLAUDE_DIR  (mode: $MODE)"
run mkdir -p "$CLAUDE_DIR"

for dir in "${PAYLOAD[@]}"; do
  src="$REPO_DIR/$dir"
  dst="$CLAUDE_DIR/$dir"
  if [ ! -d "$src" ]; then
    warn "$dir/ missing from repo — skipped"
    continue
  fi

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    run mkdir -p "$BACKUP_DIR"
    run mv "$dst" "$BACKUP_DIR/$dir"
    info "backed up existing $dir/ -> ${BACKUP_DIR/#$HOME/~}/$dir"
  fi

  if [ "$MODE" = "link" ]; then
    run ln -s "$src" "$dst"
    info "linked  $dir/  ->  $src"
  else
    run cp -R "$src" "$dst"
    info "copied  $dir/  ($(find "$src" -type f | wc -l | tr -d ' ') files)"
  fi
done

# Hooks live at ~/.claude/hooks/hooks.json and reference ${CLAUDE_PLUGIN_ROOT}.
# When installed standalone (not as a plugin) that variable is unset, so point
# it at ~/.claude by rewriting into a settings-level hooks block instead.
if [ -f "$REPO_DIR/hooks/hooks.json" ]; then
  if [ -e "$CLAUDE_DIR/hooks" ] || [ -L "$CLAUDE_DIR/hooks" ]; then
    run mkdir -p "$BACKUP_DIR"
    run mv "$CLAUDE_DIR/hooks" "$BACKUP_DIR/hooks"
  fi
  run cp -R "$REPO_DIR/hooks" "$CLAUDE_DIR/hooks"
  info "copied  hooks/"
fi

# ----------------------------------------------------------------- settings
step "Merging settings.json"
SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE="$REPO_DIR/config/settings.template.json"

if [ ! -f "$TEMPLATE" ]; then
  warn "config/settings.template.json missing — skipped"
elif [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] would merge $TEMPLATE into $SETTINGS"
else
  [ -f "$SETTINGS" ] && { mkdir -p "$BACKUP_DIR"; cp "$SETTINGS" "$BACKUP_DIR/settings.json"; }
  node - "$TEMPLATE" "$SETTINGS" <<'NODE'
const fs = require('fs');
const [tplPath, outPath] = process.argv.slice(2);

const read = p => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return {}; } };

// Template wins on conflict; anything the local file has that the template
// does not is preserved (machine-specific keys, extra permissions, etc.).
const merge = (base, over) => {
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) {
    out[k] = v && typeof v === 'object' && !Array.isArray(v) &&
             base[k] && typeof base[k] === 'object' && !Array.isArray(base[k])
      ? merge(base[k], v)
      : v;
  }
  return out;
};

const merged = merge(read(outPath), read(tplPath));
fs.writeFileSync(outPath, JSON.stringify(merged, null, 2) + '\n');
console.log('  wrote ' + outPath);
NODE
  [ $? -ne 0 ] && fail "settings merge failed — original left at $BACKUP_DIR/settings.json"
fi

# ------------------------------------------------------------------ plugins
if [ "$DO_PLUGINS" -eq 1 ]; then
  step "Restoring plugins"
  PLUGINS_JSON="$REPO_DIR/config/plugins.json"
  if [ ! -f "$PLUGINS_JSON" ]; then
    warn "config/plugins.json missing — skipped"
  else
    while IFS=$'\t' read -r name source; do
      [ -z "$name" ] && continue
      info "marketplace: $name"
      run claude plugin marketplace add "$source" >/dev/null 2>&1 \
        || warn "could not add marketplace $name ($source) — may already exist"
    done < <(node -e '
      const m = require(process.argv[1]).marketplaces || [];
      for (const x of m) console.log(x.name + "\t" + x.source);
    ' "$PLUGINS_JSON")

    while read -r plugin; do
      [ -z "$plugin" ] && continue
      if run claude plugin install "$plugin" >/dev/null 2>&1; then
        info "installed: $plugin"
      else
        warn "could not install $plugin — install it manually with /plugin"
      fi
    done < <(node -e '
      for (const p of require(process.argv[1]).plugins || []) console.log(p);
    ' "$PLUGINS_JSON")
  fi
fi

# --------------------------------------------------------------------- mcp
if [ "$DO_MCP" -eq 1 ]; then
  step "Registering MCP servers (user scope)"
  MCP_JSON="$REPO_DIR/config/mcp-servers.json"
  if [ ! -f "$MCP_JSON" ]; then
    warn "config/mcp-servers.json missing — skipped"
  else
    while IFS=$'\t' read -r name spec missing; do
      [ -z "$name" ] && continue
      if [ -n "$missing" ]; then
        warn "$name needs unset env var(s): $missing — registering anyway, export them before use"
      fi
      if run claude mcp add-json "$name" "$spec" --scope user >/dev/null 2>&1; then
        info "registered: $name"
      else
        warn "could not register $name — add it manually with: claude mcp add-json $name '<json>'"
      fi
    done < <(node -e '
      const cfg = require(process.argv[1]);
      for (const [name, spec] of Object.entries(cfg.servers || {})) {
        const missing = new Set();
        // Report ${VAR} placeholders that are not set in the environment.
        JSON.stringify(spec).replace(/\$\{(\w+)\}/g, (_, v) => {
          if (!process.env[v]) missing.add(v);
          return "";
        });
        console.log([name, JSON.stringify(spec), [...missing].join(",")].join("\t"));
      }
    ' "$MCP_JSON")
  fi
fi

# ------------------------------------------------------------------- done
step "Done"
[ -d "$BACKUP_DIR" ] && info "previous config backed up to ${BACKUP_DIR/#$HOME/~}"
cat <<EOF

  Next steps:
    1. Export MCP secrets in ~/.zshrc — see config/.env.example
    2. Re-authorize claude.ai connectors (Google Drive, Gmail, n8n, ...) from
       claude.ai connector settings — those are account-level, not in this repo.
    3. Start Claude Code and run  /plugin  and  /mcp  to verify.
EOF
