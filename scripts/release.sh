#!/bin/bash
# release.sh — TestFlight builds, in two steps (main is protected, so the
# build-number bump goes through a PR like any other change):
#
#   scripts/release.sh prepare   branch release/<version>-<build+1>, bump
#                                CURRENT_PROJECT_VERSION, push, open a PR
#   scripts/release.sh ship      on main after that PR merged: preflight,
#                                archive (Release), verify the archive, export
#                                + upload to App Store Connect, tag v<ver>-<build>
#
# `ship` refuses to run unless main is clean, matches origin, and CI passed
# for that exact commit. Upload needs the Apple Distribution certificate in
# the login keychain (team 7DZTSZ3299); -allowProvisioningUpdates lets Xcode
# create the profile. The .claude/skills/release skill wraps this.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PBX=Marque.xcodeproj/project.pbxproj
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

die() { echo "release: $*" >&2; exit 1; }
build_number() { grep -oE 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBX" | grep -oE '[0-9]+' | sort -u; }
marketing_version() { grep -oE 'MARKETING_VERSION = [0-9.]+;' "$PBX" | grep -oE '[0-9.]+[0-9]' | sort -u; }

[ "$(build_number | wc -l | tr -d ' ')" = 1 ] || die "targets disagree on CURRENT_PROJECT_VERSION: $(build_number | tr '\n' ' ')"
VERSION=$(marketing_version | tail -1); BUILD=$(build_number)

case "${1:-}" in
prepare)
  git diff --quiet && git diff --cached --quiet || die "working tree not clean"
  git fetch -q origin main
  git checkout -q -B "release/$VERSION-$((BUILD + 1))" origin/main
  NEXT=$((BUILD + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION = $BUILD;/CURRENT_PROJECT_VERSION = $NEXT;/" "$PBX"
  [ "$(build_number)" = "$NEXT" ] || die "bump failed"
  git commit -qam "Bump build to $VERSION ($NEXT)"
  git push -q -u origin HEAD
  gh pr create --base main --title "Release $VERSION ($NEXT)" \
    --body "Build-number bump for TestFlight $VERSION ($NEXT). After merge: \`scripts/release.sh ship\` on main."
  ;;

ship)
  # Preflight: exactly the commit CI passed, nothing local.
  [ "$(git branch --show-current)" = main ] || die "ship from main (git checkout main && git pull)"
  git diff --quiet && git diff --cached --quiet || die "working tree not clean"
  git fetch -q origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not origin/main — pull first"
  SHA=$(git rev-parse HEAD)
  CI=$(gh run list --workflow ci.yml --commit "$SHA" --json conclusion,status --jq '[.[] | select(.status=="completed")][0].conclusion // "none"')
  [ "$CI" = success ] || die "CI for $SHA is '$CI', not success"
  git rev-parse -q --verify "refs/tags/v$VERSION-$BUILD" >/dev/null && die "v$VERSION-$BUILD already tagged — run prepare first"
  python3 scripts/check_pitfalls.py

  OUT=/tmp/marque-release-$VERSION-$BUILD
  rm -rf "$OUT"; mkdir -p "$OUT"
  echo "release: archiving $VERSION ($BUILD) at $SHA"
  xcodebuild -project Marque.xcodeproj -scheme Marque -configuration Release \
    -destination "generic/platform=iOS" -archivePath "$OUT/Marque.xcarchive" \
    -derivedDataPath "$OUT/DerivedData" -allowProvisioningUpdates archive > "$OUT/archive.log" 2>&1 \
    || { tail -30 "$OUT/archive.log"; die "archive failed (log: $OUT/archive.log)"; }

  # Verify the archive before anything leaves the machine.
  APP="$OUT/Marque.xcarchive/Products/Applications/Marque.app"
  PB=/usr/libexec/PlistBuddy
  [ "$($PB -c 'Print CFBundleIdentifier' "$APP/Info.plist")" = com.tommychiu.marque ] || die "bundle ID"
  [ "$($PB -c 'Print CFBundleVersion' "$APP/Info.plist")" = "$BUILD" ] || die "CFBundleVersion is not $BUILD"
  [ "$($PB -c 'Print CFBundleShortVersionString' "$APP/Info.plist")" = "$VERSION" ] || die "version is not $VERSION"
  [ "$($PB -c 'Print ITSAppUsesNonExemptEncryption' "$APP/Info.plist")" = false ] || die "ITSAppUsesNonExemptEncryption"
  [ -f "$APP/PrivacyInfo.xcprivacy" ] || die "PrivacyInfo.xcprivacy missing from the app"
  WIDGET="$APP/PlugIns/MarqueWidgetExtension.appex/Info.plist"
  [ "$($PB -c 'Print CFBundleVersion' "$WIDGET")" = "$BUILD" ] || die "widget CFBundleVersion differs from the app's"
  [ ! -d "$APP/PlugIns/MarqueTests.xctest" ] || die "test bundle inside the app"
  echo "release: archive verified"

  cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>7DZTSZ3299</string>
<key>signingStyle</key><string>automatic</string>
<key>destination</key><string>upload</string>
</dict></plist>
PLIST
  echo "release: exporting + uploading"
  xcodebuild -exportArchive -archivePath "$OUT/Marque.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates > "$OUT/upload.log" 2>&1 \
    || { tail -30 "$OUT/upload.log"; die "export/upload failed (log: $OUT/upload.log)"; }
  grep -q "Upload succeeded\|EXPORT SUCCEEDED" "$OUT/upload.log" || die "no upload confirmation in $OUT/upload.log"

  git tag -a "v$VERSION-$BUILD" -m "TestFlight $VERSION ($BUILD)" "$SHA"
  git push -q origin "v$VERSION-$BUILD"
  echo "release: uploaded $VERSION ($BUILD), tagged v$VERSION-$BUILD. Apple processes it in minutes to ~1 h; then add it to the TestFlight groups."
  ;;

*) die "usage: scripts/release.sh prepare | ship" ;;
esac
