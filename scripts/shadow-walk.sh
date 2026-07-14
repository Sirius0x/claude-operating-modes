#!/usr/bin/env bash
# Shadow-Walk (POSIX) — background lossless step-journal + human-brain-style recall for the
# operating modes. Mirrors shadow-walk.ps1. Requires: jq.
#
#   record   append one compact line per step to the shared journal. Wired to a PostToolUse hook
#            with suppressOutput:true -> ZERO model tokens; the model never sees it run.
#   recall   emit a compact recall brief (working/consolidated/long-term) as
#            hookSpecificOutput.additionalContext. Wired to SessionStart -> a fresh context, incl.
#            each isolated mode subagent, gets the shared history back. Cheap, not free.
#   retrieve content-addressable recall: score journal steps by keyword overlap with the CURRENT
#            prompt (BM25-lite, no extra LLM call) and inject the top-K RELEVANT ones. Wired to
#            UserPromptSubmit. An unrelated prompt scores nothing and injects nothing.
#   show     print the recall brief to the terminal (debug).
#
# Journal: ~/.claude/shadow-walk/journal.jsonl  (append-only, lossless; full detail always on disk)
set -euo pipefail
ACTION="${1:-}"; WORKING="${WORKING:-12}"; SESSIONS="${SESSIONS:-3}"
TAIL_N="${TAIL:-400}"; MAX_LINES="${MAXLINES:-4000}"; TOPK="${TOPK:-5}"
DIR="$HOME/.claude/shadow-walk"; JOURNAL="$DIR/journal.jsonl"; ARCHIVE="$DIR/journal.archive.jsonl"; mkdir -p "$DIR"

STDIN=""; if [ "$ACTION" != "show" ] && [ ! -t 0 ]; then STDIN="$(cat)"; fi

field() { printf '%s' "$STDIN" | jq -r "$1 // \"\"" 2>/dev/null || printf ''; }

# Mask obvious secrets before they hit disk (best-effort; GNU sed). Keyword=value pairs + long tokens.
redact() {
  sed -E 's/(authorization|api[_-]?key|apikey|token|secret|password|passwd|bearer)(["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?)[^[:space:]]+/\1\2<redacted>/Ig; s/[A-Za-z0-9_-]{40,}/<redacted>/g'
}

if [ "$ACTION" = "record" ]; then
  [ -z "$STDIN" ] && exit 0
  tool="$(field '.tool_name')"
  case "$tool" in
    Edit|Write|Read|NotebookEdit) sum="$(field '.tool_input.file_path')";;
    Bash)        sum="$(field '.tool_input.command')";;
    Grep)        sum="/$(field '.tool_input.pattern')/";;
    Glob)        sum="$(field '.tool_input.pattern')";;
    WebFetch|WebSearch) sum="$(field '.tool_input.url')$(field '.tool_input.query')";;
    Task|Agent)  sum="$(field '.tool_input.description')";;
    *)           sum="$(printf '%s' "$STDIN" | jq -c '.tool_input // {}' 2>/dev/null)";;
  esac
  if [ -z "$tool" ]; then
    # No tool: capture user intent on UserPromptSubmit; skip other tool-less events (no noise).
    if [ "$(field '.hook_event_name')" = "UserPromptSubmit" ]; then tool="Prompt"; sum="$(field '.prompt')"; else exit 0; fi
  fi
  sum="$(printf '%s' "$sum" | redact | tr '\n' ' ' | cut -c1-140)"
  agent="main"
  for k in agent_type agentType subagent_type subagentType agent; do
    v="$(field ".$k")"; [ -n "$v" ] && { agent="$v"; break; }
  done
  jq -nc --arg ts "$(date -Iseconds)" --arg sid "$(field '.session_id')" --arg agent "$agent" \
     --arg event "$(field '.hook_event_name')" --arg tool "$tool" --arg sum "$sum" \
     --arg cwd "$(field '.cwd')" \
     '{ts:$ts,sid:$sid,agent:$agent,event:$event,tool:$tool,sum:$sum,cwd:$cwd}' >> "$JOURNAL"
  exit 0
fi

