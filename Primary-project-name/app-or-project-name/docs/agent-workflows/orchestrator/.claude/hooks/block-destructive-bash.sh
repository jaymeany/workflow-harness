#!/bin/bash
#
# block-destructive-bash.sh — Claude Code PreToolUse hook
#
# Blocks a small set of commands that are destructive beyond the current
# session, where the damage is not obvious at the moment of typing and not
# recoverable afterwards.
#
# Matcher in settings.json should be: "Bash"
#
# Requires: jq
#
# Exit codes:
#   0 — allow
#   2 — block, with the reason on stderr

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
[[ -n "$cmd" ]] || exit 0

# `killall -9 node` reaches every Node process on the machine, including the
# editor, Figma, and any long-running agent session. The blast radius is the
# whole desktop and nothing on screen says so.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])killall([[:space:]]+-[0-9A-Za-z]+)*[[:space:]]+node([[:space:]]|$)'; then
  cat >&2 <<'MSG'
BLOCKED: killall node.

This kills every Node process on the machine, not only the one you mean.
Editors, design tools and other agent sessions go with it.

Target the process instead:

  lsof -nP -iTCP:<port> -sTCP:LISTEN    # find the pid
  kill <pid>
MSG
  exit 2
fi

# `git push` is the outward-facing, irreversible action reachable from this
# harness, and nothing on screen at the moment of typing says so.
# protocol/Dev_Build.md §10 states the rule in prose; this is the gate behind
# it. Pushing is the user's call, never a card's. Blocks every push, not only
# force pushes.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|;)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'; then
  cat >&2 <<'MSG'
BLOCKED: git push.

Pushing is the user's decision, never a card's.

  {{CODE_DIR}}/    the code. Merging and pushing is the user's call.
                   Commit freely; do not push.
  docs/            the docs repo.
  {{STORYBOOK_DIR}}/    the Storybook workbench, if the project has one.

Commit and stop there:

  cd ../../../{{CODE_DIR}}
  git commit -m "#<card> <what changed>"

Then move the card to QA. If a card genuinely cannot complete without a push,
that is a bounce to Research, not a workaround.
MSG
  exit 2
fi

# `git push --force` to a shared branch rewrites history other people hold.
# --force-with-lease refuses when the remote moved, which is the case this
# guards against.
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]].*(--force|-f)([[:space:]]|$)' \
   && ! printf '%s' "$cmd" | grep -q -- '--force-with-lease'; then
  cat >&2 <<'MSG'
BLOCKED: git push --force.

Use --force-with-lease. It refuses the push when the remote has moved since
you last fetched, which is the situation a plain --force silently destroys.

  git push --force-with-lease
MSG
  exit 2
fi

exit 0
