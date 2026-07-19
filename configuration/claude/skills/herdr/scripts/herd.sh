#!/usr/bin/env bash
# herd.sh — deterministic Herdr orchestration (BASH — do NOT reimplement in python).
#
# WHY BASH: the herdr CLI needs a bash/MSYS console. Spawning `herdr` from python
# subprocess throws `WinError 232 "The pipe is being closed"` on Windows; the same command
# from bash works. So all herdr calls live here; python is used ONLY as a stdin JSON parser.
#
# Run from Git Bash / WSL (not the PowerShell pane).
#
# Subcommands:
#   herd.sh grid-plan <N>
#   herd.sh spinup <config.json>
#   herd.sh status [<tab_id>]
#   herd.sh read <pane_id> [<lines>]
#   herd.sh collect <config.json>
set -uo pipefail
PY="$(command -v python3 || command -v python)"

# retry wrapper — mutating herdr calls (tab create / split) intermittently 232; back off & retry.
h() {
  local out rc err; err="$(mktemp)"
  for a in 1 2 3 4 5 6; do
    out="$(herdr "$@" 2>"$err")"; rc=$?
    # success = exit code 0. Many mutating calls (split/run/rename) return EMPTY stdout on
    # success, so do NOT require non-empty output (that caused duplicate splits).
    if [ $rc -eq 0 ]; then rm -f "$err"; printf '%s' "$out"; return 0; fi
    if grep -qiE '232|pipe is being closed|brokenpipe' "$err"; then sleep "0.$((a*4))"; continue; fi
    break
  done
  echo "herdr $* failed: $(cat "$err")" >&2; rm -f "$err"; return 1
}

jq_field() { "$PY" -c "import sys,json;print(json.load(sys.stdin)$1)"; }  # e.g. jq_field "['result']['tab']['tab_id']"

pane_ids() {  # pane ids in tab $1 (one per line)
  h pane list --workspace "$WS" | "$PY" -c "import sys,json
d=json.load(sys.stdin)['result']['panes']
print('\n'.join(p['pane_id'] for p in d if p.get('tab_id')=='$1'))"
}

split_new() {  # split pane $1 dir $2 ratio $3 -> echo new pane id (from split response)
  h pane split "$1" --direction "$2" --ratio "$3" --no-focus | jq_field "['result']['pane']['pane_id']"
}

