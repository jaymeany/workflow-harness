#!/bin/bash
#
# gate-per-card-commit.sh — Claude Code PreToolUse hook
#
# Fires on mcp__trello__move_card when the destination list name contains "qa".
# Validates that SOME commit reachable from the app repo's HEAD has a subject
# line starting with `#<card-number>`.
#
# This enforces Dev_Protocol.md §5's per-card commit discipline: every card's
# work lands in commit(s) whose subject begins with `#<card-number>`.
# That discipline is what lets §6 drop Files Modified and Adjacent card
# context from the Implementation Notes — QA finds the diff via
# `git log --grep="#<card>"` then `git show <sha>` instead of reading a
# re-narration in the comment.
#
# The hook checks HISTORY, not just HEAD. The protocol's promise to QA is
# grep-findability (`git log --grep="#<card>"` returns the diff), NOT that the
# card's commit is the single most-recent one. A session can legitimately
# commit several cards' diffs interleaved and ship them in a batch — each
# card's diff still lives in a `#<card-number>`-prefixed commit, which is all
# QA needs. Checking HEAD only would assume one card is fully finished and
# shipped before the next is started, and it would trap batch-committed cards.
#
# Repo locations: fixed and named, at <project>/ the code folder, docs and the
# Storybook workbench folder, set during setup. The role folder sits at
# <project>/docs/agent-workflows/<role>/, so the project root is three levels
# up. No discovery, no env var.
#
# The gate passes when a #<card> commit exists in AT LEAST ONE of the three.
# See the REPO_NAMES block below for why that shape rather than resolving the
# expected repo from the card.
#
# Matcher in settings.json: "mcp__trello__move_card"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl, git
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - jq, curl, or git missing
#   - env vars missing
#   - app repo path doesn't exist or isn't a git repo
#   - Trello list/card lookup fails
#
# Fail-open posture mirrors the other gate hooks: transient tooling or API
# blips should not block legitimate work. The discipline lives in §5 DoD as
# prose, so the agent self-enforces when the hook can't.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__move_card" ]]; then
  exit 0
fi

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
dest_list_id=$(echo "$input" | jq -r '.tool_input.listId // empty')
[[ -z "$card_id" || -z "$dest_list_id" ]] && exit 0

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
[[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]] && exit 0

# Only fire when moving INTO the QA column.
list=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${dest_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
dest_list_name=$(echo "$list" | jq -r '.name // empty' | tr '[:upper:]' '[:lower:]')

[[ -z "$dest_list_name" ]] && exit 0
# Substring match on "qa" (a board's column may be "QA" or "Ready for QA"),
# consistent with check-now-on-ready-for-qa.sh and gate-implementation-notes.sh.
case "$dest_list_name" in *qa*) ;; *) exit 0 ;; esac

# Escape hatch: cards whose work produces NO committable diff.
#
# Some cards finish correctly without leaving anything in git — the touched
# files are all gitignored (`.env`, an ignored `CLAUDE.md`), the work lands in
# database or console state, or the card resolves to "no change required". For
# those, this gate's premise does not hold: there is no commit to find because
# there is nothing to commit, and no amount of retrying will produce one. The
# gate would otherwise strand finished work permanently.
#
# Set ALLOW_NO_CARD_COMMIT=1 for that specific move, and say in the §6
# Implementation Notes WHY no diff exists, so QA can audit the claim instead of
# taking it on trust. Deliberately an env var and not a file flag: it applies to
# one invocation and cannot silently persist, mirroring ALLOW_LOCAL_BUILD and
#
# This is NOT for "I forgot to commit" — that is the failure this gate exists
# to catch, and the fix there is to commit.
if [[ -n "${ALLOW_NO_CARD_COMMIT:-}" ]]; then
  echo "gate-per-card-commit.sh: ALLOW_NO_CARD_COMMIT set — commit check skipped for this move. Implementation Notes must state why no diff exists." >&2
  exit 0
fi

# Same hatch, as a ONE-SHOT MARKER FILE. This is the usable form from inside a
# session: an agent cannot set an env var on the Claude Code process that
# invokes this hook, and putting one in settings.json would make it persist —
# defeating the point.
#
# The file is CONSUMED (deleted) on use, before the allow. So it covers exactly
# one move and cannot silently linger, which is a stronger guarantee than the
# env var gives. A second diff-less move needs a second deliberate touch.
MARKER="$CLAUDE_PROJECT_DIR/.claude/.allow-no-card-commit"
if [[ -f "$MARKER" ]]; then
  rm -f "$MARKER"
  echo "gate-per-card-commit.sh: one-shot no-commit marker consumed — commit check skipped for THIS move only; marker deleted. Implementation Notes must state why no diff exists." >&2
  exit 0
fi

# Fetch card name + idShort (the card number Dev prefixes commits with).
# idBoard is also fetched so the worktree resolver can ask the BOARD which
# shortname applies — that's the authoritative source. Card titles encode
# the worktree as their last token, but stale titles drift (e.g., a card
# moved from the dev board to the feature board keeps "dev" in its title).
# The board name doesn't drift.
card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=name,idShort,idBoard&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
card_name=$(echo "$card" | jq -r '.name // empty')
card_number=$(echo "$card" | jq -r '.idShort // empty')
card_board_id=$(echo "$card" | jq -r '.idBoard // empty')

