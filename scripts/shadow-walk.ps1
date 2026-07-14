<#
  Shadow-Walk — a background, lossless step-journal + human-brain-style recall for the operating
  modes. Two responsibilities, dispatched by -Action:

    record   Append one compact line per step to the shared journal. Wired to a PostToolUse hook
             with suppressOutput:true, so it costs ZERO model tokens — the model never sees it run.
             This is the "shadow walk": every step recorded in the background, nothing missed.

    recall   Read the journal and emit a compact recall brief (working / consolidated / long-term
             memory) as hookSpecificOutput.additionalContext. Wired to SessionStart (and, best-
             effort, SubagentStart) so a fresh context — including each mode subagent, which runs
             in its OWN isolated window — gets the shared history back. Recall costs a small,
             bounded number of tokens; the FULL detail always stays on disk for on-demand reading.

    retrieve Content-addressable recall: score journal steps by keyword overlap with the CURRENT
             prompt (BM25-lite, no extra LLM call) and inject the top-K RELEVANT ones as
             additionalContext. Wired to UserPromptSubmit. Where recall answers "what did I just
             do", retrieve answers "what did I ever do that relates to what you're asking now" —
             so an association from 300 steps ago resurfaces exactly when it matters. Gated: an
             unrelated prompt scores nothing and injects nothing.

  Honest note: recording is genuinely free; recall is cheap, not free (anything the model reads is
  tokens). The journal is the single shared brain every mode reads/writes — the only channel that
  can cross isolated subagent contexts.

  Journal:  ~/.claude/shadow-walk/journal.jsonl   (append-only, lossless)
  Usage (normally invoked by hooks, not by hand):
    <hook stdin JSON> | pwsh -NoProfile -File shadow-walk.ps1 record
    <hook stdin JSON> | pwsh -NoProfile -File shadow-walk.ps1 recall
    <hook stdin JSON> | pwsh -NoProfile -File shadow-walk.ps1 retrieve
    pwsh -NoProfile -File shadow-walk.ps1 show     # print the recall brief to your terminal (debug)
#>
param(
  [Parameter(Mandatory, Position = 0)][ValidateSet('record', 'recall', 'retrieve', 'show')][string]$Action,
  [int]$Working = 12,      # verbatim recent steps to surface (working memory)
  [int]$Sessions = 3,      # prior sessions to one-line summarize (long-term memory)
  [int]$Tail = 400,        # recall/retrieve read only the last N journal lines (bounds cost O(1))
  [int]$MaxLines = 4000,   # rotate: keep last N lines in journal, archive the rest
  [int]$TopK = 5           # retrieve: max relevant steps to inject per prompt
)
$ErrorActionPreference = 'Stop'

$dir     = Join-Path $env:USERPROFILE '.claude\shadow-walk'
$journal = Join-Path $dir 'journal.jsonl'
$archive = Join-Path $dir 'journal.archive.jsonl'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# Mask obvious secrets before they ever hit disk — the journal is plaintext.
function Protect-Secret([string]$s) {
  if (-not $s) { return $s }
  $s = $s -replace '(?i)\b(authorization|api[_-]?key|apikey|token|secret|password|passwd|bearer)(["'']?\s*[:=]\s*["'']?)\S+', '$1$2<redacted>'
  $s = $s -replace '\b(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})\b', '<redacted>'
  $s = $s -replace '\b[A-Za-z0-9_\-]{40,}\b', '<redacted>'   # long opaque tokens
  return $s
}

# Read hook JSON from stdin (empty for 'show').
$stdin = ''
if ($Action -ne 'show' -and -not [Console]::IsInputRedirected) { $stdin = '' }
elseif ($Action -ne 'show') { $stdin = [Console]::In.ReadToEnd() }
$hook = $null
if ($stdin.Trim()) { try { $hook = $stdin | ConvertFrom-Json } catch { $hook = $null } }

function Get-AgentName($h) {
  foreach ($k in 'agent_type', 'agentType', 'subagent_type', 'subagentType', 'agent') {
    if ($h.PSObject.Properties.Name -contains $k -and $h.$k) { return [string]$h.$k }
  }
  return 'main'
}

# Compact one-line summary of a step, tuned per tool so the journal is readable at a glance.
function Get-StepSummary($h) {
  $tool = [string]$h.tool_name
  $ti   = $h.tool_input
  $s = ''
  switch -regex ($tool) {
    '^(Edit|Write|Read|NotebookEdit)$' { $s = [string]$ti.file_path; break }
    '^Bash$'        { $s = [string]$ti.command; break }
    '^Grep$'        { $s = "/$([string]$ti.pattern)/"; break }
    '^Glob$'        { $s = [string]$ti.pattern; break }
    '^(WebFetch|WebSearch)$' { $s = [string]($ti.url + $ti.query); break }
    '^Task|Agent$'  { $s = [string]$ti.description; break }
    default         { if ($ti) { $s = ($ti | ConvertTo-Json -Compress -Depth 4) } }
  }
  $s = Protect-Secret $s
  if ($s.Length -gt 140) { $s = $s.Substring(0, 137) + '...' }
  return ($s -replace '\s+', ' ').Trim()
}

