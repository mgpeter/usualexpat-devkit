---
name: herdr
description: Operate the Herdr terminal agent-multiplexer — launch Claude agents in panes, read/message them, lay a herd out as an even grid, open it in a new tab, and coordinate. Load this BEFORE running any `herdr` command so you don't have to re-derive the CLI. Pairs with the `spin-up-herd` skill (planning + briefs).
---

# Herdr operations

Herdr is a Rust terminal agent-multiplexer (like tmux for AI agents). Each agent gets its own
real pane with its own `--cwd`; a coordinator can drive the others over a Unix socket. This skill
is the baked-in reference so you never need to re-read the docs.

## Golden rules (read first)

1. **Drive herdr from bash, NEVER from a python subprocess.** herdr needs a bash/MSYS console.
   Your `Bash` tool runs Git Bash — call `herdr` directly there and it works. Spawning `herdr`
   from `python subprocess` (even via `bash -lc`) throws `WinError 232 "pipe is being closed"`.
   That's why the helper is `herd.sh`, not a python script. Also tell the *user* to run herdr from
   `bash`, not the PowerShell pane (pwsh intermittently 232s too).
   - Mutating calls (`tab create`, `pane split`) also 232 *intermittently* even from bash — retry
     with a short backoff (`herd.sh`'s `h()` wrapper does this). Success = exit code 0; do NOT treat
     empty stdout as failure (split/run/rename return empty on success).
2. **A herd goes in its OWN tab.** Always create a new tab for a multi-agent herd (keeps the grid
   clean and navigable). If the user wants to reuse an existing tab, ask which one by label/id.
3. **Even grid layout.** When launching multiple agents, tile the panes into a near-square,
   balanced grid (equal widths; row counts balanced to within one). Use `scripts/herd.sh` — it does
   the math and the splits for you. Never leave agents as a lopsided stack.
4. **You cannot pass `--dangerously-skip-permissions` yourself** — the safety classifier blocks the
   assistant from spawning skip-permission agents. Either (a) launch without it and have the user
   approve the first prompt per pane (pick "allow for this project" to stop re-prompting), or
   (b) give the user the ready commands to run themselves with the flag for fully-unattended runs.
5. **Keep bootstrap prompts short.** Don't paste an 800-char brief into `pane run`/`agent start`
   (it can wedge the pipe). Write each brief to a file and launch with a one-liner:
   `claude "Read <brief-file> and carry out the task it describes."`

## The mechanical helper — `scripts/herd.sh` (bash)

Prefer this over hand-rolling splits. Run it from Git Bash:

```bash
H="$HOME/.claude/skills/herdr/scripts/herd.sh"
bash "$H" grid-plan 5              # preview the grid (cols + balanced row counts)
bash "$H" spinup herd.json         # new tab + even grid + launch each agent's brief
bash "$H" status w4:t3             # agent statuses in a tab
bash "$H" read <pane_id> 150       # read a pane
bash "$H" collect herd.json        # print the findings file
```

`spinup` creates a new tab (or reuses `reuse_tab_id`), builds an even grid of N panes (verified even:
N=4→2×2, N=5→3 cols with rows balanced [2,2,1]), renames each pane, and launches each agent with a
short "read your brief" bootstrap. Config schema is at the top of `herd.sh`. Minimal example:

```json
{
  "tab_label": "auth-investigation",
  "findings_file": "D:/repos/tk/_work/findings.md",
  "skip_permissions": false,
  "agents": [
    {"name": "textures", "cwd": "D:\\repos\\tk\\mpb-textures", "brief_file": "D:/repos/tk/_work/brief-textures.md"},
    {"name": "gem",      "cwd": "D:\\repos\\tk\\mpb-gem",      "brief_file": "D:/repos/tk/_work/brief-gem.md"}
  ]
}
```

## CLI cheat-sheet (herdr 0.7.x)

Session / layout:
- `herdr status` · `herdr status server` — health. `herdr workspace list` / `herdr tab list` / `herdr pane list [--workspace <ws>]` — inventory (JSON).
- `herdr tab create --workspace <ws> --label <t> --no-focus` — **new tab**. Returns
  `result.tab.tab_id` + `result.root_pane.pane_id`. **Pass `--workspace`** or it may land in the
  wrong workspace. `herdr tab focus|rename|close <tab_id>`.
- `herdr pane split <pane> --direction right|down --ratio R [--no-focus]` — split. **`--ratio` is the
  fraction kept by the ORIGINAL (left/top) pane**; the new pane gets `(1-R)`. The split response
  new pane id is returned at `result.pane.pane_id` (herd.sh reads it there — deterministic).
- `herdr pane layout --pane <p>` — geometry (`rect{x,y,width,height}`) for evenness checks.
- `herdr pane rename <pane> <label>` · `herdr pane close <pane>` · `herdr pane focus --direction ...`.

Agents:
- `herdr agent start <name> [--cwd PATH] [--workspace ID] [--tab ID] [--split right|down] -- <argv...>`
  — creates a NEW pane and execs `<argv>` directly (no shell). Good for a single agent; for a grid,
  prefer building panes first (herd.sh) then `pane run`.
- `herdr agent list` — all agents + `agent_status` (idle | working | blocked | done | unknown).
- `herdr agent read <target> [--source visible|recent|recent-unwrapped] [--lines N]` — read output.
- `herdr agent send <target> <text>` — type literal text into a running agent (no Enter).
- `herdr pane send-keys <pane> enter` / `... escape` / `... ctrl+c` — key events (Enter to submit,
  Esc/Ctrl+C to cancel a prompt or interrupt).
- `herdr pane run <pane> <command>` — send `<command>`+Enter to the pane's shell (pwsh on Windows).
  Use this to start `claude` in a pre-built grid pane. Keep `<command>` free of `$`/backticks.
- `herdr wait agent-status <pane> --status <idle|working|blocked|done|unknown> [--timeout MS]`,
  `herdr agent wait <target> --status ...`, `herdr wait output <pane> --match <text>` — blocking waits.

Socket API (if scripting raw, e.g. `herdr api ...`): `pane.split`, `pane.run`, `pane.read`,
`pane.send_text`, `pane.send_keys`, `events.subscribe {pane.agent_status_changed}`.

## Launching a Claude investigator/worker into a pane

Read-only bootstrap (short prompt → agent reads its full brief from a file):
```bash
herdr pane run <pane> 'claude "Read D:/repos/tk/_work/brief-textures.md and carry out the task it describes. This is read-only: do not modify code. Append findings to D:/repos/tk/_work/findings.md under a ## textures heading."'
```
- Fully unattended (user runs it): add `--dangerously-skip-permissions` after `claude`.
- Nudging a stalled/idle agent: `herdr agent send <pane> "Proceed and finish the task."` then
  `herdr pane send-keys <pane> enter`.
- Reclaiming a wedged claude pane: `herdr pane send-keys <pane> escape` then `... ctrl+c ctrl+c`, or
  `herdr pane close <pane>` and recreate.

## Coordinator pattern

1. Spin up the herd (herd.sh) in a new tab; confirm each pane got its brief (`agent read`).
2. Poll `herdr agent list` (or `bash herd.sh status <t>`); a pane in `blocked` needs the user to
   approve a prompt — surface which one. Nudge any pane stuck `idle` right after reading its brief.
3. Have each agent append to ONE shared findings file (durable) AND read panes live.
4. When all `done`, dedup, cross-examine conflicts (`agent send` a rival's finding to challenge),
   and write a single synthesis into the findings file.

## Gotchas
- `herdr tab create` without `--workspace` lands in a default (often the first) workspace.
- Agents launched in "manual mode" prompt on each read/Bash until the user picks "allow for project".
- `tab create` and `pane split` inherit the default pane shell (pwsh on Windows) — that's why
  bootstrap commands must be pwsh-safe.