[[ -z "$card_name" || -z "$card_number" ]] && exit 0

# Resolve the project's repositories. The project holds THREE, recorded in
# the project CLAUDE.md: the code folder, docs and the Storybook workbench.
# $CLAUDE_PROJECT_DIR is the role's cwd (<project>/docs/agent-workflows/<role>/), so:
#   ../../..      = the project root
#
# Fixed paths are deliberate and stay that way. A sibling-discovery walk from
# here could reach unrelated folders and resolve a repo that has nothing to do
# with this work. Named paths cannot pick wrong. If another repo appears, add
# its name to REPO_NAMES.
PROJECT_ROOT="$(cd "$CLAUDE_PROJECT_DIR/../../.." 2>/dev/null && pwd)"

# The code folder, the docs repo and the Storybook workbench, set during setup.
REPO_NAMES=("{{CODE_DIR}}" docs "{{STORYBOOK_DIR}}")

REPOS=()
for name in "${REPO_NAMES[@]}"; do
  # Fail open per repo: a named tree that is absent or not a repo is skipped
  # rather than treated as an error. Same posture the whole-gate fail-open
  # below has always had.
  if [[ -n "$PROJECT_ROOT" && -e "$PROJECT_ROOT/$name/.git" ]]; then
    REPOS+=("$PROJECT_ROOT/$name")
  fi
done

# The code folder is the publishing repo and the one the block message points at.
APP_REPO_DIR=""
if [[ -n "$PROJECT_ROOT" && -e "$PROJECT_ROOT/{{CODE_DIR}}/.git" ]]; then
  APP_REPO_DIR="$PROJECT_ROOT/{{CODE_DIR}}"
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
  # No repo at all. Fail open, and surface a one-line note to stderr so the
  # operator knows the hook didn't run, but allow the move (the prose DoD is
  # the backstop).
  echo "gate-per-card-commit.sh: no git repo under '$PROJECT_ROOT', skipping commit check" >&2
  exit 0
fi

# THERE IS NO BRANCH WARNING. This hook fires on a card move and never on a
# push, so it is the wrong place to guard the branch model.
# `block-destructive-bash.sh` is where push policy lives.

# WHAT THIS GATE REQUIRES: a #<card> commit in AT LEAST ONE known repo.
#
# The stricter shape, resolving the expected repo from the card and requiring
# the commit there, was considered and rejected. Nothing on a card names its
# tree in a form a hook can read: the title's last token is a worktree
# shortname, not a repo. Deriving it would mean inventing a convention, and a
# wrong derivation is a FALSE STOP, which is the worst failure a gate has. A
# false stop blocks correct work and teaches the operator to reach for the
# marker.
#
# "At least one" cannot false-stop, and a card that simply forgot to commit is
# still caught, because it has no #<card> commit in any of them.


# Check HISTORY for a commit whose SUBJECT begins with #<card_number>,
# followed by a non-digit or end-of-line. The non-digit guard prevents
# card #7 from false-matching against #79. This is exactly the lookup QA
# performs (`git log --grep`), so it tests the discipline's actual promise
# rather than the position of the commit in history.
matching_subject=""
for repo in "${REPOS[@]}"; do
  matching_subject=$(git -C "$repo" log --pretty=format:%s 2>/dev/null \
    | grep -E "^#${card_number}([^0-9]|$)" | head -1 || true)
  [[ -n "$matching_subject" ]] && break
done

if [[ -n "$matching_subject" ]]; then
  exit 0  # Discipline observed — the card's diff is in a prefixed commit.
fi

# No prefixed commit in any known repo. Surface each repo's HEAD for context,
# so the operator can see at a glance which tree they actually committed to.
latest_subject=""
for repo in "${REPOS[@]}"; do
  head_subject=$(git -C "$repo" log -1 --pretty=format:%s HEAD 2>/dev/null || echo '(no commits)')
  latest_subject+="  $(basename "$repo"): ${head_subject}
"
done
searched_list="$(printf '%s ' "${REPO_NAMES[@]}")"

cat >&2 <<EOF
BLOCKED: card "${card_name}" cannot move to QA — per-card commit discipline violated.

Dev_Build.md §10 requires the card's diff to live in commit(s) whose subject
begins with \`#<card-number>\`, in whichever of the project's three repos the work
belongs to: \`{{CODE_DIR}}/\`, \`docs/\` or \`{{STORYBOOK_DIR}}/\`, each on the branch named in
the project CLAUDE.md § Repos and branches.
The hook searches all of HEAD's history in each (the same lookup QA runs).

  Expected subject prefix: #${card_number}
  Searched: ${searched_list}
  No matching commit in any of them. Each repo's HEAD subject:
${latest_subject}
This discipline is what lets §6 drop Files Modified and Adjacent card
context from the comment — QA finds the diff via
\`git log --grep="#${card_number}"\` then \`git show <sha>\`. Without
a prefixed commit, that lookup returns nothing and QA has to
reverse-engineer scope from HEAD's tree.

Fix: commit the card's work with a \`#${card_number}\` subject prefix
(or, if the diff is already committed under a different subject, amend
that commit's subject to start with \`#${card_number}\`).

  cd <the repo the diff belongs in>
  git commit -m "#${card_number} <one-line summary>"

Then retry the move.
EOF
exit 2
