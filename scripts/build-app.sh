#!/bin/bash
# Builds "Claude Lector.app" (release), ad-hoc signs it and copies it to ~/Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product ClaudeLector
BIN="$(swift build -c release --show-bin-path)/ClaudeLector"
APP="$ROOT/build/Claude Lector.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeLector"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - --deep "$APP"
codesign --verify "$APP"
mkdir -p "$HOME/Applications"
# Quit a running copy so the new build replaces it cleanly.
osascript -e 'tell application id "cz.lukisk.ClaudeLector" to quit' >/dev/null 2>&1 || true
rm -rf "$HOME/Applications/Claude Lector.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed $HOME/Applications/Claude Lector.app"
