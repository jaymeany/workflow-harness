#!/bin/bash
#
# precompact-write-handoff.sh — Claude Code PreCompact hook (all roles)
#
# On context compaction (manual OR automatic), block unless today's handoff for
# this role exists AND is fresh (modified within FRESHNESS_SECONDS). Surfaces a
# structured stderr prompt so the agent writes (or refreshes) the durable
# cross-session artifact BEFORE compaction summarizes session detail away.
#
# Matcher in settings.json: PreCompact / "manual|auto"
# Fires on BOTH manual /compact AND auto-compaction. A session can hit the
# context wall WITHOUT auto-compact ever firing (it freezes), forcing the human
# into a manual /compact — the exact ungated-compaction scenario this gate
# exists to prevent. The freeze path ENDS in manual /compact, so manual must be
# gated identically. exit 2 blocks both modes and feeds stderr back (per hooks docs).
#
# Sweep-safe: writes nothing; checks and instructs one computed path only.
#
# Path resolution:
#   $CLAUDE_PROJECT_DIR is the role cwd (harness/<role>/).
#   Handoffs live at ../../handoffs/.
#
# Requires: bash
# Requires-Path: ../../handoffs
#
# The path declaration is load-bearing. This hook fails open when the
# handoffs directory is absent. audit-fail-open.sh checks this line at
# SessionStart, so the absence announces itself.
#
# Exit codes:
#   0 — allow compaction (fresh handoff exists, or env unresolvable — fail-open)
#   2 — block compaction with stderr instruction

set -euo pipefail

if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then
  exit 0
fi

HANDOFFS_DIR="${CLAUDE_PROJECT_DIR}/../../handoffs"
if [[ ! -d "$HANDOFFS_DIR" ]]; then
  exit 0
fi

TODAY=$(date +%Y-%m-%d)
# Role is derived from the session cwd, never hardcoded. This file is shared
# verbatim by every role; each role writes and reads its own handoff.
ROLE="$(basename "${CLAUDE_PROJECT_DIR}")"
HANDOFF_FILE="${HANDOFFS_DIR}/${ROLE}-handoff-${TODAY}.md"

FRESHNESS_SECONDS=3600

# File modification time in epoch seconds. GNU stat (Linux) first; on macOS
# `stat -c` fails and the BSD form runs. The other order is wrong on Linux,
# where `stat -f` means file-system status.
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# BLOCK ONCE, THEN GET OUT OF THE WAY.
#
# The failure: a session at the context wall cannot take a turn to write a
# handoff, and compaction is how it regains the capacity to write one.  Blocking
# there makes the remedy require the resource being denied.  That is a deadlock,
# and the documented escape hatch was a shell command the wedged session could
# not run for itself.
#
# The reasoning for gating manual as well as auto is sound: a frozen session
# ends in a manual /compact, so gating auto alone leaves a hole.  What matters
# is a ceiling on refusals.
#
# FIRST refusal blocks and says why.  A second refusal within two hours means
# the session demonstrably cannot comply: write a placeholder, warn loudly, and
# ALLOW.  A gate that reminds you is doing its job.  A gate that traps you has
# stopped being one.
# ---------------------------------------------------------------------------
REFUSAL_MARKER="${HANDOFFS_DIR}/.${ROLE}-precompact-refused"
if [[ -f "$REFUSAL_MARKER" ]]; then
  marker_age=$(( $(date +%s) - $(file_mtime "$REFUSAL_MARKER") ))
  if (( marker_age < 7200 )); then
    if [[ ! -f "$HANDOFF_FILE" ]]; then
      {
        printf '# %s handoff placeholder — %s\n\n' "$ROLE" "$TODAY"
        printf '**Written by precompact-write-handoff.sh after a second refusal, not by the session.**\n\n'
        printf 'The session could not take a turn to write a handoff, so compaction was allowed rather\n'
        printf 'than wedging it. **This is a placeholder.** The detail a handoff should carry was\n'
        printf 'summarised away. Reconstruct from the board, the commits and the other roles.\n'
      } > "$HANDOFF_FILE"
    fi
    rm -f "$REFUSAL_MARKER"
    echo "precompact-write-handoff.sh: second refusal, session cannot comply. Placeholder written, compaction ALLOWED. ${HANDOFF_FILE} is NOT a handoff." >&2
    exit 0
  fi
fi
touch "$REFUSAL_MARKER"

if [[ -f "$HANDOFF_FILE" ]]; then
  now=$(date +%s)
  mtime=$(file_mtime "$HANDOFF_FILE")
  if [[ -z "$mtime" || "$mtime" -eq 0 ]]; then
    exit 0
  fi
  age=$(( now - mtime ))
  if (( age <= FRESHNESS_SECONDS )); then
    exit 0
  fi
  ABS_HANDOFF_FILE=$(cd "$HANDOFFS_DIR" 2>/dev/null && pwd)/${ROLE}-handoff-${TODAY}.md
  cat >&2 <<EOF
BLOCKED: auto-compaction is imminent and today's ${ROLE} handoff is STALE ($(( age / 60 )) minutes since last write).

Everything since then is about to be summarized away. UPDATE the handoff first — refresh the sections that changed (cards moved, checks run, rulings, open threads); append rather than rewrite where earlier content still stands.

Update:
  $ABS_HANDOFF_FILE

Then continue working — the next compaction attempt (manual or auto) passes while the file's last write is under $(( FRESHNESS_SECONDS / 60 )) minutes old.

HUMAN ESCAPE HATCH: if the session is already at the context wall and cannot take a turn to refresh the handoff, run:
  touch "$ABS_HANDOFF_FILE" && /compact
The fresh mtime passes the gate — trading the refresh away is then an explicit human decision, not a dead end.
EOF
  exit 2
fi

ABS_HANDOFF_FILE=$(cd "$HANDOFFS_DIR" 2>/dev/null && pwd)/${ROLE}-handoff-${TODAY}.md

cat >&2 <<EOF
BLOCKED: auto-compaction would summarize away session detail before today's ${ROLE} handoff was written.

The handoff is the durable cross-session artifact. Write it first, then continue working — the next auto-compact attempt will pass once this file exists.

Write to:
  $ABS_HANDOFF_FILE

Quality bar: this is what the next ${ROLE} session boots from. Cite commits and file:line where claims rest on them. Skip sections that genuinely don't apply — don't pad.

Structure (in this order):

  # ${ROLE} handoff — $TODAY

  <One short paragraph: the session arc — cards worked, context, anything unusual about the flow.>

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

  Small operational facts the next session needs: monitor/watcher state and PIDs, staged-but-unapplied changes awaiting the user, tool quirks discovered.

Retry: continue working and the next compaction (manual or auto) passes once the file exists, or run \`/compact\` after writing.

HUMAN ESCAPE HATCH: if the session is already at the context wall and cannot take a turn to write the handoff, run:
  touch "$ABS_HANDOFF_FILE" && /compact
That creates the file with a fresh mtime so the gate passes — trading the handoff away becomes an explicit human decision instead of wedging the only exit.
EOF

exit 2
