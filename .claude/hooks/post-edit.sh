#!/bin/bash
# PostToolUse (Edit|Write): after a source edit, run the fast deterministic
# checks. Exit 2 feeds the output back to Claude.
f=$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
case "$f" in
  *.swift|*.ts|*.rules|*.py) ;;
  *) exit 0 ;;
esac
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
fail=""
out=$(python3 scripts/check_pitfalls.py 2>&1) || fail="$out"
if [[ "$f" == *.swift && -f "$f" ]] && command -v swiftlint >/dev/null; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  # Only error-severity findings block; warnings are ignored.
  lint=$(swiftlint lint --quiet "$f" 2>&1 | grep ' error:')
  [ -n "$lint" ] && fail="$fail"$'\n'"$lint"
fi
[ -n "$fail" ] && { echo "$fail" >&2; exit 2; }
exit 0
