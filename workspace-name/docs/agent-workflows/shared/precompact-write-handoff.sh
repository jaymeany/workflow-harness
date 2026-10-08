#!/bin/bash
#
# precompact-write-handoff.sh — Claude Code PreCompact hook (all roles)
#
# ONE copy, shared by every role, the same way board/board.sh is. Each role's
# settings.json points here. The hook needs nothing from its own location: the
# role is $CLAUDE_PROJECT_DIR's basename and handoffs sit at ../../handoffs
# from there, so it behaves identically wherever it is invoked from.
#
# Five copies of this file used to exist. They were byte-identical, which is
# the state a copy is in right before it stops being identical.
#
# WHAT IT IS FOR
#
# Compaction summarises session detail away. The handoff is the durable
# artifact the next session of that role boots from. So the gate tries to get
# the handoff written, or refreshed, before the detail is gone.
#
# Matcher in settings.json: "manual|auto". BOTH paths. A session can hit the
# context wall WITHOUT auto-compact firing (it freezes), which forces the
# human into a manual /compact. Gating auto alone leaves that door open.
#
# HOW HARD IT PUSHES IS A PREFERENCE
#
# shared/preferences.conf sets HANDOFF_GATE to block, warn or off. Blocking
# compaction until someone writes a handoff is a strong opinion about how to
# work, and not everyone shares it. Default is block; the refusal message says
# how to change it.
#
# BLOCK ONCE, THEN GET OUT OF THE WAY
#
# A session at the context wall cannot take a turn to write a handoff, and
# compaction is how it regains the capacity to write one. Refusing there makes
# the remedy require the resource being denied. So the gate refuses at most
# once per session: the first refusal blocks and says why, and a later
# compaction in the same session proceeds, writing a placeholder if no handoff
# exists at all. A gate that reminds you is doing its job. A gate that traps
# you has stopped being one.
#
# "Once per session" is keyed to the session_id Claude Code puts on stdin, not
# to a wall-clock window. An earlier version approximated the session with a
# two-hour timer and touched its marker before the allow paths, so a
# compaction that PASSED armed the bypass for the next one: the same stale
# handoff would block or pass depending only on whether an earlier compaction
# had happened to succeed. The marker is now written on the refusal path and
# nowhere else.
#
# STDERR IS NOT A CHANNEL HERE
#
# On exit 0 Claude never sees stderr; it goes to the debug log. Anything the
# agent needs to know on an allowed compaction goes out as systemMessage JSON.
# stderr is only meaningful alongside exit 2.
#
# Sweep-safe: writes one marker and, at most, one placeholder handoff, both on
# computed paths. Never touches an existing handoff.
#
# Requires: bash, jq
# Requires-Path: ../../handoffs
#
# The path declaration is load-bearing. This hook fails open when the handoffs
# directory is absent. audit-fail-open.sh checks this line at SessionStart, so
# the absence announces itself.
#
# Exit codes:
#   0 — allow compaction (fresh handoff, gate off, already refused, or
#       anything unresolvable — fail open)
#   2 — refuse compaction, with the instruction on stderr

set -uo pipefail

# Read stdin once, whatever happens next. A PreCompact payload carries
# session_id; an empty or unparseable one is not a reason to wedge.
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  exit 0
fi

HANDOFFS_DIR="${CLAUDE_PROJECT_DIR}/../../handoffs"
if [ ! -d "$HANDOFFS_DIR" ]; then
  exit 0
fi

# Role is derived from the session cwd, never hardcoded. One file serves every
# role; each writes and reads its own handoff.
ROLE="$(basename "$CLAUDE_PROJECT_DIR")"
TODAY="$(date +%Y-%m-%d)"
HANDOFF_FILE="${HANDOFFS_DIR}/${ROLE}-handoff-${TODAY}.md"

# ---------------------------------------------------------------------------
# Preference
# ---------------------------------------------------------------------------
HANDOFF_GATE="block"
HANDOFF_FRESHNESS_SECONDS=3600
_conf="$(dirname "${BASH_SOURCE[0]}")/preferences.conf"
if [ -f "$_conf" ]; then
  # shellcheck disable=SC1090
  . "$_conf"
fi
case "${HANDOFF_GATE:-}" in
  block|warn|off) ;;
  *) HANDOFF_GATE="block" ;;
esac
case "${HANDOFF_FRESHNESS_SECONDS:-}" in
  ''|*[!0-9]*) HANDOFF_FRESHNESS_SECONDS=3600 ;;
esac

[ "$HANDOFF_GATE" = "off" ] && exit 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# File modification time in epoch seconds. GNU stat (Linux) first; on macOS
# `stat -c` fails and the BSD form runs. The other order is wrong on Linux,
# where `stat -f` means file-system status.
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# say_and_allow <text> — the only way to reach the agent on exit 0.
say_and_allow() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$1" '{systemMessage: $m}'
  fi
  exit 0
}

ABS_HANDOFFS_DIR="$(cd "$HANDOFFS_DIR" 2>/dev/null && pwd)"
ABS_HANDOFF_FILE="${ABS_HANDOFFS_DIR:-$HANDOFFS_DIR}/${ROLE}-handoff-${TODAY}.md"

# ---------------------------------------------------------------------------
# Is today's handoff fresh?
# ---------------------------------------------------------------------------
state="missing"
age_min=0
if [ -f "$HANDOFF_FILE" ]; then
  mtime="$(file_mtime "$HANDOFF_FILE")"
  if [ -z "$mtime" ] || [ "$mtime" -eq 0 ] 2>/dev/null; then
    exit 0   # cannot stat it; fail open rather than guess
  fi
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -le "$HANDOFF_FRESHNESS_SECONDS" ]; then
    exit 0   # fresh. Nothing to say, nothing to record.
  fi
  state="stale"
  age_min=$(( age / 60 ))
