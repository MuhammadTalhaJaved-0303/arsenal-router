# Arsenal Code

**Smart prompt router for AI coding assistants** — auto-classifies every task as Vanilla, Scout, or Arsenal mode to optimize token usage and maximize productivity.

## The Problem

AI coding assistants have dozens of tools: agents, skills, MCP servers, commands, hooks. Using them all on every prompt wastes tokens. Not using them on complex tasks wastes time. There's no middle ground.

## The Solution

Arsenal Code automatically classifies each prompt:

| Mode | When | Token Cost | Action |
|------|------|------------|--------|
| **Vanilla** | Simple edits, git ops, questions | Low | Direct work, no overhead |
| **Scout** | Unclear scope, needs exploration | Medium | Research first, then reclassify |
| **Arsenal** | Multi-file features, architecture, debugging | High | Deploy relevant agents/skills/MCP |

### Key Features

- **Auto-discovers your tools** — reads your environment to find installed agents, skills, MCP servers. Never hardcoded.
- **Right-sizes resources** — Arsenal doesn't mean "use everything." It means "use what's needed."
- **User override** — say "use Arsenal" or `/arsenal` to force full power mode.
- **Zero config** — install and forget. Works with any setup.

## Supported Platforms

| Platform | Status | Install Method |
|----------|--------|---------------|
| **Claude Code** (CLI, Desktop, VS Code, JetBrains) | Full support | Plugin system |
| **Cursor** | Full support | `.cursor/rules/` |
| **Windsurf** (Codeium) | Full support | `.windsurfrules` |
| **VS Code + Copilot** | Full support | `.github/copilot-instructions.md` |
| **Codex** (OpenAI) | Full support | `codex.md` / instructions |
| **Aider** | Full support | `.aider.conf.yml` conventions |
| **Continue.dev** | Full support | `.continuerules` |
| **Zed AI** | Full support | `.zed/rules/` |
| **Cline / Roo Code** | Full support | `.clinerules` |

## Installation

### Claude Code (Plugin)

```bash
/install arsenal-code
```

Or manually:
```bash
cd ~/.claude/plugins/cache
git clone https://github.com/MuhammadTalhaJaved-0303/arsenal-code
```

### Cursor

```bash
npx arsenal-code init --platform cursor
```

Creates `.cursor/rules/arsenal-code.mdc` with the routing logic adapted for Cursor's rule system.

### Windsurf

```bash
npx arsenal-code init --platform windsurf
```

Creates `.windsurfrules` with Arsenal Code routing.

### VS Code + GitHub Copilot

```bash
npx arsenal-code init --platform copilot
```

Creates `.github/copilot-instructions.md` with Arsenal Code routing.

### OpenAI Codex

```bash
npx arsenal-code init --platform codex
```

Creates `codex.md` with Arsenal Code routing adapted for Codex's instruction format.

### Aider

```bash
npx arsenal-code init --platform aider
```

Adds conventions to `.aider.conf.yml`.

### Universal (any platform)

```bash
npx arsenal-code init
```

Auto-detects your platform and generates the appropriate config file.

## Usage

**It runs automatically.** After installation, Arsenal Code classifies every prompt silently.

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

1. **Loads on every message** — via your platform's rule/instruction system
2. **Scans environment** — discovers installed tools (agents, skills, MCP, commands)
3. **Classifies** — rule-based heuristics, no API calls, no extra tokens
4. **Enforces** — prevents wasteful agent launches on simple tasks
5. **Escalates** — mid-task upgrade if hidden complexity is discovered

## Platform Adaptation

Arsenal Code's core routing logic is the same across all platforms. The `init` CLI adapts it to each platform's instruction format:

| Platform Feature | Claude Code | Cursor | Windsurf | Copilot | Codex |
|-----------------|-------------|--------|----------|---------|-------|
| Agents (sub-tasks) | Agent tool | Composer agents | Cascade | Chat participants | Built-in |
| Rules location | `.claude/` | `.cursor/rules/` | `.windsurfrules` | `.github/` | `codex.md` |
| MCP support | Native | Native | Native | Via extensions | Native |
| Slash commands | Skills | N/A | N/A | N/A | N/A |

## What's Included

- **19 specialized agents** — architect, code-reviewer, security-reviewer, tdd-guide, and more
- **35 slash commands** — `/plan`, `/tdd`, `/code-review`, `/verify`, etc.
- **23 skill modules** — API design, frontend patterns, database migrations, etc.
- **14 rule sets** — coding standards, security, testing, git workflow
- **Hooks** — auto-format, security checks, quality gates

> Note: Not all platforms support all features. Claude Code gets the full toolkit. Other platforms get the core routing logic + rules adapted to their capabilities.

## Compatibility

Works alongside your existing setup:
- Superpowers plugin
- Everything Claude Code toolkit
- Custom agents and MCP servers
- Bare installs (no plugins)

## License

MIT
