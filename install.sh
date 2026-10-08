#!/usr/bin/env bash
#
# Workflow harness installer.
#
# It does four mechanical things and then gets out of the way: checks this
# computer has what the hooks need, asks whether the folder it runs from is the
# workspace, one of its projects or neither, shows the folders it will set up and lets
# the user change them, downloads the harness there, and starts the orchestrator.
#
# Naming the workspace folder is the one setup task that has to happen while
# Claude Code is closed, because the agent sessions live inside it.
# This script is that moment. It places the folders on disk and nothing else:
# every {{placeholder}} is left unfilled, so the orchestrator still runs
# FIRST_START.md from step 1 and still records the names in the CLAUDE.md files.
#
# It never asks for or writes a key, a token or a password. Trello, git, the
# MCP server, the projects and their stacks are all settled in the
# conversation with the orchestrator, after this script hands off.
#
# Run it from a file, not from a pipe:
#
#   curl -fsSL https://raw.githubusercontent.com/jaymeany/workflow-harness/main/install.sh -o harness-install.sh
#   bash harness-install.sh
#
set -euo pipefail

REPO="jaymeany/workflow-harness"
BRANCH="main"
WORKSPACE_SRC="workspace-name"
MIN_CLAUDE="2.1.224"

# ------------------------------------------------------------------- styling
# Color only on a terminal, and never when NO_COLOR is set (no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  B=$'\033[1m' D=$'\033[2m' C=$'\033[36m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'
else
  B="" D="" C="" G="" Y="" R="" N=""
fi

TOTAL_STEPS=4

say()  { printf '%s\n' "$*" > /dev/tty; }
dim()  { printf '%s%s%s\n' "$D" "$*" "$N" > /dev/tty; }
ok()   { printf '  %s✓%s %-13s %s\n' "$G" "$N" "$1" "$2" > /dev/tty; }
warn() { printf '\n  %s!%s %s\n' "$Y" "$N" "$1" > /dev/tty; shift; for l in "$@"; do say "    $l"; done; }
die()  { printf '\n  %s✗%s %s\n' "$R" "$N" "$1" >&2; shift; for l in "$@"; do printf '    %s\n' "$l" >&2; done; exit 1; }

# A numbered section header with a rule to the right.
section() {
  local n="$1" title="$2" label rule
  label="$n of $TOTAL_STEPS  $title"
  rule="$(printf '%*s' $(( 60 - ${#label} )) '' | sed 's/ /─/g')"
  printf '\n%s%s%s of %s%s  %s%s%s %s%s%s\n\n' "$C" "$B" "$n" "$TOTAL_STEPS" "$N" "$B" "$title" "$N" "$D" "$rule" "$N" > /dev/tty
}

# The start of a question line.
ask() { printf '\n  %s?%s %s%s%s ' "$C" "$N" "$B" "$1" "$N" > /dev/tty; }

# One option in a list: key, then what it does.
option() { printf '      %s%s%s  %s\n' "$C$B" "$1" "$N" "$2" > /dev/tty; }

# ---------------------------------------------------------------- pipe guard
# A piped script shares stdin with the pipe, so the questions below would read
# the script's own text and Claude Code would have no terminal to start in.
if [ ! -t 0 ]; then
  die "Run this from a file, not a pipe:" "" \
    "curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/install.sh -o harness-install.sh" \
    "bash harness-install.sh"
fi

say ""
printf '  %sWorkflow harness installer%s\n' "$B" "$N" > /dev/tty
dim "  github.com/$REPO"

# ----------------------------------------------------------------- preflight
section 1 "Checking this computer"

os="$(uname -s)"
case "$os" in
  Darwin) ok "system" "Mac" ;;
  Linux)  ok "system" "Linux" ;;
  *)      die "This is $os. The hooks are bash scripts and need a bash shell." \
            "On Windows, install WSL and run this script inside it, where everything works as on Linux." ;;
esac