grid_cols()   { "$PY" -c "import math,sys;print(math.ceil(math.sqrt(int(sys.argv[1]))))" "$1"; }
grid_counts() { "$PY" -c "import math,sys
n=int(sys.argv[1]);c=math.ceil(math.sqrt(n));b,e=divmod(n,c)
print(' '.join(str(b+(1 if i<e else 0)) for i in range(c)))" "$1"; }
ratio() { "$PY" -c "print(f'{1/($1-$2+1):.4f}')"; }  # ratio(total,k): fraction kept by first pane

build_grid() {  # build_grid <root_pane> <n> -> echo pane ids (column-major), sets global GRID
  local root="$1" n="$2" cols cc curr k c top rc j newp
  cols="$(grid_cols "$n")"; cc=($(grid_counts "$n"))
  local col_tops=("$root"); curr="$root"
  for ((k=1;k<cols;k++)); do
    newp="$(split_new "$curr" right "$(ratio "$cols" "$k")")"; [ -z "$newp" ] && { echo "col split failed" >&2; return 1; }
    col_tops+=("$newp"); curr="$newp"
  done
  GRID=()
  for ((c=0;c<cols;c++)); do
    top="${col_tops[$c]}"; rc="${cc[$c]}"; GRID+=("$top"); curr="$top"
    for ((j=1;j<rc;j++)); do
      newp="$(split_new "$curr" down "$(ratio "$rc" "$j")")"; [ -z "$newp" ] && { echo "row split failed" >&2; return 1; }
      GRID+=("$newp"); curr="$newp"
    done
  done
  echo "cols=$cols col_counts=${cc[*]}" >&2
}

spinup() {
  local cfg="$1"
  WS="$("$PY" -c "import json,os;c=json.load(open('$cfg'));print(c.get('workspace') or os.environ.get('HERDR_WORKSPACE_ID',''))")"
  [ -z "$WS" ] && { echo "no workspace (config.workspace or \$HERDR_WORKSPACE_ID)"; exit 1; }
  local n reuse label findings skip readonly
  n="$("$PY" -c "import json;print(len(json.load(open('$cfg'))['agents']))")"
  reuse="$("$PY" -c "import json;print(json.load(open('$cfg')).get('reuse_tab_id') or '')")"
  label="$("$PY" -c "import json;print(json.load(open('$cfg')).get('tab_label','herd'))")"
  findings="$("$PY" -c "import json;print(json.load(open('$cfg')).get('findings_file') or '')")"
  skip="$("$PY" -c "import json;print('1' if json.load(open('$cfg')).get('skip_permissions') else '')")"
  readonly="$("$PY" -c "import json;print('' if json.load(open('$cfg')).get('readonly',True) is False else '1')")"

  local root
  if [ -n "$reuse" ]; then
    TAB="$reuse"; root="$(pane_ids "$TAB" | head -1)"
    [ -z "$root" ] && { echo "reuse_tab_id $TAB has no panes"; exit 1; }
    echo "Reusing tab $TAB (root $root)."
  else
    local res; res="$(h tab create --workspace "$WS" --label "$label" --no-focus)" || exit 1
    TAB="$(printf '%s' "$res" | jq_field "['result']['tab']['tab_id']")"
    root="$(printf '%s' "$res" | jq_field "['result']['root_pane']['pane_id']")"
    echo "Created tab $TAB (label '$label')."
  fi

  build_grid "$root" "$n" || exit 1

  echo; echo "Launched agents:"; printf '  %-16s %-8s %s\n' agent pane cwd
  local i=0 name cwd brief flags ro fnote prompt launch cmd
  while IFS=$'\t' read -r name cwd brief; do
    flags=""; [ -n "$skip" ] && flags="--dangerously-skip-permissions "
    if [ -n "$brief" ]; then
      ro=""; [ -n "$readonly" ] && ro=" This is a READ-ONLY investigation: do not modify code."
      fnote=""; [ -n "$findings" ] && fnote=" When done, append your findings to $findings under a '## $name' heading, then summarize."
      prompt="Read $brief and carry out the task it describes exactly.${ro}${fnote}"
      launch="claude ${flags}\"$prompt\""
    else
      launch="claude ${flags}"   # bare agent - no brief, waiting for you to direct it
    fi
    # cd the pane into the agent's repo first (pwsh), so claude loads the right repo context.
    cmd="cd '$cwd'; $launch"
    h pane rename "${GRID[$i]}" "$name" >/dev/null
    h pane run "${GRID[$i]}" "$cmd" >/dev/null
    printf '  %-16s %-8s %s\n' "$name" "${GRID[$i]}" "$cwd"
    i=$((i+1))
  done < <("$PY" -c "import json
for a in json.load(open('$cfg'))['agents']:
    print(a['name']+'\t'+a['cwd']+'\t'+a.get('brief_file',''))" | tr -d '\r')

  echo; echo "Tab: $TAB   Findings: ${findings:-(none)}"
  echo "Coordinate:  bash herd.sh status $TAB   |   herdr agent read <pane> --source recent --lines 150"
  [ -z "$skip" ] && echo "Agents need first-prompt approval per pane (pick 'allow for this project')."
}

case "${1:-}" in
  grid-plan) echo "n=$2 -> $(grid_cols "$2") cols; balanced columns [$(grid_counts "$2")]";;
  spinup)    spinup "$2";;
  status)    h agent list | "$PY" -c "import sys,json
tab='${2:-}'
for a in json.load(sys.stdin)['result']['agents']:
    if not tab or a.get('tab_id')==tab: print(f\"{a.get('pane_id',''):8} {a.get('name','?'):16} {a.get('agent_status','')}\")";;
  read)      herdr agent read "$2" --source recent --lines "${3:-150}" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['result']['read']['text'])";;
  collect)   f="$("$PY" -c "import json;print(json.load(open('$2')).get('findings_file') or '')")"; [ -f "$f" ] && cat "$f" || echo "no findings file: $f";;
  *) echo "usage: herd.sh {grid-plan N|spinup cfg|status [tab]|read pane [lines]|collect cfg}";;
esac
