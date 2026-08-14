<#
.SYNOPSIS
  Arsenal Code — restore a full Claude Code setup on Windows.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -DryRun
  .\install.ps1 -NoPlugins -NoMcp
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$NoPlugins,
  [switch]$NoMcp
)

$ErrorActionPreference = 'Continue'

$RepoDir   = $PSScriptRoot
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ClaudeDir "backups\arsenal-$Stamp"
$Payload   = @('agents','commands','skills','rules','scripts','hooks')

function Write-Step($m) { Write-Host ''; Write-Host $m -ForegroundColor White }
function Write-Info($m) { Write-Host "  $m" }
function Write-Warn($m) { Write-Host "  warn: $m" -ForegroundColor Yellow }
function Write-Fail($m) { Write-Host "  fail: $m" -ForegroundColor Red }

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Backup-Path($path, $label) {
  if (-not (Test-Path $path)) { return }
  if ($DryRun) { Write-Info "[dry-run] would back up $label"; return }
  New-Item -ItemType Directory -Force $BackupDir | Out-Null
  Move-Item $path (Join-Path $BackupDir $label) -Force
  Write-Info "backed up existing $label"
}

# ---------------------------------------------------------------- preflight
Write-Step 'Preflight'
$missing = $false
foreach ($bin in @('node','git')) {
  if (Test-Cmd $bin) { Write-Info "$bin  $((& $bin --version 2>&1 | Select-Object -First 1))" }
  else { Write-Fail "$bin not found - required (hooks are Node scripts)"; $missing = $true }
}
$hasClaude = Test-Cmd 'claude'
if ($hasClaude) {
  Write-Info "claude  $((& claude --version 2>&1 | Select-Object -First 1))"
} else {
  Write-Warn 'claude CLI not found - plugin and MCP steps will be skipped.'
  $NoPlugins = $true; $NoMcp = $true
}
if ($missing) { exit 1 }

# ------------------------------------------------------------------ payload
Write-Step "Installing config into $ClaudeDir"
if (-not $DryRun) { New-Item -ItemType Directory -Force $ClaudeDir | Out-Null }

foreach ($dir in $Payload) {
  $src = Join-Path $RepoDir $dir
  $dst = Join-Path $ClaudeDir $dir
  if (-not (Test-Path $src)) { Write-Warn "$dir\ missing from repo - skipped"; continue }

  Backup-Path $dst $dir
  if ($DryRun) {
    Write-Info "[dry-run] would copy $dir\"
  } else {
    Copy-Item $src $dst -Recurse -Force
    $n = @(Get-ChildItem -Recurse -File $src).Count
    Write-Info "copied  $dir\  ($n files)"
  }
}

# ----------------------------------------------------------------- settings
Write-Step 'Merging settings.json'
$settings = Join-Path $ClaudeDir 'settings.json'
$template = Join-Path $RepoDir 'config\settings.template.json'

if (-not (Test-Path $template)) {
  Write-Warn 'config\settings.template.json missing - skipped'
} elseif ($DryRun) {
  Write-Info "[dry-run] would merge $template into $settings"
} else {
  if (Test-Path $settings) {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    Copy-Item $settings (Join-Path $BackupDir 'settings.json') -Force
  }
  # Template wins on conflict; local-only keys are preserved.
  $mergeScript = @'
const fs = require('fs');
const [tplPath, outPath] = process.argv.slice(2);
const read = p => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return {}; } };
const merge = (base, over) => {
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) {
    out[k] = v && typeof v === 'object' && !Array.isArray(v) &&
             base[k] && typeof base[k] === 'object' && !Array.isArray(base[k])
      ? merge(base[k], v) : v;
  }
  return out;
};
fs.writeFileSync(outPath, JSON.stringify(merge(read(outPath), read(tplPath)), null, 2) + '\n');
console.log('  wrote ' + outPath);
'@
  $tmp = Join-Path $env:TEMP "arsenal-merge-$Stamp.js"
  Set-Content -Path $tmp -Value $mergeScript -Encoding utf8
  & node $tmp $template $settings
  if ($LASTEXITCODE -ne 0) { Write-Fail 'settings merge failed' }
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------ plugins
if (-not $NoPlugins) {
  Write-Step 'Restoring plugins'
  $pluginsJson = Join-Path $RepoDir 'config\plugins.json'
  if (-not (Test-Path $pluginsJson)) {
    Write-Warn 'config\plugins.json missing - skipped'
  } else {
    $cfg = Get-Content $pluginsJson -Raw | ConvertFrom-Json
    foreach ($m in $cfg.marketplaces) {
      Write-Info "marketplace: $($m.name)"
      if (-not $DryRun) {
        & claude plugin marketplace add $m.source *>$null
        if ($LASTEXITCODE -ne 0) { Write-Warn "could not add marketplace $($m.name) - may already exist" }
      }
    }
    foreach ($p in $cfg.plugins) {
      if ($DryRun) { Write-Info "[dry-run] would install $p"; continue }
      & claude plugin install $p *>$null
      if ($LASTEXITCODE -eq 0) { Write-Info "installed: $p" }
      else { Write-Warn "could not install $p - install it manually with /plugin" }
    }
  }
}

# --------------------------------------------------------------------- mcp
if (-not $NoMcp) {
  Write-Step 'Registering MCP servers (user scope)'
  $mcpJson = Join-Path $RepoDir 'config\mcp-servers.json'
  if (-not (Test-Path $mcpJson)) {
    Write-Warn 'config\mcp-servers.json missing - skipped'
  } else {
    $cfg = Get-Content $mcpJson -Raw | ConvertFrom-Json
    foreach ($prop in $cfg.servers.PSObject.Properties) {
      $name = $prop.Name
      $spec = $prop.Value | ConvertTo-Json -Depth 20 -Compress
      # Report ${VAR} placeholders that are not set in the environment.
      $unset = [regex]::Matches($spec, '\$\{(\w+)\}') |
               ForEach-Object { $_.Groups[1].Value } |
               Sort-Object -Unique |
               Where-Object { -not (Test-Path "env:$_") }
      if ($unset) { Write-Warn "$name needs unset env var(s): $($unset -join ', ')" }
      if ($DryRun) { Write-Info "[dry-run] would register $name"; continue }
      & claude mcp add-json $name $spec --scope user *>$null
      if ($LASTEXITCODE -eq 0) { Write-Info "registered: $name" }
      else { Write-Warn "could not register $name - add it manually with claude mcp add-json" }
    }
  }
}

Write-Step 'Done'
if (Test-Path $BackupDir) { Write-Info "previous config backed up to $BackupDir" }
Write-Host @'

  Next steps:
    1. Set MCP secrets as environment variables - see config\.env.example
    2. Re-authorize claude.ai connectors (Google Drive, Gmail, n8n, ...) from
       claude.ai connector settings - those are account-level, not in this repo.
    3. Start Claude Code and run  /plugin  and  /mcp  to verify.
'@
