<#
  Mode themes — flip the LIVE Windows Terminal color scheme to match the active operating mode,
  and revert cleanly. Windows Terminal hot-reloads settings.json, so the open window repaints on
  save. One file covers all nine modes.

  Each mode has a distinct scheme applied to EVERY profile (and defaults), because per-profile
  overrides beat a defaults-only change. A one-time backup preserves your TRUE original settings.

  Two scopes:
    (default) edits Windows Terminal settings.json — persistent, applies to ALL tabs/windows.
    -Session  recolors ONLY the current terminal via ANSI OSC — per-tab, no file edit, other tabs
              untouched. Best run directly in the terminal you want to theme. Works in any
              OSC-capable host (Windows Terminal, VS Code, most xterm-likes).

  Usage:
    mode-theme.ps1 batman              # global: Batman scheme via settings.json (all tabs)
    mode-theme.ps1 batman -Session     # THIS tab only (recommended for per-session identity)
    mode-theme.ps1 fight-club          # crimson/dark 'unleash' signal (global)
    mode-theme.ps1 off                 # revert global to your exact original settings
    mode-theme.ps1 off -Session        # reset just this tab
    mode-theme.ps1 list                # list modes and their palettes
    mode-theme.ps1 joker -SettingsPath C:\tmp\settings.json   # target a file (testing)

  Aliases: john-wick=wick, jack-sparrow=sparrow, thomas-shelby=shelby, dr-strange=strange,
           alter-ego/alterego/tyler=fight-club.
#>
param(
  [Parameter(Mandatory, Position = 0)][string]$Mode,
  [string]$SettingsPath,
  [switch]$Session
)
$ErrorActionPreference = 'Stop'

if (-not $SettingsPath) {
  $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
}
$backup = Join-Path (Split-Path $SettingsPath -Parent) 'settings.opmode-backup.json'

# canonical mode <- alias
$aliases = @{
  'batman' = 'batman'; 'ironman' = 'ironman'
  'wick' = 'wick'; 'john-wick' = 'wick'; 'johnwick' = 'wick'
  'thanos' = 'thanos'
  'sparrow' = 'sparrow'; 'jack-sparrow' = 'sparrow'; 'jacksparrow' = 'sparrow'
  'joker' = 'joker'
  'shelby' = 'shelby'; 'thomas-shelby' = 'shelby'; 'thomasshelby' = 'shelby'
  'strange' = 'strange'; 'dr-strange' = 'strange'; 'drstrange' = 'strange'
  'fight-club' = 'fightclub'; 'fightclub' = 'fightclub'; 'alter-ego' = 'fightclub'; 'alterego' = 'fightclub'; 'tyler' = 'fightclub'
}

