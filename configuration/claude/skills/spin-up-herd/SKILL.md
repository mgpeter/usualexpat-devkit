---
name: spin-up-herd
description: Plan and launch a multi-agent Herdr "herd" — analyze the work, ask the user scoping questions, write a focused brief per agent, lay them out in an EVEN grid in a NEW Herdr tab, then coordinate and synthesize. Use when the user wants to fan out Claude agents across repos or sub-tasks (investigations, reviews, migrations, research). Depends on the `herdr` skill for the mechanics.
---

# Spin up a herd

End-to-end playbook: turn a fuzzy "investigate/review/do X across N things" request into a laid-out,
briefed, coordinated team of Claude agents in Herdr. Load the **`herdr`** skill too — it has the CLI,
grid math, tab handling, and `scripts/herd.sh` this playbook drives.

## Step 1 — Analyze the work and scope it (ask, don't assume)

Decompose the request into independent units of work (one agent per unit). Use **AskUserQuestion**
to settle anything you can't infer. Cover:

- **Targets / partition.** Which repos, dirs, services, or sub-topics? One agent each. Confirm the
  exact paths. (For a genuinely unknown scope, scout first — list repos/files — then partition.)
- **Objective & depth.** What's the deliverable per agent (investigate a bug, review a diff, map a
  subsystem, port a pattern)? Read-only or may they change code?
- **Tab.** Default: a **new tab** named after the task. Only if the user wants to reuse an existing
  tab, ask for its label/id (`herdr tab list` to show options).
- **Permission posture.** Unattended (`--dangerously-skip-permissions`, which the *user* must launch,
  since the classifier blocks the assistant) vs supervised (user approves the first prompt per pane).
- **Adversarial framing.** For investigations/reviews, assign each agent a distinct hypothesis/lens
  and tell it to actively DISPROVE its own assignment — this is what makes a herd better than one agent.

Right-size it: 3–6 agents is the sweet spot. More units → group them.

## Step 2 — Write a brief per agent + a shared findings file

Create a work dir (e.g. a neutral folder outside the target repos, like
`D:\repos\tk\_<task>-investigation\`). Write one `brief-<name>.md` per agent and one `findings.md`.

Brief template (keep each ~30-60 lines; the agent reads the file, so no quoting limits):

```markdown
# Investigator brief — <name>

<1-2 sentences: the shared goal + why the team exists>. <The key framing fact(s) already established,
so agents don't re-derive them.>

**Rules:** Read-only — do not modify code (or: you may change code in <scope>). Cite file:line
evidence. Actively try to DISPROVE <this agent's hypothesis/that this target is the cause>.

## Your target: <repo/dir/topic>
1. <specific question 1 — with the exact entry-point files/symbols to start from>
2. <specific question 2 — the hypothesis this agent owns>
3. <what to report back>

Use subagents if that speeds up the sweep.

## Deliverable
Append a `## <name>` section to <findings-file> with file:line evidence + a confidence rating,
then summarize in your final message.
```

Give every brief the **same shared context** (so agents agree on the premise) but a **different
target + hypothesis**. Point agents that share a dependency at each other ("hand SDK questions to
the <core> agent").

## Step 3 — Assemble the config and spin up (new tab, even grid)

Build `herd.json` (schema at the top of `herdr/scripts/herd.sh`) and launch from **Git Bash**:

```bash
H="$HOME/.claude/skills/herdr/scripts/herd.sh"
bash "$H" grid-plan <N>            # sanity-check the grid layout
bash "$H" spinup herd.json        # new tab + even grid + launch each brief
```

`spinup` creates a new tab (or reuses `reuse_tab_id`), tiles N panes into an even grid, renames each
pane to the agent name, and launches each with a short "read your brief" bootstrap. It prints a
legend (agent → pane) and the coordinate commands.

- If the user chose unattended: set `"skip_permissions": true` **and give them the exact spinup
  command to run themselves** (the classifier blocks you from launching skip-permission agents).
- If supervised: launch it yourself; then tell the user which panes are `blocked` so they approve
  (advise picking "allow for this project" to stop re-prompting).

## Step 4 — Coordinate

Use `TaskCreate` to track one task per agent + a synthesis task. Then:

- Poll `bash herd.sh status <tab>` (or `herdr agent list`). Report progress.
- A pane stuck `blocked` → user approval needed; a pane `idle` right after reading its brief → nudge
  it: `herdr agent send <pane> "Proceed and finish."` + `herdr pane send-keys <pane> enter`.
- For long runs, monitor in the background (a bash loop watching the findings file's section count),
  so you're re-invoked when they finish rather than polling blindly.

## Step 5 — Synthesize

When all agents are `done`: read the findings file, **dedup** overlapping findings, reconcile any
conflicts (optionally `herdr agent send` one agent a rival's claim to challenge it), rank by
confidence, and write a single **coordinator synthesis** at the bottom of the findings file — root
cause / recommendation / next steps + a cheap way to confirm. Relay the headline to the user.

## Reuse
This produces a reusable pattern: `_<task>/` work dir with briefs + findings, a `herd.json`, and a
tab of agents. Re-run `spinup` to relaunch, `collect` to reprint findings.
