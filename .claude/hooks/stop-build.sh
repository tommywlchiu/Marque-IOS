#!/bin/bash
# Stop: if Swift files changed vs HEAD, compile the app once before Claude
# hands back. On failure exit 2 so Claude sees the errors and fixes them.
# DEVELOPER_DIR must be exported as its own statement (see Known Pitfalls).
input=$(cat)
# Already continuing because of this hook: don't loop forever.
echo "$input" | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin).get("stop_hook_active") else 1)' && exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git status --porcelain 2>/dev/null | grep -qE '\.swift$' || exit 0
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
log=$(mktemp)
if ! xcodebuild build -project Marque.xcodeproj -scheme Marque \
     -destination 'generic/platform=iOS Simulator' \
     -derivedDataPath /tmp/marque-hook-build CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
  { echo "xcodebuild failed after Swift edits:"; grep -E 'error:' "$log" | sort -u | head -20; } >&2
  rm -f "$log"; exit 2
fi
rm -f "$log"