missing=""
for tool in git curl jq pgrep; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] || die "Missing:$missing" "" \
  "The hooks need these. A hook that cannot find its tool allows everything without" \
  "checking, so install them before going on." \
  "  Mac:   brew install${missing}" \
  "  Linux: use your package manager"
ok "tools" "git, curl, jq, pgrep"

command -v claude >/dev/null 2>&1 || die "Claude Code is not installed, or is not on PATH." \
  "Install it, open a new terminal, and run this script again."

claude_version="$(claude --version 2>/dev/null | awk '{print $1}')"
[ -n "$claude_version" ] || die "Could not read the Claude Code version from 'claude --version'."
oldest="$(printf '%s\n%s\n' "$MIN_CLAUDE" "$claude_version" | sort -V | head -n1)"
if [ "$oldest" != "$MIN_CLAUDE" ] && [ "$claude_version" != "$MIN_CLAUDE" ]; then
  die "Claude Code $claude_version is older than $MIN_CLAUDE." \
    "The agents reach each other with ListAgents and SendMessage, which need $MIN_CLAUDE or later." \
    "Run 'claude update', then run this script again."
fi
ok "Claude Code" "$claude_version"

# --------------------------------------------------------------------- names
# Naming the workspace folder is the one setup task that has to happen while
# Claude Code is closed, because the orchestrator's session lives inside it.
section 2 "Where the harness goes"

ask_name() {
  local prompt="$1" default="$2" answer=""
  while true; do
    ask "$prompt"
    printf '%s[%s]%s ' "$D" "$default" "$N" > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    [ -n "$answer" ] || answer="$default"
    if printf '%s' "$answer" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]*$'; then
      printf '%s' "$answer"
      return 0
    fi
    warn "Use letters, digits, hyphens and underscores. No spaces or slashes."
  done
}

HERE="$(pwd -P)"
HOME_DIR="$(cd "$HOME" && pwd -P)"
[ -w "$HERE" ] || die "Cannot write to $HERE." "Change to a folder you own, then run this script again."

# One line of a tree: prefix, folder name, note, and an optional marker.
# printf pads by bytes and the box-drawing characters are three bytes each,
# so pad by hand from a plain copy.
row() {
  local prefix="$1" name="$2" note="$3" mark="${4:-}" plain pad
  plain="${prefix//└──/xxx}"
  plain="${plain//├──/xxx}$name"
  pad=$(( 34 - ${#plain} ))
  [ "$pad" -ge 1 ] || pad=1
  printf '    %s%s%s%s%s%s%*s%s%s%s' "$D" "$prefix" "$N" "$B" "$name" "$N" "$pad" "" "$D" "$note" "$N" > /dev/tty
  [ -z "$mark" ] || printf '  %s◀ %s%s' "$Y" "$mark" "$N" > /dev/tty
  printf '\n' > /dev/tty
}

# The hooks find the workspace three levels up from an agent's folder. So the
# agents live in the workspace's docs/ folder, beside the projects, and one
# team works on all of them. Any folders above the workspace are the user's
# own business.
say "  A workspace is a folder that holds one or more projects, such as the"
say "  software of one company. The agents live in its docs/ folder, so they"
say "  work on the projects in it. A project you add later goes in the same"
say "  folder, and the same agents work on it."
say ""
row ""                    "workspace/"            "CLAUDE.md: the rules and every project"
row "├── "                "project-one/"          "your code. One folder per project"
row "├── "                "project-two/"          ""
row "└── "                "docs/agent-workflows/" "orchestrator, research, designer, dev, qa"
say ""
dim "  Folders above the workspace can be anything."
say ""
printf '  You are in %s%s%s\n' "$B" "$HERE" "$N" > /dev/tty

show_here() {
  say ""
  say "  This folder holds:"
  if [ -n "$(ls -A "$HERE" 2>/dev/null)" ]; then
    ls -A "$HERE" | head -n 20 | while IFS= read -r f; do dim "      $f"; done
  else
    dim "      nothing"
  fi
  say ""
  say "  Choose w if this folder holds your projects, or will."
  say "  Choose p if this folder is one project. The harness goes in the folder above."
  say "  Choose n to keep the harness in a new folder of its own, below this one."
}

# Sets LAYOUT to w, p or n. "Don't know" shows the folder and asks again.
ask_layout() {
  local answer=""
  say ""
  printf '  %sWhat is this folder?%s\n' "$B" "$N" > /dev/tty
  say ""
  option w "the workspace. The harness goes in here, beside your projects."
  option p "one project. The harness goes in the folder above, the workspace."
  option n "neither. A new workspace folder goes inside it."
  option d "don't know"
  option q "stop"
  while true; do
    ask "Choose w, p, n, d or q:"
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    case "$answer" in
      w|W) LAYOUT=w; return 0 ;;
      p|P) LAYOUT=p; return 0 ;;
      n|N) LAYOUT=n; return 0 ;;
      d|D|"?") show_here ;;
      q|Q) die "Stopped. Nothing was written." ;;
      *) warn "Choose w, p, n, d or q." ;;
    esac
  done
}

