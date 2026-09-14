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
#
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

# PLAIN `git push` IS NOT BLOCKED for Dev. Dev pushes according to the branch
# model in the project CLAUDE.md § Repos and branches.
#
# The force guard below stays. That one is about rewriting history other people
# hold, which is a different question from whether Dev may ship.

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
