# Arsenal Router

**Smart prompt router for Claude Code** — auto-classifies every task as Vanilla, Scout, or Arsenal mode to optimize token usage and maximize productivity.

## The Problem

Claude Code has dozens of tools: agents, skills, MCP servers, commands, hooks. Using them all on every prompt wastes tokens. Not using them on complex tasks wastes time. There's no middle ground.

## The Solution

Arsenal Router automatically classifies each prompt:

| Mode | When | Token Cost | Action |
|------|------|------------|--------|
| 🟢 **Vanilla** | Simple edits, git ops, questions | Low | Direct work, no overhead |
| 🟡 **Scout** | Unclear scope, needs exploration | Medium | Research first, then reclassify |
| 🔴 **Arsenal** | Multi-file features, architecture, debugging | High | Deploy relevant agents/skills/MCP |

### Key Features

- **Auto-discovers your tools** — reads your system prompt to find installed agents, skills, MCP servers. Never hardcoded.
- **Right-sizes resources** — Arsenal doesn't mean "use everything." It means "use what's needed."
- **User override** — say "use Arsenal" or `/arsenal` to force full power mode.
- **Zero config** — install and forget. Works with any Claude Code setup.

## Installation

### Claude Code (Plugin Marketplace)

```bash
/install arsenal-router
```

### Manual Installation

Clone this repo into your Claude Code plugins directory:

```bash
cd ~/.claude/plugins/cache
git clone https://github.com/MuhammadTalhaJaved-0303/arsenal-router
```

## Usage

**It runs automatically.** After installation, Arsenal Router classifies every prompt silently.

- Simple tasks → just does the work (no announcement)
- Complex tasks → announces "Arsenal: [plan]. Using: [tools]" then executes
- Force full power → type `/arsenal` or say "use Arsenal"

## Examples

```
You: "fix the typo in Header.tsx"
→ [Vanilla: just fixes it, no agents launched]

You: "build a notification system with email, push, and in-app"
→ Arsenal: Multi-service notification system. Using: planner, architect, tdd-guide (parallel).

You: "can we add dark mode?"
→ [Scout: explores current theming setup, then classifies as Vanilla or Arsenal]

You: "use Arsenal and audit security"
→ Arsenal activated. Using: security-reviewer, code-reviewer (parallel).
```

## How It Works

1. **Skill loads** on every message (via Claude's skill system)
2. **Scans system prompt** to discover installed tools (agents, skills, MCP, commands)
3. **Classifies** the prompt using rule-based heuristics (no API calls, no extra tokens)
4. **Enforces** the mode — prevents wasteful agent launches on simple tasks
5. **Escalates** mid-task if hidden complexity is discovered

## Compatibility

Works with any Claude Code setup:
- Superpowers plugin ✓
- Everything Claude Code toolkit ✓
- Custom agents ✓
- Any MCP servers ✓
- Bare Claude Code (no plugins) ✓

## License

MIT