# Sets WS_DIR from LAYOUT, asking for a name where the layout makes a new
# folder. Returns 1, with the reason shown, if the plan cannot work, so the
# user can choose again.
plan() {
  case "$LAYOUT" in
    w) WS_DIR="$HERE" ;;
    p) WS_DIR="$(dirname "$HERE")" ;;
    n) WORKSPACE="$(ask_name "Workspace name" "${WORKSPACE:-workspace}")"
       WS_DIR="$HERE/$WORKSPACE" ;;
  esac

  # A workspace CLAUDE.md in the home folder would load into every Claude
  # session on this computer, so the home folder cannot be the workspace.
  if [ "$WS_DIR" = "$HOME_DIR" ]; then
    warn "That makes the home folder the workspace." \
      "Its CLAUDE.md would load into every Claude session on this computer." \
      "Choose another layout, or make a folder for the harness, change to it," \
      "and run this script again."
    return 1
  fi
  if [ "$LAYOUT" = n ] && [ -e "$WS_DIR" ]; then
    warn "$WS_DIR already exists." "Choose another workspace name, or change to it and choose w."
    return 1
  fi
  if [ "$LAYOUT" != n ]; then
    for name in CLAUDE.md docs; do
      if [ -e "$WS_DIR/$name" ]; then
        warn "$WS_DIR already has $name, and the harness would write its own." \
          "Move it aside, or choose another layout."
        return 1
      fi
    done
    if [ ! -w "$WS_DIR" ]; then
      warn "Cannot write to $WS_DIR." "Choose another layout."
      return 1
    fi
  fi
  return 0
}

draw_plan() {
  local ws_note ws_mark="" projects="" p last
  if [ ! -e "$WS_DIR" ]; then
    ws_note="workspace. New folder, with CLAUDE.md."
  else
    ws_note="workspace. CLAUDE.md is added."
  fi
  [ "$LAYOUT" = w ] && ws_mark="you are here"

  # The folders already in the workspace are shown as projects. Setup confirms
  # each one with the user, so a folder that is not a project costs nothing.
  if [ -d "$WS_DIR" ]; then
    projects="$(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sort | head -n 8)"
  fi

  say ""
  printf '  %sThis is what will be set up.%s\n' "$B" "$N" > /dev/tty
  say ""
  if [ "$LAYOUT" = n ]; then
    dim "  In $(dirname "$HERE")"
    say ""
    row ""         "$(basename "$HERE")/"     ""                "you are here"
    row "└── "     "$(basename "$WS_DIR")/"   "$ws_note"
    row "    └── " "docs/agent-workflows/"    "the five agents, for every project"
  else
    dim "  In $(dirname "$WS_DIR")"
    say ""
    row "" "$(basename "$WS_DIR")/" "$ws_note" "$ws_mark"
    if [ -n "$projects" ]; then
      while IFS= read -r p; do
        if [ "$LAYOUT" = p ] && [ "$WS_DIR/$p" = "$HERE" ]; then
          row "├── " "$p/" "project. Left as it is." "you are here"
        else
          row "├── " "$p/" "project. Left as it is."
        fi
      done <<< "$projects"
    fi
    row "└── " "docs/agent-workflows/" "the five agents, for every project"
  fi
  say ""
  dim "  Anything already in these folders is left alone. The orchestrator"
  dim "  confirms each project with you during setup."
}