# ---- retrieve (associative / content-addressable recall) ----
if [ "$ACTION" = "retrieve" ]; then
  [ -z "$STDIN" ] && exit 0
  [ -f "$JOURNAL" ] || exit 0
  query="$(field '.prompt')"
  [ -z "$query" ] && exit 0
  stop=" the and for you your with this that from have are was not can will how use using used all any out get got let its has had but yes one two now off via per into than then what when where which who why also been make made run running file files "
  qflat="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z0-9_]{3,}' \
           | awk -v s="$stop" '{ if (index(s, " " $0 " ")==0) print }' | sort -u | tr '\n' ' ')"
  [ -z "$(printf '%s' "$qflat" | tr -d ' ')" ] && exit 0
  # Documents: ts \t tool \t sum \t cwd from the journal tail. Score BM25-lite (query terms only)
  # in awk, rank by sort, dedupe by tool|sum, take top-K. Skips the just-submitted prompt itself.
  best="$(tail -n "$TAIL_N" "$JOURNAL" \
    | jq -r '[.ts, .tool, (.sum // "")] | @tsv' 2>/dev/null \
    | awk -F'\t' -v Q="$qflat" -v query="$query" '
        BEGIN{ nq=split(Q,qa," "); for(i=1;i<=nq;i++) qset[qa[i]]=1; k1=1.2 }
        {
          if($2=="Prompt"){ s=tolower($3); sub(/[. ]+$/,"",s); ql=tolower(query);
                            if(length(s)>=8 && index(ql, substr(s,1,40))==1) next }
          ts[NR]=$1; tool[NR]=$2; sum[NR]=$3;
          text=tolower($2" "$3); gsub(/[^a-z0-9_]+/, " ", text);
          c=split(text, toks, " "); delete seen;
          for(i=1;i<=c;i++){ w=toks[i]; if(length(w)<3) continue;
            if(w in qset){ tf[NR,w]++; hit[NR]=1; if(!seen[w]){df[w]++; seen[w]=1} } }
        }
        END{
          N=0; for(d=1;d<=NR;d++) if(hit[d]) N++; if(N==0) exit;
          for(d=1;d<=NR;d++){ if(!hit[d]) continue; score=0;
            for(w in qset){ f=tf[d,w]; if(f<=0) continue;
              idf=log(1+(N-df[w]+0.5)/(df[w]+0.5)); score+=idf*(f*(k1+1))/(f+k1) }
            printf "%.6f\t%s\t%s\t%s\n", score, substr(ts[d],1,10), tool[d], sum[d] }
        }' \
    | sort -t"$(printf '\t')" -k1,1 -rn \
    | awk -F'\t' '!seen[$3"|"$4]++' \
    | head -n "$TOPK")"
  [ -z "$best" ] && exit 0
  body="## Shadow-Walk associative recall (past steps related to your prompt)
Matched by keyword overlap against $JOURNAL — read it for full detail."
  while IFS="$(printf '\t')" read -r sc day tl sm; do
    [ -z "$day" ] && continue
    body="$body
- [$day] $tl: $sm"
  done <<< "$best"
  jq -nc --arg e "$(field '.hook_event_name')" --arg c "$body" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
  exit 0
fi

# ---- recall / show ----
[ -f "$JOURNAL" ] || { [ "$ACTION" = "show" ] && echo "Shadow-Walk: journal is empty."; exit 0; }
sid="$(field '.session_id')"

# Rotation (once per session): keep the freshest MAX_LINES, fold the rest into the archive.
lc="$(wc -l < "$JOURNAL" | tr -d ' ')"
if [ "$lc" -gt "$MAX_LINES" ]; then
  head -n "$(( lc - MAX_LINES ))" "$JOURNAL" >> "$ARCHIVE"
  tail -n "$MAX_LINES" "$JOURNAL" > "$JOURNAL.tmp" && mv "$JOURNAL.tmp" "$JOURNAL"
fi

# Read only the TAIL so recall cost is bounded regardless of journal size.
tailbuf="$(tail -n "$TAIL_N" "$JOURNAL")"
cur="$(printf '%s\n' "$tailbuf" | jq -c --arg s "$sid" 'select(.sid==$s)' 2>/dev/null || true)"
[ -z "$cur" ] && cur="$tailbuf"

total="$(printf '%s\n' "$cur" | grep -c . || true)"
recent="$(printf '%s\n' "$cur" | tail -n "$WORKING")"
older_n=$(( total > WORKING ? total - WORKING : 0 ))

brief="## Shadow-Walk recall (shared across all operating modes)
Journal: $JOURNAL — full detail on disk; read it directly for anything below.

### Working memory — last $(printf '%s\n' "$recent" | grep -c . || echo 0) steps"
while IFS= read -r l; do
  [ -z "$l" ] && continue
  brief="$brief
- [$(printf '%s' "$l" | jq -r '.agent')] $(printf '%s' "$l" | jq -r '.tool'): $(printf '%s' "$l" | jq -r '.sum')"
done <<< "$recent"

if [ "$older_n" -gt 0 ]; then
  older="$(printf '%s\n' "$cur" | head -n "$older_n")"
  bytool="$(printf '%s\n' "$older" | jq -r '.tool' | sort | uniq -c | sort -rn | awk '{printf "%s×%s, ",$2,$1}' | sed 's/, $//')"
  brief="$brief

### Consolidated — $older_n earlier steps this session
- by tool: $bytool"
fi

if [ "$ACTION" = "show" ]; then printf '%s\n' "$brief"; exit 0; fi
jq -nc --arg e "$(field '.hook_event_name')" --arg c "$brief" \
  '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
exit 0