# one scheme per mode — name + 20 Windows-Terminal color fields
$schemes = [ordered]@{
  batman = [ordered]@{ name = 'Batman'; background = '#0B0E14'; foreground = '#C7D0DB'; cursorColor = '#5B8DEF'; selectionBackground = '#1E3A5F'
    black = '#1B2029'; red = '#C0503A'; green = '#6E8F7A'; yellow = '#C9A227'; blue = '#3E6FB0'; purple = '#5B6EA6'; cyan = '#4C8FA6'; white = '#C7D0DB'
    brightBlack = '#3A4250'; brightRed = '#E0664A'; brightGreen = '#8FB39C'; brightYellow = '#E6C34A'; brightBlue = '#5B8DEF'; brightPurple = '#7E92C8'; brightCyan = '#6FB2C8'; brightWhite = '#EDF1F6' }
  ironman = [ordered]@{ name = 'Ironman'; background = '#0A0A0A'; foreground = '#F0E6D2'; cursorColor = '#FFD447'; selectionBackground = '#5A1010'
    black = '#1A1414'; red = '#E62222'; green = '#8F9E4B'; yellow = '#FFB000'; blue = '#B5552A'; purple = '#B03050'; cyan = '#C77A3A'; white = '#EDE3CF'
    brightBlack = '#3A2A2A'; brightRed = '#FF3B3B'; brightGreen = '#B7C766'; brightYellow = '#FFD447'; brightBlue = '#E0803A'; brightPurple = '#E0577E'; brightCyan = '#F0A055'; brightWhite = '#FFF6E6' }
  wick = [ordered]@{ name = 'JohnWick'; background = '#050506'; foreground = '#B8BCC0'; cursorColor = '#8A0303'; selectionBackground = '#2A0A0A'
    black = '#141416'; red = '#8A0303'; green = '#5F6E5A'; yellow = '#8A7B4A'; blue = '#3A4A5A'; purple = '#5A3A4A'; cyan = '#4A6A6A'; white = '#B8BCC0'
    brightBlack = '#2E3034'; brightRed = '#C21B1B'; brightGreen = '#8A9A85'; brightYellow = '#B3A36A'; brightBlue = '#5A6E82'; brightPurple = '#8A5A72'; brightCyan = '#6E9A9A'; brightWhite = '#E6E9EC' }
  thanos = [ordered]@{ name = 'Thanos'; background = '#0E0A16'; foreground = '#D9CEEA'; cursorColor = '#9B5DE5'; selectionBackground = '#3B2A5A'
    black = '#1C1630'; red = '#B0446A'; green = '#6E9E8A'; yellow = '#D9A441'; blue = '#5A5DB0'; purple = '#9B5DE5'; cyan = '#5AA6C8'; white = '#D9CEEA'
    brightBlack = '#3A3358'; brightRed = '#D9668C'; brightGreen = '#8FBFA8'; brightYellow = '#F0C05A'; brightBlue = '#7E82E0'; brightPurple = '#B884F5'; brightCyan = '#7EC8E6'; brightWhite = '#F0E9FA' }
  sparrow = [ordered]@{ name = 'JackSparrow'; background = '#071A1A'; foreground = '#E6D8B8'; cursorColor = '#E0A83B'; selectionBackground = '#0E3A3A'
    black = '#123030'; red = '#B5613A'; green = '#3FA98A'; yellow = '#E0A83B'; blue = '#2E7A8A'; purple = '#8A6A9A'; cyan = '#3FB5B5'; white = '#E6D8B8'
    brightBlack = '#2E5252'; brightRed = '#D98A5A'; brightGreen = '#6FD9B5'; brightYellow = '#F0C866'; brightBlue = '#5AA6B5'; brightPurple = '#B08FC0'; brightCyan = '#6FE0E0'; brightWhite = '#F5ECD6' }
  joker = [ordered]@{ name = 'Joker'; background = '#0C0714'; foreground = '#D6D0DE'; cursorColor = '#39FF14'; selectionBackground = '#3A1D5A'
    black = '#1A1226'; red = '#B02D6A'; green = '#39FF14'; yellow = '#B7C742'; blue = '#6A3AB0'; purple = '#8E2DE2'; cyan = '#4AB5A6'; white = '#D6D0DE'
    brightBlack = '#3A2C52'; brightRed = '#E0568C'; brightGreen = '#7CFF5A'; brightYellow = '#D6E066'; brightBlue = '#9B5DE5'; brightPurple = '#B884F5'; brightCyan = '#6FD9C8'; brightWhite = '#F0EAF7' }
  shelby = [ordered]@{ name = 'ThomasShelby'; background = '#0F0D0A'; foreground = '#CDBFA6'; cursorColor = '#D9A441'; selectionBackground = '#3A2E1C'
    black = '#1C1913'; red = '#9E5A3A'; green = '#6E7A5A'; yellow = '#D9A441'; blue = '#4A5A6A'; purple = '#7A5A5A'; cyan = '#6A7A72'; white = '#CDBFA6'
    brightBlack = '#3A342A'; brightRed = '#C27A56'; brightGreen = '#93A07A'; brightYellow = '#E6C066'; brightBlue = '#6E8296'; brightPurple = '#A07E7E'; brightCyan = '#93A69A'; brightWhite = '#E6DAC4' }
  strange = [ordered]@{ name = 'DrStrange'; background = '#06121A'; foreground = '#CFE7EA'; cursorColor = '#E6B54A'; selectionBackground = '#0C3A44'
    black = '#10242C'; red = '#C05A4A'; green = '#3FA98A'; yellow = '#E6B54A'; blue = '#2E8AA6'; purple = '#6A6AC0'; cyan = '#2BD9D9'; white = '#CFE7EA'
    brightBlack = '#2E4A52'; brightRed = '#E07E6A'; brightGreen = '#6FD9B5'; brightYellow = '#F0CC66'; brightBlue = '#5AB5D9'; brightPurple = '#8A8AE0'; brightCyan = '#66F0F0'; brightWhite = '#E6F5F7' }
  fightclub = [ordered]@{ name = 'FightClub'; background = '#0A0A0A'; foreground = '#E6E6E6'; cursorColor = '#FF2A2A'; selectionBackground = '#7A0000'
    black = '#1A1A1A'; red = '#E01A1A'; green = '#8A8A8A'; yellow = '#C0392B'; blue = '#7A0000'; purple = '#A00000'; cyan = '#B03030'; white = '#D0D0D0'
    brightBlack = '#3A3A3A'; brightRed = '#FF2A2A'; brightGreen = '#A0A0A0'; brightYellow = '#E74C3C'; brightBlue = '#C0392B'; brightPurple = '#E01A1A'; brightCyan = '#FF4040'; brightWhite = '#FFFFFF' }
}
$ourSchemeNames = @($schemes.Keys | ForEach-Object { $schemes[$_].name })

