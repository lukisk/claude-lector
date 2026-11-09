#!/bin/bash
# Registers (or with --uninstall removes) the Claude Lector UserPromptSubmit hook
# in ~/.claude/settings.json. Other settings and hooks are left untouched; a backup is written first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/capture-prompt.sh"
SETTINGS="$HOME/.claude/settings.json"
chmod +x "$HOOK"
mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"

# Remove our hook everywhere, then drop matcher groups left empty by that.
strip='
  if .hooks.UserPromptSubmit then
    .hooks.UserPromptSubmit |= (map(.hooks |= map(select(.command != $hook))) | map(select((.hooks | length) > 0)))
  else . end'

if [[ "${1-}" == "--uninstall" ]]; then
  filter="$strip"
  msg="Removed Claude Lector hook from $SETTINGS"
else
  filter="$strip | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks: [{type: \"command\", command: \$hook}]}])"
  msg="Installed Claude Lector hook in $SETTINGS"
fi

tmp=$(mktemp "$SETTINGS.XXXXXX")
jq --arg hook "$HOOK" "$filter" "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
echo "$msg"