fi

# ---------------------------------------------------------------------------
# warn: never refuse, but make sure the agent knows
# ---------------------------------------------------------------------------
if [ "$HANDOFF_GATE" = "warn" ]; then
  if [ "$state" = "stale" ]; then
    say_and_allow "Compaction is proceeding and today's ${ROLE} handoff is ${age_min} minutes old. Everything since then is about to be summarised away. Refresh ${ABS_HANDOFF_FILE} when you can. (HANDOFF_GATE=warn in agent-workflows/shared/preferences.conf.)"
  fi
  say_and_allow "Compaction is proceeding and today's ${ROLE} handoff has not been written. This session's detail is about to be summarised away. Write ${ABS_HANDOFF_FILE} when you can. (HANDOFF_GATE=warn in agent-workflows/shared/preferences.conf.)"
fi

# ---------------------------------------------------------------------------
# block: refuse once per session, then yield
# ---------------------------------------------------------------------------

# Session identity comes from the payload. Without it the gate still works;
# it just cannot tell one session from another, so it refuses once per day.
SESSION_KEY="nosession-${TODAY}"
if [ -n "$HOOK_INPUT" ] && command -v jq >/dev/null 2>&1; then
  _sid="$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  _sid="$(printf '%s' "$_sid" | tr -cd 'A-Za-z0-9-')"
  [ -n "$_sid" ] && SESSION_KEY="$_sid"
fi
MARKER="${HANDOFFS_DIR}/.${ROLE}-precompact-refused-${SESSION_KEY}"

# Markers are per session and tiny. Drop ones older than two days so they
# cannot accumulate. Scoped to this role's own marker name.
find "$HANDOFFS_DIR" -maxdepth 1 -name ".${ROLE}-precompact-refused-*" -mtime +2 -delete 2>/dev/null || true

if [ -f "$MARKER" ]; then
  # Already refused this session. The session has demonstrated it cannot
  # comply, so allow rather than wedge it.
  if [ ! -f "$HANDOFF_FILE" ]; then
    {
      printf '# %s handoff placeholder, %s\n\n' "$ROLE" "$TODAY"
      printf 'Written by precompact-write-handoff.sh after a second refusal, not by the session.\n\n'
      printf 'The session could not take a turn to write a handoff, so compaction was allowed\n'
      printf 'rather than wedging it. This is a placeholder. The detail a handoff should carry\n'
      printf 'was summarised away. Reconstruct from the board, the commits and the other roles.\n'
    } > "$HANDOFF_FILE"
    say_and_allow "Compaction was allowed after a second refusal: this session could not write a handoff. A PLACEHOLDER was written to ${ABS_HANDOFF_FILE}. It is not a handoff. Replace it when you have room, or reconstruct from the board, the commits and the other roles."
  fi
  say_and_allow "Compaction was allowed after a second refusal. Today's ${ROLE} handoff is still ${age_min} minutes old, so this session's recent detail is not in it. Refresh ${ABS_HANDOFF_FILE} when you have room."
fi

touch "$MARKER"

if [ "$state" = "stale" ]; then
  cat >&2 <<EOF
BLOCKED: compaction is imminent and today's ${ROLE} handoff is STALE (${age_min} minutes since last write).

Everything since then is about to be summarized away. UPDATE the handoff first, refreshing the sections that changed (cards moved, checks run, rulings, open threads). Append rather than rewrite where earlier content still stands.

Update:
  $ABS_HANDOFF_FILE

Then continue working. The next compaction in this session will not be refused again, whether or not you update it, so this is a reminder rather than a trap.

HUMAN ESCAPE HATCH: if the session is already at the context wall and cannot take a turn, run:
  touch "$ABS_HANDOFF_FILE" && /compact

PREFERENCE: this gate is HANDOFF_GATE in agent-workflows/shared/preferences.conf. Set it to "warn" to be told without being stopped, or "off" to switch it off.
EOF
  exit 2
fi

cat >&2 <<EOF
BLOCKED: compaction would summarize away session detail before today's ${ROLE} handoff was written.

The handoff is the durable cross-session artifact. Write it first, then continue working.

Write to:
  $ABS_HANDOFF_FILE

Quality bar: this is what the next ${ROLE} session boots from. Cite commits and file:line where claims rest on them. Skip sections that genuinely don't apply. Don't pad.

Structure (in this order):

  # ${ROLE} handoff, $TODAY

  <One short paragraph: the session arc. Cards worked, context, anything unusual about the flow.>

  ## State at close

  Board truth right now: this role's column contents, cards moved this session (number, destination, why), repo branch/HEAD and clean/dirty, commits authored this session (hash + one line each).

  ## Checks run

  Each check or gate run this session: what ran, against which commit, and the result. Note any environmental problems diagnosed.

  ## Rulings of record (cite, don't re-litigate)

  User rulings VERBATIM with dates, plus any new precedents this session established.

  ## Open threads (blocking and non-blocking)

  Cards waiting on rework or on another role, pending user decisions, and what unblocks each.

  ## Process rules this session paid for

  New or reinforced rules, each with where it now lives (memory file, protocol doc, hook).

  ## Working notes

  Small operational facts the next session needs: watcher state and PIDs, staged-but-unapplied changes awaiting the user, tool quirks discovered.

The next compaction in this session will not be refused again, whether or not you write it, so this is a reminder rather than a trap.

HUMAN ESCAPE HATCH: if the session is already at the context wall and cannot take a turn, run:
  touch "$ABS_HANDOFF_FILE" && /compact

PREFERENCE: this gate is HANDOFF_GATE in agent-workflows/shared/preferences.conf. Set it to "warn" to be told without being stopped, or "off" to switch it off.
EOF

exit 2