if ($Action -eq 'record') {
  if (-not $hook) { exit 0 }   # nothing to record; never block the tool
  $tool = [string]$hook.tool_name
  $sum  = Get-StepSummary $hook
  if (-not $tool) {
    # No tool: capture user intent on UserPromptSubmit; skip other tool-less events (no noise).
    if ($hook.hook_event_name -eq 'UserPromptSubmit' -and $hook.prompt) {
      $tool = 'Prompt'
      $sum  = Protect-Secret ([string]$hook.prompt)
      if ($sum.Length -gt 140) { $sum = $sum.Substring(0, 137) + '...' }
      $sum = ($sum -replace '\s+', ' ').Trim()
    } else { exit 0 }
  }
  $entry = [ordered]@{
    ts    = (Get-Date).ToString('o')
    sid   = [string]$hook.session_id
    agent = Get-AgentName $hook
    event = [string]$hook.hook_event_name
    tool  = $tool
    sum   = $sum
    cwd   = [string]$hook.cwd
  }
  $line = ($entry | ConvertTo-Json -Compress -Depth 6)
  Add-Content -Path $journal -Value $line -Encoding UTF8
  exit 0
}

# ---- retrieve (associative / content-addressable recall) ----
# Tokenizer shared by query and documents: lowercase, alnum tokens >=3 chars, drop stopwords.
$stop = @{}
foreach ($w in 'the','and','for','you','your','with','this','that','from','have','are','was','not',
                'can','will','how','use','using','used','all','any','out','get','got','let','its',
                'has','had','but','yes','one','two','now','off','via','per','into','than','then',
                'what','when','where','which','who','why','into','over','also','been','make','made',
                'run','running','file','files') { $stop[$w] = $true }
function Get-Tokens([string]$t) {
  if (-not $t) { return @() }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($t.ToLowerInvariant(), '[a-z0-9_]{3,}')) {
    $w = $m.Value
    if (-not $stop.ContainsKey($w)) { $out.Add($w) }
  }
  return $out.ToArray()
}

if ($Action -eq 'retrieve') {
  if (-not $hook -or -not $hook.prompt) { exit 0 }
  if (-not (Test-Path $journal)) { exit 0 }
  $query  = [string]$hook.prompt
  $qterms = @(Get-Tokens $query | Select-Object -Unique)
  if ($qterms.Count -eq 0) { exit 0 }
  $qset = @{}; foreach ($q in $qterms) { $qset[$q] = $true }

  # Build documents from the journal tail (bounded cost). Skip the just-submitted prompt itself.
  $docs = New-Object System.Collections.Generic.List[object]
  foreach ($l in (Get-Content $journal -Tail $Tail -Encoding UTF8)) {
    if (-not $l.Trim()) { continue }
    try { $e = $l | ConvertFrom-Json } catch { continue }
    if ($e.tool -eq 'Prompt' -and $e.sum -and $query.StartsWith([string]$e.sum.TrimEnd('.'))) { continue }
    $toks = Get-Tokens ("{0} {1}" -f $e.tool, $e.sum)
    if ($toks.Count -eq 0) { continue }
    # only keep docs that share at least one query term (keeps scoring O(matches))
    $tf = @{}; $hit = $false
    foreach ($t in $toks) { if ($qset.ContainsKey($t)) { $tf[$t] = ($tf[$t] + 1); $hit = $true } }
    if ($hit) { $docs.Add([pscustomobject]@{ entry = $e; tf = $tf }) }
  }
  if ($docs.Count -eq 0) { exit 0 }

  # Document frequency per query term, then BM25-lite score (idf * saturated tf; no length norm).
  $N = $docs.Count
  $df = @{}
  foreach ($d in $docs) { foreach ($t in $d.tf.Keys) { $df[$t] = ($df[$t] + 1) } }
  $k1 = 1.2
  $scored = foreach ($d in $docs) {
    $score = 0.0
    foreach ($t in $d.tf.Keys) {
      $idf = [Math]::Log(1 + ($N - $df[$t] + 0.5) / ($df[$t] + 0.5))
      $f   = $d.tf[$t]
      $score += $idf * ($f * ($k1 + 1)) / ($f + $k1)
    }
    [pscustomobject]@{ entry = $d.entry; score = $score }
  }
  # Dedupe by summary (keep highest score), rank, take top-K.
  $best = $scored | Sort-Object score -Descending |
            Group-Object { "$($_.entry.tool)|$($_.entry.sum)" } |
            ForEach-Object { $_.Group[0] } |
            Sort-Object score -Descending | Select-Object -First $TopK
  $best = @($best | Where-Object { $_.score -gt 0 })
  if ($best.Count -eq 0) { exit 0 }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine('## Shadow-Walk associative recall (past steps related to your prompt)')
  [void]$sb.AppendLine("Matched by keyword overlap against $journal — read it for full detail.")
  foreach ($b in $best) {
    $e = $b.entry
    $t0 = $e.ts   # ConvertFrom-Json may hand back a [DateTime] or a string
    $day = if ($t0 -is [datetime]) { $t0.ToString('yyyy-MM-dd') } else { ([string]$t0).Substring(0, [Math]::Min(10, ([string]$t0).Length)) }
    [void]$sb.AppendLine(("- [{0}] {1}: {2}" -f $day, $e.tool, $e.sum))
  }
  $brief = $sb.ToString().TrimEnd()
  $out = @{ hookSpecificOutput = @{ hookEventName = [string]$hook.hook_event_name; additionalContext = $brief } }
  $out | ConvertTo-Json -Compress -Depth 6
  exit 0
}

