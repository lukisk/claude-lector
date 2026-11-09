# Claude Lector

A quiet macOS menu bar app that checks the English of every prompt you send in
Claude Code and shows the mistakes with one-line explanations.

## How it works

1. A global `UserPromptSubmit` hook (`hooks/capture-prompt.sh`) appends each prompt as one
   JSON line to `~/Library/Application Support/ClaudeLector/inbox.jsonl` and exits. It prints
   nothing and never blocks or changes the prompt.
2. The app picks up the inbox, skips what isn't your English (non-English, slash commands,
   very short prompts, logs/stack traces, pasted content, headless `claude -p`/SDK runs),
   strips code, paths and URLs, and checks the rest with the configured engine.
3. Mistakes show up in the menu bar popover: your text with highlights, the corrected
   version, and one sentence per mistake. The badge counts unseen prompts with grammar
   mistakes.
4. **Open window** in the popover opens the full history: a searchable list (All / With
   mistakes / Grammar only) and a large detail view with each mistake as a card. While the
   window is open the app shows in the Dock and Cmd-Tab.
5. **Quick check**: type or paste any sentence into the field at the top of the popover or the
   window and press ⌘↩. **⌥⌘L** opens a quick-check window from any app. Manual checks are kept
   in history under the project "manual" and don't count toward the badge.

## Install

```bash
./scripts/build-app.sh          # builds, ad-hoc signs, copies to ~/Applications
open ~/Applications/Claude\ Lector.app
./scripts/install-hook.sh       # adds the hook to ~/.claude/settings.json (backup written)
```

Uninstall the hook with `./scripts/install-hook.sh --uninstall`.

## Engine configuration

`~/.config/claude-lector/config.json` (keep it `chmod 600`). Without the file the app uses
your Claude subscription through `claude -p` with Haiku.

```json
{
  "engine": "proxy",
  "subscription": { "model": "haiku" },
  "proxy": {
    "base_url": "https://llm-proxy.example.com",
    "token": "…",
    "token_header": "x-api-key",
    "model": "claude-haiku-4-5"
  }
}
```

- `engine`: `subscription` (`claude -p`, hooks disabled, no session saved) or `proxy`
  (Anthropic Messages API at `<base_url>/v1/messages`).
- `token_header` is optional; without it the token is sent as `Authorization: Bearer`.
- After editing, click **Reload config** in the popover.

### Trying another model

```bash
swift run LectorSpike --limit 25            # configured engine vs. subscription · haiku
swift run LectorSpike --config other.json   # any config file
```

It checks your 25 most recent English prompts from `~/.claude/projects` with both engines and
writes `spike/report.md`. Look for candidate-only grammar issues: those are likely false
corrections.

## Data

- Inbox: `~/Library/Application Support/ClaudeLector/inbox.jsonl`
- History: `~/Library/Application Support/ClaudeLector/history.store` (SwiftData; **Clear history** in the popover)

## Development

```bash
swift test                                   # core logic (Swift Testing)
bash tests/hooks/test-capture-prompt.sh      # hook
bash tests/scripts/test-install-hook.sh      # installer
```
