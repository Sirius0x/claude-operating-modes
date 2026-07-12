<#
  Cross-agent installer for Claude Operating Modes.

  Deploys the portable payload (SKILL.md, CRAFT.md, AGENTS.md, mode-theme.ps1) into each detected
  AI agent's config, and injects the always-loaded quick-ref (AGENTS.md) into that agent's global
  instruction file inside a MANAGED BLOCK — so re-running updates only our block and never clobbers
  the user's own instructions.

  Supported agents:
    claude-code : bundle -> ~/.claude/skills/operating-modes/ ; quick-ref -> ~/.claude/CLAUDE.md
                  ; /mode command -> ~/.claude/commands/mode.md
    codex       : bundle -> ~/.codex/operating-modes/          ; quick-ref -> ~/.codex/AGENTS.md

  Usage:
    .\install.ps1                 # install to every agent whose home dir exists (Claude if none)
    .\install.ps1 -All            # install to Claude Code AND Codex (create dirs as needed)
    .\install.ps1 -Claude         # Claude Code only
    .\install.ps1 -Codex          # Codex only
    .\install.ps1 -DryRun         # show exactly what would change; write nothing
    .\install.ps1 -All -DryRun    # preview a full install
#>
[CmdletBinding()]
param(
  [switch]$Claude,
  [switch]$Codex,
  [switch]$All,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$skill = Join-Path $root 'skill'
$begin = '<!-- BEGIN operating-modes (managed by claude-operating-modes installer — edits here are overwritten) -->'
$end   = '<!-- END operating-modes -->'

function Write-Step($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# Copy the payload into a bundle dir; substitute {{BUNDLE_DIR}} in the deployed AGENTS.md.
function Deploy-Bundle($bundleDir) {
  if ($DryRun) { Write-Step "  would copy SKILL.md, CRAFT.md, AGENTS.md, mode-theme.ps1 -> $bundleDir (pruning legacy alter-ego.ps1/install.ps1)" 'DarkGray'; return }
  New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
  # prune files left by older installs that are no longer part of the payload
  foreach ($stale in 'alter-ego.ps1', 'install.ps1') {
    $p = Join-Path $bundleDir $stale
    if (Test-Path $p) { Remove-Item $p -Force }
  }
  Copy-Item (Join-Path $skill 'SKILL.md') (Join-Path $bundleDir 'SKILL.md') -Force
  Copy-Item (Join-Path $skill 'CRAFT.md') (Join-Path $bundleDir 'CRAFT.md') -Force
  Copy-Item (Join-Path $root 'scripts\mode-theme.ps1') (Join-Path $bundleDir 'mode-theme.ps1') -Force
  $agents = (Get-Content (Join-Path $skill 'AGENTS.md') -Raw).Replace('{{BUNDLE_DIR}}', $bundleDir)
  Set-Content (Join-Path $bundleDir 'AGENTS.md') $agents -Encoding UTF8
  Write-Step "  bundle -> $bundleDir" 'Green'
}

# Build the managed block (quick-ref with the bundle path resolved).
function Get-Block($bundleDir) {
  $body = (Get-Content (Join-Path $skill 'AGENTS.md') -Raw).Replace('{{BUNDLE_DIR}}', $bundleDir).TrimEnd()
  "$begin`n$body`n$end"
}

# Idempotently inject the block into a global instruction file: replace an existing block, else append.
function Inject-Block($file, $block) {
  $exists  = Test-Path $file
  $content = if ($exists) { Get-Content $file -Raw } else { '' }
  $has     = $content -match [regex]::Escape($begin)
  if ($DryRun) {
    $verb = if (-not $exists) { 'create + add block' } elseif ($has) { 'update managed block in' } else { 'append block to' }
    Write-Step "  would $verb $file" 'DarkGray'; return
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent) | Out-Null
  if ($has) {
    $pattern = [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
    $new = [regex]::Replace($content, $pattern, { param($m) $block }, 'Singleline')
    Write-Step "  updated managed block in $file" 'Green'
  } elseif ($exists -and $content.Trim()) {
    $new = $content.TrimEnd() + "`n`n" + $block + "`n"
    Write-Step "  appended managed block to $file" 'Green'
  } else {
    $new = $block + "`n"
    Write-Step "  wrote $file" 'Green'
  }
  Set-Content $file $new -Encoding UTF8
}

function Install-ClaudeCode {
  Write-Step "claude-code:" 'Cyan'
  $agentHome = Join-Path $env:USERPROFILE '.claude'
  $bundle = Join-Path $agentHome 'skills\operating-modes'
  Deploy-Bundle $bundle
  Inject-Block (Join-Path $agentHome 'CLAUDE.md') (Get-Block $bundle)
  $cmd = Join-Path $agentHome 'commands\mode.md'
  if ($DryRun) { Write-Step "  would install /mode command -> $cmd" 'DarkGray' }
  else {
    New-Item -ItemType Directory -Force -Path (Split-Path $cmd -Parent) | Out-Null
    Copy-Item (Join-Path $root 'agents\claude-code\commands\mode.md') $cmd -Force
    Write-Step "  /mode command -> $cmd" 'Green'
  }
}

function Install-Codex {
  Write-Step "codex:" 'Cyan'
  $agentHome = Join-Path $env:USERPROFILE '.codex'
  $bundle = Join-Path $agentHome 'operating-modes'
  Deploy-Bundle $bundle
  Inject-Block (Join-Path $agentHome 'AGENTS.md') (Get-Block $bundle)
}

# ---- decide targets ----
$doClaude = $Claude -or $All
$doCodex  = $Codex  -or $All
if (-not ($doClaude -or $doCodex)) {
  # auto-detect: install to whichever agent home dirs already exist; default to Claude if none.
  $doClaude = Test-Path (Join-Path $env:USERPROFILE '.claude')
  $doCodex  = Test-Path (Join-Path $env:USERPROFILE '.codex')
  if (-not ($doClaude -or $doCodex)) { $doClaude = $true }
}

if ($DryRun) { Write-Step "== DRY RUN — no files will be written ==" 'Yellow' }
if ($doClaude) { Install-ClaudeCode }
if ($doCodex)  { Install-Codex }

Write-Step ""
Write-Step "Done. Select a mode with 'op:<mode>' (any agent), '/mode <mode>' (Claude Code), or '<mode> mode'." 'Cyan'
Write-Step "For agents not covered above, add the contents of skill/AGENTS.md to that agent's global rules file." 'DarkGray'
