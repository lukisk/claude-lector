#!/bin/bash
# Claude Lector — UserPromptSubmit hook.
# Appends the submitted prompt as one JSON line to the Claude Lector inbox and exits.
# It must never print anything (Claude Code would add stdout to the prompt's context),
# never block, and always exit 0.
exec >/dev/null 2>&1
trap 'exit 0' EXIT

INBOX="${CLAUDE_LECTOR_INBOX:-$HOME/Library/Application Support/ClaudeLector/inbox.jsonl}"
command -v jq >/dev/null || exit 0
mkdir -p "$(dirname "$INBOX")" || exit 0

line=$(jq -c \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg ep "${CLAUDE_CODE_ENTRYPOINT-}" \
  --arg att "${CLAUDE_CODE_SESSION_ATTENDED-}" \
  '{prompt_id: (.prompt_id // ""), session_id: (.session_id // ""), cwd: (.cwd // ""), prompt: (.prompt // ""),
    timestamp: $ts,
    entrypoint: (if $ep == "" then null else $ep end),
    attended: (if $att == "" then null else $att end)}') || exit 0
[ -n "$line" ] || exit 0
printf '%s\n' "$line" >> "$INBOX"