# ---- recall / show ----
if (-not (Test-Path $journal)) {
  if ($Action -eq 'show') { Write-Host 'Shadow-Walk: journal is empty.'; exit 0 }
  exit 0
}

# Rotation (once per session at recall): if the journal grew past MaxLines, keep the freshest
# MaxLines and fold the rest into the archive. Bounds disk and keeps recall fast; nothing is lost.
$lineCount = (Get-Content $journal -Encoding UTF8 | Measure-Object -Line).Lines
if ($lineCount -gt $MaxLines) {
  $raw  = Get-Content $journal -Encoding UTF8
  $keep = $raw | Select-Object -Last $MaxLines
  $old  = $raw | Select-Object -SkipLast $MaxLines
  Add-Content -Path $archive -Value $old -Encoding UTF8
  Set-Content -Path $journal -Value $keep -Encoding UTF8
}

# Recall reads only the TAIL — cost is bounded no matter how large the journal is.
$all = @()
foreach ($l in (Get-Content $journal -Tail $Tail -Encoding UTF8)) {
  if (-not $l.Trim()) { continue }
  try { $all += ($l | ConvertFrom-Json) } catch { }
}
if (-not $all) { exit 0 }

$sid = if ($hook) { [string]$hook.session_id } else { '' }
$cur = if ($sid) { @($all | Where-Object { $_.sid -eq $sid }) } else { @() }
if (-not $cur) { $cur = @($all) }   # show / unknown session -> whole journal

# Working memory: the most recent steps, verbatim-compact.
$recent = @($cur | Select-Object -Last $Working)
$older  = @($cur | Select-Object -SkipLast $Working)

# Consolidated memory: roll up everything older so NO point is silently dropped.
$byTool = $older | Group-Object tool | Sort-Object Count -Descending
$files  = @($older | Where-Object { $_.tool -match '^(Edit|Write|NotebookEdit)$' -and $_.sum } |
             Select-Object -ExpandProperty sum -Unique)

# Long-term memory: one line per prior session.
$priorSids = @($all | Where-Object { $_.sid -ne $sid } | Select-Object -ExpandProperty sid -Unique)
$priorSids = @($priorSids | Select-Object -Last $Sessions)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('## Shadow-Walk recall (shared across all operating modes)')
[void]$sb.AppendLine("Journal: $journal — full detail on disk; read it directly for anything below.")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("### Working memory — last $($recent.Count) steps")
foreach ($e in $recent) {
  [void]$sb.AppendLine(("- [{0}] {1}: {2}" -f $e.agent, $e.tool, $e.sum))
}
if ($older.Count) {
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("### Consolidated — $($older.Count) earlier steps this session")
  [void]$sb.AppendLine("- by tool: " + (($byTool | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join ', '))
  if ($files.Count) { [void]$sb.AppendLine("- files touched: " + (($files | Select-Object -Last 12) -join ', ')) }
}
if ($priorSids.Count) {
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('### Long-term — prior sessions')
  foreach ($ps in $priorSids) {
    $ss = @($all | Where-Object { $_.sid -eq $ps })
    $tools = ($ss | Group-Object tool | Sort-Object Count -Descending | Select-Object -First 3 |
                ForEach-Object { "$($_.Name)×$($_.Count)" }) -join ', '
    $t0 = $ss[0].ts   # ConvertFrom-Json may hand back a [DateTime] or a string
    $day = if ($t0 -is [datetime]) { $t0.ToString('yyyy-MM-dd') } else { ([string]$t0).Substring(0, [Math]::Min(10, ([string]$t0).Length)) }
    [void]$sb.AppendLine(("- {0}: {1} steps ({2})" -f $day, $ss.Count, $tools))
  }
}
$brief = $sb.ToString().TrimEnd()

if ($Action -eq 'show') { Write-Host $brief; exit 0 }

# recall: emit as additionalContext so Claude Code wraps it in a system reminder.
$out = @{ hookSpecificOutput = @{ hookEventName = [string]$hook.hook_event_name; additionalContext = $brief } }
$out | ConvertTo-Json -Compress -Depth 6
exit 0