# Returns 0 to go ahead, 1 to edit. q stops.
confirm_plan() {
  local answer=""
  while true; do
    ask "Set it up like this?"
    printf '%sy%s go ahead  %se%s change it  %sq%s stop: ' "$C$B" "$N" "$C$B" "$N" "$C$B" "$N" > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    case "$answer" in
      y|Y|yes|Yes|YES) return 0 ;;
      e|E) return 1 ;;
      q|Q) die "Stopped. Nothing was written." ;;
      *) warn "Answer y, e or q." ;;
    esac
  done
}

LAYOUT="" WS_DIR="" WORKSPACE=""
while true; do
  ask_layout
  plan || continue
  draw_plan
  confirm_plan && break
done

# ------------------------------------------------------------------ download
section 3 "Setting it up"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
curl -fsSL "$url" -o "$tmp/harness.tar.gz" || die "Download failed from $url"

# Unpack whole, then move what is wanted. Matching member names by pattern
# behaves differently under GNU tar and bsdtar; moving a folder does not.
mkdir -p "$tmp/unpacked"
tar -xzf "$tmp/harness.tar.gz" -C "$tmp/unpacked" --strip-components=1 \
  || die "Could not unpack the harness."

src="$tmp/unpacked/$WORKSPACE_SRC"
[ -f "$src/CLAUDE.md" ] && [ -d "$src/docs/agent-workflows/orchestrator" ] \
  || die "The download did not contain what was expected. Nothing was written."
find "$src" -name '.DS_Store' -delete 2>/dev/null || true
ok "downloaded" "github.com/$REPO"

# The workspace may already exist and hold the user's projects. Check every
# name first, so a clash stops before anything is written.
for entry in "$src"/* "$src"/.[!.]*; do
  [ -e "$entry" ] || continue
  [ ! -e "$WS_DIR/$(basename "$entry")" ] \
    || die "$WS_DIR/$(basename "$entry") already exists. Nothing was written."
done

mkdir -p "$WS_DIR"
for entry in "$src"/* "$src"/.[!.]*; do
  [ -e "$entry" ] || continue
  mv "$entry" "$WS_DIR/"
done
if [ ! -e "$WS_DIR/LICENSE" ] && [ -f "$tmp/unpacked/LICENSE" ]; then
  mv "$tmp/unpacked/LICENSE" "$WS_DIR/LICENSE"
fi

ORCHESTRATOR="$WS_DIR/docs/agent-workflows/orchestrator"
ok "workspace" "$WS_DIR"
ok "orchestrator" "$ORCHESTRATOR"

# -------------------------------------------------------------------- hand off
section 4 "Starting the orchestrator"

say "  It takes it from here. It will speak first. It will ask what you want to"
say "  build, then walk you through git, Trello, your projects and their stacks,"
say "  and the other agents. Keys and tokens go in your shell profile, typed by"
say "  you, never in the chat."
say ""
say "  You can stop at any point. To come back, open a terminal and run:"
say ""
printf '    %scd %s && claude%s\n' "$C" "$ORCHESTRATOR" "$N" > /dev/tty
say ""
printf '  %sPress Return to start.%s ' "$B" "$N" > /dev/tty
IFS= read -r _ < /dev/tty || true

# exec replaces this process, so the EXIT trap will not fire.
rm -rf "$tmp"
trap - EXIT

# Launch with no prompt. The orchestrator's SessionStart hook,
# load-first-start-check.sh, sees the unfilled placeholders and tells the
# session to lead with FIRST_START.md whatever the user opens with. A prompt
# here would only compete with it.
cd "$ORCHESTRATOR"
exec claude
