<p align="center">
  <img src="assets/social-preview.png" alt="Claude Operating Modes — nine character-driven cognitive modes for any AI agent" width="860">
</p>

# Claude Operating Modes

[![Stars](https://img.shields.io/github/stars/Sirius0x/claude-operating-modes?style=social)](https://github.com/Sirius0x/claude-operating-modes/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Shell](https://img.shields.io/badge/shell-PowerShell%20%C2%B7%20Bash-5391FE)
![Works with](https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20any-8A2BE2)
![Modes](https://img.shields.io/badge/modes-9-orange)

**One line switches your AI's whole posture.** `op:batman` → recon before acting · `op:joker` →
red-team its own plan · `op:fightclub` → drop the hedging and commit. Nine character-driven
**cognitive modes** — portable across Claude Code, Codex, or any agent — each distilled to one
mental move, a trigger, and the failure it *kills*. Domain-general: code, writing, research,
strategy, decisions. **Not cosplay.**

> Ego is fuel; modes are the steering.

## The nine modes

| Mode | Move | Use when | Kills |
|---|---|---|---|
| 🦇 Batman | **Prepare** — intel & contingency before acting | starting, high-stakes | acting blind, corner-cutting |
| ⚙️ Ironman | **Build** — prototype fast, automate, own it | making/fixing | paralysis, manual toil |
| 🎯 John Wick | **Finish** — one objective to completion | executing | half-done work, scatter |
| ⚖️ Thanos | **Prioritize** — cut ruthlessly to the essential | overloaded, trade-offs | bloat, indecision |
| 🏴‍☠️ Jack Sparrow | **Improvise** — lateral angle when blocked | stuck, out-resourced | rigid thinking |
| 🃏 Joker | **Challenge** — red-team assumptions | before committing | groupthink, false confidence |
| ♟️ Thomas Shelby | **Strategize** — sequence & anticipate the counter | multi-step, adversarial | reactive/emotional moves |
| 🔮 Dr Strange | **Foresee** — branch futures, pick best EV, keep plan B | high uncertainty | tunnel vision, no fallback |
| 🌗 Fight Club | **Unleash** — drop hesitation, commit boldly (+theme flip) | over-hedging, timidity | timidity, analysis-paralysis |

Full character profiles — **Core traits** (with `[Certain]`/`[Likely]`/`[Uncertain]` confidence
tags), *In plain terms*, discipline, and cross-domain examples — live in [`skill/SKILL.md`](skill/SKILL.md).

## The craft beneath the modes
The modes are *postures* you step into. [`skill/CRAFT.md`](skill/CRAFT.md) is the *reasoning craft*
you practice inside every one of them — a senior-to-junior operating manual covering how to read the
real request, decompose into checkable pieces, place effort where the risk lives, verify by
re-deriving (not re-reading), label known vs guessed, red-team your own conclusion, and lead with the
answer. It closes with the mistakes that look like competence and a five-question self-test to run on
every answer. Read it once end to end; keep it at your elbow.

## Three laws (override every mode)
- **Accuracy** — verify before claiming; confirmed > plausible; never overstate.
- **Economy** — the minimum that solves it; don't re-derive; be terse.
- **Goal** — every action traces to the real objective; if it doesn't serve it, cut it.

## Ethics anchor (non-negotiable)
Villains and alter-egos are invoked **only** at their high-conscious reading — Joker = red-team
assumptions, Thanos = ruthless prioritization, Fight Club = controlled boldness — **never** harm,
chaos, or recklessness. No mode overrides honesty, safety, or the user's real interest.

## Works with any agent
Three portable files in [`skill/`](skill/) do the whole job, and the installer wires them into
whatever AI you use:

| File | Job | Deployed as |
|---|---|---|
| `AGENTS.md` | always-loaded quick-ref + mode triggers + laws + craft principles | Claude Code `~/.claude/CLAUDE.md` · Codex `~/.codex/AGENTS.md` |
| `SKILL.md` | full mode profiles (the deep reference) | `<agent>/…/operating-modes/SKILL.md` |
| `CRAFT.md` | the reasoning manual beneath the modes | `<agent>/…/operating-modes/CRAFT.md` |

The installer injects `AGENTS.md` into each agent's global instruction file inside a **managed
block** (`<!-- BEGIN/END operating-modes -->`), so re-running only updates that block and never
touches your own instructions. For an agent it doesn't know, paste `skill/AGENTS.md` into that
agent's global rules file — that's all it takes.

## Selecting a mode
Pick a mode inline with any of these — every trigger is equivalent:
```
op:batman            # universal, safe in every agent
/mode joker          # Claude Code slash command (installed to ~/.claude/commands/mode.md)
batman mode          # natural language
```
`op:off` clears it · `op:modes` lists the nine · triggers stack (`op:batman op:joker`).

## Install
```powershell
.\scripts\install.ps1            # install to every agent whose home dir exists (Claude if none)
.\scripts\install.ps1 -All       # Claude Code AND Codex
.\scripts\install.ps1 -Claude    # one agent only  (also: -Codex)
.\scripts\install.ps1 -DryRun    # preview every change; write nothing
```
```bash
./scripts/install.sh [--all|--claude|--codex] [--dry-run]   # macOS / Linux
```

## Live terminal themes (one per mode)
Every mode has its own color scheme, so the active posture is visible at a glance. Two scopes:
```powershell
# global — edits Windows Terminal settings.json, applies to ALL tabs (persistent)
.\scripts\mode-theme.ps1 batman
.\scripts\mode-theme.ps1 off              # revert (restores your exact original settings.json)

# per-tab — recolors ONLY this terminal via ANSI OSC; other tabs stay put (per-session identity)
.\scripts\mode-theme.ps1 fight-club -Session
.\scripts\mode-theme.ps1 off -Session

.\scripts\mode-theme.ps1 list             # show all nine palettes
```
Use **`-Session`** when several terminals are open and you want each one to carry its own mode
colour — it writes ANSI escape codes to the current console only (works in Windows Terminal, VS
Code, most xterm-likes), so run it *in* the terminal you want to theme. The global form overrides
every profile (a per-profile pin can't block it) and keeps a one-time backup for clean revert.
Palettes: Batman graphite/steel-blue · Ironman red & gold · John Wick steel & blood-red · Thanos
violet & gold · Sparrow sea-teal & gold · Joker purple & acid-green · Shelby amber & smoke · Strange
cyan & gold · Fight Club crimson.

### In-character voice (agentic)
Invoke a mode and the agent **opens with that mode's iconic line** — `op:fight-club` → *"Welcome to
Fight Club."*, `op:joker` → *"Why so serious?"* — names the mode, then gets to work. It's purely
instruction-driven (no code): the entry line comes from each mode's `Voice` cue in `SKILL.md`, and
any further in-character asides are improvised. Flavor never displaces the answer — for real
deliverables the agent still leads with the answer (`CRAFT.md` §0.5, "tone is the mask; craft is
the skull").

### Roadmap / fine-tune TODO
- [x] **Cross-agent install** — portable `AGENTS.md` payload + managed-block installer for Claude
      Code and Codex; any other agent works by pasting `skill/AGENTS.md`.
- [x] **`op:` / `/mode` invocation** — inline mode selection in every agent.
- [ ] **Multi-host theming** — support VS Code / Cursor / Antigravity integrated terminals and
      raw conhost (currently Windows-Terminal-only). Likely via ANSI OSC sequences + oh-my-posh
      prompt-theme swap so the signal shows in *any* host.
- [ ] Per-mode prompt glyph (oh-my-posh segment showing the active mode).
- [ ] Native skill manifests for more agents (Cursor `.mdc`, Windsurf rules).
- [ ] Optional 10th mode slot (one free).

## License
MIT — see [LICENSE](LICENSE).
