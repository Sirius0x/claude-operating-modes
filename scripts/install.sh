#!/usr/bin/env bash
# Cross-agent installer for Claude Operating Modes (POSIX / macOS / Linux).
# Mirrors install.ps1: deploys the payload and injects the AGENTS.md quick-ref into each agent's
# global instruction file inside an idempotent MANAGED BLOCK (never clobbers the user's own rules).
#
# Usage:
#   ./install.sh            # install to every agent whose home dir exists (Claude if none)
#   ./install.sh --all      # Claude Code AND Codex (create dirs as needed)
#   ./install.sh --claude   # Claude Code only
#   ./install.sh --codex    # Codex only
#   ./install.sh --dry-run  # show what would change; write nothing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skill"
BEGIN='<!-- BEGIN operating-modes (managed by claude-operating-modes installer — edits here are overwritten) -->'
END='<!-- END operating-modes -->'

CLAUDE=0; CODEX=0; ALL=0; DRY=0
for a in "$@"; do case "$a" in
  --claude) CLAUDE=1;; --codex) CODEX=1;; --all) ALL=1;; --dry-run) DRY=1;;
  *) echo "unknown arg: $a" >&2; exit 2;; esac; done

deploy_bundle() { # $1 = bundle dir
  local d="$1"
  if [ "$DRY" = 1 ]; then echo "  would copy SKILL.md, CRAFT.md, AGENTS.md, mode-theme.ps1 -> $d (pruning legacy alter-ego.ps1/install.ps1)"; return; fi
  mkdir -p "$d"
  rm -f "$d/alter-ego.ps1" "$d/install.ps1"   # prune files from older installs
  cp -f "$SKILL/SKILL.md" "$SKILL/CRAFT.md" "$ROOT/scripts/mode-theme.ps1" "$d/"
  sed "s#{{BUNDLE_DIR}}#$d#g" "$SKILL/AGENTS.md" > "$d/AGENTS.md"
  echo "  bundle -> $d"
}

block() { sed "s#{{BUNDLE_DIR}}#$1#g" "$SKILL/AGENTS.md"; }

inject() { # $1 = target file, $2 = bundle dir
  local file="$1" bundle="$2"
  if [ "$DRY" = 1 ]; then
    if   [ ! -f "$file" ];              then echo "  would create + add block: $file"
    elif grep -qF "$BEGIN" "$file";     then echo "  would update managed block in $file"
    else                                     echo "  would append block to $file"; fi
    return
  fi
  mkdir -p "$(dirname "$file")"
  local tmp; tmp="$(mktemp)"
  {
    if [ -f "$file" ] && grep -qF "$BEGIN" "$file"; then
      # replace existing block
      awk -v b="$BEGIN" -v e="$END" '
        $0==b {skip=1; print "@@BLOCK@@"; next}
        $0==e {skip=0; next}
        !skip {print}' "$file"
    elif [ -f "$file" ]; then
      cat "$file"; echo; echo "@@BLOCK@@"
    else
      echo "@@BLOCK@@"
    fi
  } > "$tmp.stage"
  # expand the @@BLOCK@@ placeholder into the real managed block
  {
    while IFS= read -r line; do
      if [ "$line" = "@@BLOCK@@" ]; then
        printf '%s\n' "$BEGIN"; block "$bundle"; printf '%s\n' "$END"
      else printf '%s\n' "$line"; fi
    done < "$tmp.stage"
  } > "$tmp"
  mv "$tmp" "$file"; rm -f "$tmp.stage"
  echo "  wrote managed block -> $file"
}

install_claude() {
  echo "claude-code:"
  local home="$HOME/.claude" bundle="$HOME/.claude/skills/operating-modes"
  deploy_bundle "$bundle"
  inject "$home/CLAUDE.md" "$bundle"
  if [ "$DRY" = 1 ]; then echo "  would install /mode command -> $home/commands/mode.md";
  else mkdir -p "$home/commands"; cp -f "$ROOT/agents/claude-code/commands/mode.md" "$home/commands/mode.md"; echo "  /mode command -> $home/commands/mode.md"; fi
}

install_codex() {
  echo "codex:"
  local home="$HOME/.codex" bundle="$HOME/.codex/operating-modes"
  deploy_bundle "$bundle"
  inject "$home/AGENTS.md" "$bundle"
}

do_claude=$(( CLAUDE || ALL )); do_codex=$(( CODEX || ALL ))
if [ "$do_claude" = 0 ] && [ "$do_codex" = 0 ]; then
  [ -d "$HOME/.claude" ] && do_claude=1
  [ -d "$HOME/.codex" ]  && do_codex=1
  [ "$do_claude" = 0 ] && [ "$do_codex" = 0 ] && do_claude=1
fi

[ "$DRY" = 1 ] && echo "== DRY RUN — no files will be written =="
[ "$do_claude" = 1 ] && install_claude
[ "$do_codex" = 1 ]  && install_codex
echo
echo "Done. Select a mode with 'op:<mode>' (any agent), '/mode <mode>' (Claude Code), or '<mode> mode'."
echo "For other agents, add skill/AGENTS.md to that agent's global rules file."