$m = $Mode.ToLower()

if ($m -eq 'list') {
  Write-Host "Mode themes:" -ForegroundColor Cyan
  foreach ($k in $schemes.Keys) {
    $s = $schemes[$k]
    Write-Host ("  {0,-9} {1,-13} bg {2}  accent {3}" -f $k, $s.name, $s.background, $s.cursorColor)
  }
  exit 0
}

# -Session: recolor ONLY the current terminal via ANSI OSC — per-tab, no settings.json edit, other
# tabs untouched. Most reliable when run directly in the terminal you want to theme.
if ($Session) {
  $ESC = [char]27; $BEL = [char]7
  if ($m -eq 'off') {
    [Console]::Out.Write("$ESC]104$BEL$ESC]110$BEL$ESC]111$BEL$ESC]112$BEL")  # reset palette/fg/bg/cursor
    Write-Host "Session theme reset (this terminal only)." -ForegroundColor Green
    exit 0
  }
  if (-not $aliases.ContainsKey($m)) { Write-Warning "Unknown mode '$Mode'. Valid: $($aliases.Keys -join ', '), off, list."; exit 2 }
  $s = $schemes[$aliases[$m]]
  $pal = 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white', 'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
  $seq = "$ESC]11;$($s.background)$BEL$ESC]10;$($s.foreground)$BEL$ESC]12;$($s.cursorColor)$BEL"
  for ($i = 0; $i -lt 16; $i++) { $seq += "$ESC]4;$i;$($s[$pal[$i]])$BEL" }
  [Console]::Out.Write($seq)
  Write-Host "Session theme '$($s.name)' applied to THIS terminal only (other tabs unaffected). Run 'mode-theme.ps1 off -Session' to reset." -ForegroundColor Green
  exit 0
}

if ($m -eq 'off') {
  if (Test-Path $backup) {
    Copy-Item $backup $SettingsPath -Force
    Remove-Item $backup -Force
    Write-Host "Mode theme OFF — original terminal theme restored." -ForegroundColor Green
  } else {
    Write-Host "No mode-theme backup found; nothing to revert." -ForegroundColor Yellow
  }
  exit 0
}

if (-not $aliases.ContainsKey($m)) {
  Write-Warning "Unknown mode '$Mode'. Valid: $($aliases.Keys -join ', '), off, list."
  exit 2
}
if (-not (Test-Path $SettingsPath)) {
  Write-Warning "Windows Terminal settings.json not found at $SettingsPath — are you in Windows Terminal? (IDE terminals need host-specific theming; see README roadmap.)"
  exit 1
}
if (-not $env:WT_SESSION -and -not $PSBoundParameters.ContainsKey('SettingsPath')) {
  Write-Warning "WT_SESSION not set: this shell may not be hosted by Windows Terminal, so the repaint may not show. Editing settings.json anyway."
}

$scheme = $schemes[$aliases[$m]]

# preserve the TRUE original, once
if (-not (Test-Path $backup)) { Copy-Item $SettingsPath $backup -Force }

$raw   = Get-Content $SettingsPath -Raw
$clean = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
$json  = $clean | ConvertFrom-Json -AsHashtable

if (-not $json.schemes) { $json.schemes = @() }
# drop any of OUR schemes, then add the selected one (keeps the list clean across switches)
$json.schemes = @($json.schemes | Where-Object { $ourSchemeNames -notcontains $_.name }) + $scheme

if (-not $json.profiles)          { $json.profiles = @{} }
if (-not $json.profiles.defaults) { $json.profiles.defaults = @{} }
$json.profiles.defaults.colorScheme = $scheme.name
if ($json.profiles.list) { foreach ($p in $json.profiles.list) { $p.colorScheme = $scheme.name } }

($json | ConvertTo-Json -Depth 32) | Set-Content $SettingsPath -Encoding UTF8
Write-Host "Mode theme ON — '$($scheme.name)' applied to all profiles." -ForegroundColor Green
Write-Host "If the open tab didn't repaint, open a NEW tab (Ctrl+Shift+T)." -ForegroundColor DarkGray
