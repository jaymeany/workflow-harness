#!/bin/bash
#
# load-status-digest.sh — Claude Code SessionStart hook
#
# Surfaces the load status of session-start doc hooks: which docs were
# inlined in full vs. which overflowed and got persisted to a file
# (where the harness substitutes only a ~2KB preview, silently turning
# a session-start doc into a pointer the agent has to manually fetch).
#
# Provenance:
#   - The ~10,000-char additionalContext cap is a Claude Code harness
#     constraint (https://code.claude.com/docs/en/hooks). Real, native.
#   - This digest hook is agent-authored. Its job is to make the cap's
#     consequence visible at session start so an overflow can never
#     hide behind a normal-looking system reminder again.
#
# Discovery: globs `load-dev-*.sh` in the hooks dir, excludes state
# loaders (bus-catchup, trello-catchup) and the digest itself. Re-runs
# each remaining loader in a subshell and measures the real emitted
# payload — no duplication of any loader's path or slicing logic.
#
# Must run AFTER all other SessionStart hooks in settings.json so its
# output appears at the bottom of the session-start context.
#
# Requires: jq, bash, wc
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

THRESHOLD=9500
HOOKS_DIR="${CLAUDE_PROJECT_DIR}/.claude/hooks"

declare -a entries
overflow_count=0
ok_count=0
max_chars=0

for loader_path in "$HOOKS_DIR"/load-qa-*.sh; do
  [[ -f "$loader_path" ]] || continue
  loader=$(basename "$loader_path" .sh)

  # Skip non-doc loaders (state catchups) and the digest itself.
  case "$loader" in
    load-qa-bus-catchup|load-qa-trello-catchup|load-status-digest) continue ;;
  esac

  # Re-run the loader; capture its real emitted JSON. `|| true` so a
  # loader failure can't abort the digest under `set -e`.
  output=$(bash "$loader_path" 2>/dev/null || true)
  body=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || echo "")
  chars=$(printf '%s' "$body" | wc -m | tr -d ' ')

  if [[ "$chars" -gt "$max_chars" ]]; then
    max_chars="$chars"
  fi

  if [[ -z "$body" ]] || [[ "$chars" -le 0 ]]; then
    entries+=("| ${loader} | 0 | EMPTY (loader emitted no body) |")
    overflow_count=$((overflow_count + 1))
  elif [[ "$chars" -gt "$THRESHOLD" ]]; then
    entries+=("| ${loader} | ${chars} | OVERFLOW (>${THRESHOLD} — content persisted as file, only ~2KB preview inlined) |")
    overflow_count=$((overflow_count + 1))
  else
    entries+=("| ${loader} | ${chars} | OK |")
    ok_count=$((ok_count + 1))
  fi
done

total=$((ok_count + overflow_count))

if [[ "$total" -eq 0 ]]; then
  digest="## Session Start Doc Loader Status

No doc loaders found under ${HOOKS_DIR}."
elif [[ "$overflow_count" -eq 0 ]]; then
  digest="## Session Start Doc Loader Status

${ok_count}/${total} doc loaders inlined in full (max ${max_chars} chars; harness cap ~10000)."
else
  rows=$(printf '%s\n' "${entries[@]}")
  digest="## Session Start Doc Loader Status — WARNING

${overflow_count}/${total} doc loader(s) overflowed the additionalContext cap. Affected docs were persisted as files with only a ~2KB preview inlined; the agent is operating on inference for the rest of those docs. Decisions referencing the persisted sections must Read the source file first.

| Loader | Chars | Status |
|---|---|---|
${rows}

Cap is a harness constraint (~10000 chars per additionalContext payload). Fix by splitting the source doc into smaller files at semantic boundaries — one loader per file. Do not work around it by slicing a loader into byte ranges."
fi

jq -n --arg ctx "$digest" '{
  systemMessage: $ctx,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
