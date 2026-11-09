#!/bin/bash
# Tests for scripts/install-hook.sh against a temporary HOME.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT/scripts/install-hook.sh"
HOOK="$ROOT/hooks/capture-prompt.sh"
fail=0
pass() { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }
ours() { jq "[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == \"$HOOK\")] | length" "$1"; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S="$T/.claude/settings.json"

# 1. no settings file
HOME="$T" "$INSTALL" >/dev/null
jq -e --arg h "$HOOK" '.hooks.UserPromptSubmit[0].hooks[0] == {"type":"command","command":$h}' "$S" >/dev/null \
  && pass "creates settings.json" || bad "creates settings.json"

# 2. existing settings preserved, ours appended, backup written
cat > "$S" <<JSON
{"model":"opus","env":{"A":"1"},"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/other/hook.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"/stop.sh"}]}]}}
JSON
HOME="$T" "$INSTALL" >/dev/null
jq -e '.model=="opus" and .env.A=="1" and (.hooks.Stop|length)==1 and ([.hooks.UserPromptSubmit[].hooks[].command]|index("/other/hook.sh")) != null' "$S" >/dev/null \
  && [[ $(ours "$S") -eq 1 ]] && pass "preserves other settings" || bad "preserves other settings"
ls "$T/.claude/" | grep -q '^settings.json.bak-' && pass "backup written" || bad "backup written"

# 3. idempotent
HOME="$T" "$INSTALL" >/dev/null
[[ $(ours "$S") -eq 1 ]] && pass "idempotent" || bad "idempotent"

# 4. uninstall
HOME="$T" "$INSTALL" --uninstall >/dev/null
[[ $(ours "$S") -eq 0 ]] && jq -e '[.hooks.UserPromptSubmit[].hooks[].command]|index("/other/hook.sh") != null' "$S" >/dev/null \
  && jq -e '.model=="opus"' "$S" >/dev/null && pass "uninstall removes only ours" || bad "uninstall removes only ours"

exit $fail
