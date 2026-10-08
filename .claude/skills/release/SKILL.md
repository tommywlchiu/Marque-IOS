---
name: release
description: Ship a TestFlight build of Marque — bump the build number through a PR, then archive, verify and upload the merged main commit with scripts/release.sh. Use when the owner asks for a TestFlight build, a release, or to "ship" app changes.
---

# Release a TestFlight build

Everything mechanical is in `scripts/release.sh`; this is the order and the judgment around it. Uploading is outward-facing: do it only with the owner's go-ahead (given per release or for the session).

## 1. Decide what ships
- `git log --oneline $(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo HEAD~20)..origin/main` — what's new since the last tagged build (tags are `v<version>-<build>`; builds before 6 predate tagging — the last untagged one was 1.0 (5), 2026-09-30).
- Anything that needs a backend deploy *first* (new callable, rules, hosting catalog the app expects)? Deploy it before the build reaches testers — use the `deploy` skill.

## 2. Bump through a PR
```bash
scripts/release.sh prepare
```
Opens `release/<version>-<build+1>` with only the bump. Wait for CI (`gh pr checks <n> --watch`), then `gh pr merge <n> --merge --delete-branch`.

## 3. Archive, verify, upload, tag
```bash
git checkout main && git pull --ff-only
scripts/release.sh ship
```
It refuses unless `main` == `origin/main`, the tree is clean and CI passed for that exact commit. It checks the archived Info.plist (bundle ID, version, build, `ITSAppUsesNonExemptEncryption = false`), `PrivacyInfo.xcprivacy`, that the widget's build matches the app's and that no test bundle leaked in — then uploads and tags `v<version>-<build>`. Logs: `/tmp/marque-release-<version>-<build>/`.

Known noise: dSYM "Upload Symbols Failed" warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, openssl_grpc (precompiled third-party frameworks) — harmless.

## 4. After upload
- Apple processes the build (minutes to ~1 h). The owner adds it to TestFlight groups in App Store Connect ("MarqueHQ", Apple ID 6812103249) — there's no CLI for that here.
- Report: version/build, the commit and tag, the change list from step 1, and anything not verified on a real device.
- If an upload is rejected for a duplicate build number, the bump didn't merge — run `prepare` again.
