# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Marque is an iOS app (SwiftUI, iOS 17.6+, Swift 5, bundle ID `com.tommychiu.marque`) for car owners to manage, track, and share vehicle information. It combines a private garage tool (service history, document expiry alerts, expense tracking), a social layer (public profiles, follows, block/report), and an AI assistant (Marque Assistant, v1.1, behind a Remote Config flag).

Product source of truth: `docs/Marque-PRD.md` (v1.2). Cite FR/EC/US identifiers from it when discussing intended behavior.

---

# Working Protocol

## The team

| Role | Agent | Owns | Never touches |
|---|---|---|---|
| **Orchestrator** | main session | Decomposition, delegation, review, integration, git, user communication | — |
| **Frontend** | `frontend` | `Features/**`, `Views/**`, `Components/**` | Stores, Models, functions, rules |
| **Backend** | `backend` | `functions/**`, `firestore.rules`, `firebase.json`, `Stores/**`, `Models/**` | SwiftUI view bodies |
| **QA** | `qa` | Verification, edge-case audit vs. PRD, test harnesses | **All production code — read-only.** Reports defects, does not fix them |

Definitions live in `.claude/agents/*.md`. Agents are `sonnet` by default; bump to `opus` in the frontmatter for reasoning-heavy work.

**Ownership is exclusive.** No file has two owners. A task spanning both domains gets split, not shared.

## Delegation rules

**Delegate when** the task sits squarely in one agent's domain and needs several file reads or edits.

**Do it yourself when** it's a one-line change, a single file read, or a question. A subagent starts cold and re-derives context you already have — that cost only pays off on real work.

**Parallel dispatch requires disjoint file sets.** Assign file ownership explicitly in the dispatch prompt. If two agents would touch the same file, run them sequentially instead. If B depends on A's output, sequence them.

**Never delegate a deploy.** See Key Conventions.

## Review gate (orchestrator — mandatory)

Before reporting delegated work as done:

1. **Read the actual changed files.** Never accept an agent's summary as evidence — summaries overstate, and the gap between "what I did" and "what the diff says" is where real bugs live.
2. **Verify the claim matches the diff**, including the parts the agent didn't mention.
3. **Check the change against Known Pitfalls** below.
4. **Consider a `qa` pass** for anything touching auth, deletion cascades, security rules, PII, or money.
5. **Report honestly** — state what was verified and what was not. Never imply verification you didn't perform.

This gate is not ceremony. It has caught a non-terminating loop and a build compiling the wrong file, both of which the implementing agent reported as clean.

## Self-Correction Protocol

**Triggers** — any one of these fires the protocol:
- The user corrects a factual claim you made
- A build or verification fails after it was reported as passing
- The review gate finds a defect in delegated work
- A rule in this file or in `.claude/agents/*.md` turns out to be false

**Response, in order:**
1. Fix the immediate problem.
2. Ask: *would a written rule have prevented this?* If no — stop here. Not every mistake generalizes.
3. If yes — add an entry to **Known Pitfalls** in the format below.
4. If the root cause was a **stale fact** in this file or an agent definition, fix that file in the same pass. Documentation that lies is worse than documentation that's missing, because agents act on it confidently.

**Entry format** (all three lines required):
```
### <short imperative title>
- **Rule** — specific and falsifiable. "Be careful with X" is not a rule.
- **Why** — the actual incident, one line.
- **Detect** — a command or check that surfaces it.
```

**Do not add** entries for: anything the compiler or type-checker already catches, one-off typos, or restatements of an existing entry (sharpen the existing one instead).

**Pruning** — cap this list around 15 entries. When adding beyond that, remove entries that are now enforced by code, or that haven't been relevant in months. Note removals in the commit message.

**Where knowledge goes:** project rules that apply to anyone working this repo → this file (checked into git). User-specific working preferences and cross-session context → the memory directory. Don't cross the streams.

---

# Known Pitfalls

Learned the hard way. Each one cost real debugging time.

### Xcode compiles the pbxproj path, not the file you're reading
- **Rule** — Before deleting or trusting a duplicate `.swift` file, grep `project.pbxproj` for the filename and check which `path =` it resolves to. Two files with the same struct name at different paths will not necessarily error; Xcode silently compiles one.
- **Why** — Two `MarqueChatView.swift` existed; Xcode was compiling the older one, which was missing the `FeatureFlagsStore` gate. Reading the canonical file showed correct code that was never being built.
- **Detect** — `grep -n "Filename.swift" Marque.xcodeproj/project.pbxproj`

### A swallowed error inside a retry loop is an infinite loop
- **Rule** — Any `while` loop whose exit condition depends on a mutation must not swallow that mutation's failure. Use `guard (try? await op()) != nil else { break }`, not bare `try? await op()`.
- **Why** — The message-deletion pager re-queried the same 500 docs forever if the batch commit kept failing, hanging `deleteAccount()`.
- **Detect** — Grep for `try?` inside `while` bodies in `Stores/**`.

### `npm audit fix` does nothing for transitive dependencies
- **Rule** — For CVEs inside the `firebase-admin` / `firebase-functions` trees, add an `overrides` entry in `functions/package.json`. Don't rely on `npm audit fix`; it only bumps direct dependencies.
- **Why** — `npm audit fix` cleared 1 of 12 CVEs. Overrides on `uuid` and `qs` cleared the remaining 11 to zero.
- **Detect** — `cd functions && npm audit` after any dependency change.

### Xcode fails a build on the literal text `error:` in a Run Script phase, independent of its exit code
- **Rule** — Xcode scans a Run Script build phase's raw stdout/stderr for a line starting with `error:` and fails the whole build/archive on sight of it, even if the phase's own process exits `0`. Making a flaky script "non-fatal" needs two things, not one: zero the exit code (`cmd || true`) *and* keep the underlying tool's own `error:`-prefixed output from ever reaching the log — redirect it to a file and emit your own `note:`/`warning:`-prefixed line instead. Fixing only the exit code still fails the build; Xcode's own log even says so ("emitted errors but did not return a nonzero exit code to indicate failure") while still marking it failed.
- **Why** — The Crashlytics symbol-upload script hits an open, unresolved `firebase-ios-sdk` bug on every Release archive (`Could not get GOOGLE_APP_ID...`, archive-only, `GoogleService-Info.plist` correctly bundled). The first fix (`cmd || echo "warning: ..."`) still failed the archive, because the underlying tool's own `error:` line printed before the `||` fallback ran.
- **Detect** — Grep a failing Run Script phase's raw output (not just its exit code) for `error:`; if found, the phase must redirect that command's own stdout/stderr rather than let it print directly.

### A date-only string parsed by `ISO8601DateFormatter` is UTC midnight, not local
- **Rule** — `ISO8601DateFormatter` with `.withFullDate` parses `"yyyy-MM-dd"` as midnight **UTC**. Every date-consuming call in this app (`.formatted()`, `Calendar.current` reminder math in `NotificationManager`, DatePicker input) reads dates in the **device's local calendar**. Never hand a UTC-midnight `Date` to those directly — re-anchor it first: pull `[.year, .month, .day]` via a UTC-timezone `Calendar`, then rebuild the `Date` via `Calendar.current.date(from:)`. Same care in reverse when encoding a local `Date` back to a date-only string for the server — use a `DateFormatter` with `timeZone = .current`, not `ISO8601DateFormatter`'s UTC default.
- **Why** — `DocumentScanService.parseISODate` and `AIServiceSuggestionService` (both directions) skipped the re-anchor. A real driver's license and insurance card, scanned on a real device in Pacific time, both showed their expiry date one day earlier than printed — and `NotificationManager`'s 30-day/7-day/on-day expiry reminders would have fired a day early too, silently, for the whole US-timezone user base.
- **Detect** — `grep -rn "ISO8601DateFormatter" Marque --include='*.swift'`; every `.date(from:)` result must be re-anchored before use, every `.string(from:)` call must go through a `.current`-timezone formatter.

### `DEVELOPER_DIR` must be exported, not inline-prefixed
- **Rule** — This machine's `xcode-select` points at CommandLineTools, so both `xcodebuild` and `xcrun` fail without `DEVELOPER_DIR`. It must be `export`ed as its own statement first. `DEVELOPER_DIR=... xcodebuild -destination "...$(xcrun ...)"` does **not** work: the shell expands the subshell before applying the command-prefix assignment, so `xcrun` runs without it, returns empty, and `xcodebuild` gets a malformed destination and silently dumps its help text instead of building. Also pass `-derivedDataPath` to a scratch dir — Xcode locks the default when open.
- **Why** — The first fix for the hardcoded-simulator pitfall used the inline-prefix one-liner. It looked correct, was committed to three files, and produced a help dump rather than a build on the first run.
- **Detect** — `xcode-select -p`. If a build prints flag documentation instead of compiling, the destination is malformed — echo the resolved `$SIM` and check it isn't empty.

### Image sizes are points until you multiply by scale
- **Rule** — Any resize with a pixel budget must measure `image.size * image.scale` and render with a `UIGraphicsImageRendererFormat` whose `scale = 1`. `UIImage.size` is in points and `UIGraphicsImageRenderer` defaults to the screen scale (3x), so a points-based "max 2000" writes 6000px files. Verify a resize by reading the written file's pixel dimensions, not the code.
- **Why** — `ImageManager.downscaled` shipped (through agent review and orchestrator review) writing 6000×4004 JPEGs for a 2000px cap, and its load-time "migration" re-saved them at 6000px on every load. Caught only by `sips` on the Simulator's `Documents/CarPhotos`.
- **Detect** — `grep -rn "UIGraphicsImageRenderer(" Marque` — every call must pass a format with `scale = 1` when the target is a pixel size; then `sips -g pixelWidth -g pixelHeight` on a freshly saved file.

### `AuthErrorCode(_bridgedNSError:)` returns nil for every real Firebase Auth error
- **Rule** — Never map a Firebase Auth error with `AuthErrorCode(_bridgedNSError:)`. Use `AuthService.authErrorCode(_:)`, which checks `ns.domain == AuthErrors.domain` and then builds `AuthErrorCode(rawValue: ns.code)`. `AuthErrorCode` is a Swift `@objc` enum whose bridged domain is its own type name, not `FIRAuthErrorDomain`, so the bridging initializer never matches a real error.
- **Why** — Every `switch`/`==` on the bridged code silently fell through: a wrong password showed Firebase's raw "The supplied auth credential is malformed or has expired", and the EC-05 collision checks (`emailAlreadyInUse`, `accountExistsWithDifferentCredential`) never fired from these paths. Found only by seeing the raw text on the redesigned login screen.
- **Detect** — `grep -rn "_bridgedNSError" Marque` must return nothing (outside the comment on the helper).

### Firestore does not cascade subcollection deletes
- **Rule** — Deleting a document orphans its subcollections; they stay queryable. Walk and delete children first, then the parent. Batches cap at 500 ops.
- **Why** — `deleteAccount` left `conversations/` and `usage/` behind, violating FR-10.15 / EC-22 and leaving user data after deletion.
- **Detect** — Cross-check every `users/{uid}/` subcollection against `AuthService.deleteAccount` and `onAuthUserDeleted`.

### New subcollections default to deny
- **Rule** — `firestore.rules` has no wildcard under `users/{userId}/` — it was removed deliberately so `usage/` could be server-only. Adding a subcollection without adding its rule means every client write silently fails.
- **Why** — The client-side `usage/` cleanup fails with `PERMISSION_DENIED`, swallowed by `try?`. Correct behavior, but only discoverable by reading the rules.
- **Detect** — `grep -n "match /users" firestore.rules` against the paths your change writes to.

### `allow create, update` silently denies delete
- **Rule** — Firestore decomposes `write` into `create`/`update`/`delete`. A rule enumerating only some verbs denies the rest. Never infer delete permission from the presence of a write grant — read the actual verb list. And check *which principal* the rule binds: `followers/` binds the follower, `following/` binds the path owner, so neither is deletable by the account owner.
- **Why** — `deleteAccount` appeared to work while leaving the `users/{uid}` profile doc, `followers/**`, `notifications/**`, and every reverse follow pointer in Firestore. All four denials were swallowed by `try?`. The profile doc stayed world-readable to any signed-in user after "deletion".
- **Detect** — For every path your code writes or deletes, find its `match` block and read the verb list and the principal: `grep -n "match /" firestore.rules`. Anything the client cannot delete belongs in `onAuthUserDeleted`, which uses the Admin SDK and bypasses rules.

### Audit every write path against the rules, not just the new ones
- **Rule** — When reviewing a change that touches Firestore access, enumerate *all* collection paths the affected code touches and check each against `firestore.rules`. Checking only the paths the diff adds is not sufficient.
- **Why** — The review gate on the deletion-cascade commit verified that the two new subcollections had rules, and passed it. Four pre-existing paths in the same function were silently denied and shipped as fixed. A separate QA pass caught it; the orchestrator review did not.
- **Detect** — `grep -rn 'collection("' Marque/ functions/src/ | grep -oE 'collection\("[^"]+"\)' | sort -u` then cross-check each against `firestore.rules` and against both deletion paths.

### A retry that destroys its own inputs reports success
- **Rule** — "Every step is idempotent" is a claim about individual operations, not about the function. Before enabling retries, ask what the *second* run reads. If an earlier run deleted the state a later phase depends on, the retry does nothing, finds no errors, and exits green — worse than no retry, because it looks like it worked. Order destructive work so the widest-blast-radius delete happens **last**, and abort before it if any earlier phase failed.
- **Why** — `onAuthUserDeleted` ran `recursiveDelete(users/{uid})` even when reverse-pointer cleanup had failed. The retry then read empty follower lists, cleaned nothing, and reported success — leaving ghost pointers permanently. The same shape burned the username reservation: once the profile doc was gone, the retry could no longer read the username it needed to release.
- **Detect** — For every phase in a retryable function, list what it reads and what it deletes. Any phase that deletes something an earlier phase read is a retry hazard.

### A constant that "looks right" still needs checking against the actual build artifact
- **Rule** — Never assert a bundle ID, app ID, or similar identifying constant in code or docs without checking it against the real source: `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`, or `CFBundleIdentifier` in the built `Info.plist`. A value that reads as plausible — especially one matching the product's own name — is not evidence it's correct.
- **Why** — `CLAUDE.md`, every agent brief, and the Cloud Functions `BUNDLE_ID` constant all asserted `com.marque.app` for the entire session. The real bundle ID, set in the very first commit, is `com.tommychiu.marque`. This silently broke `SignedDataVerifier`'s bundle-ID check on every production and sandbox verification, on top of the separate `appAppleId` constructor bug found the same week — two independent reasons the same code path never worked, neither visible from reading the code alone.
- **Detect** — `grep PRODUCT_BUNDLE_IDENTIFIER Marque.xcodeproj/project.pbxproj` and diff against any hardcoded bundle ID elsewhere in the repo. For `APP_STORE_APP_ID` in `functions/src/index.ts`, ask the owner to read App Store Connect > App Information > Apple ID; nothing in the repo or in sandbox testing can confirm it.
- **Again** — `APP_STORE_APP_ID` was `6763424467` under a comment saying it was confirmed from App Store Connect. The real Apple ID is `6812103249` (owner, 2026-09-30). Sandbox/TestFlight never checks it, so only the first live purchase would have failed.
- **Also** — the same goes for a third-party config value (an entitlement, a console setting, a flag): read the vendor's own doc for *this* integration before writing it, don't reason from the general convention. `appattest-environment` was set to `development` (Apple's usual dev value) when Firebase App Check requires `production` and rejects sandbox attestations; caught by reading the Firebase page before telling the user how to register.

### A cap keyed by a client-supplied value is not a cap
- **Rule** — Any counter whose document ID or bucket key comes from the request (`usage/scans_{clientDate}`, `usage/assistant_{clientDate}`) must have that key validated against server state before use. Bound it to the server clock (±1 UTC day covers UTC-12..UTC+14). Checking only the *shape* of the key (a regex) lets a client mint a fresh allowance per call by sending a new key each time.
- **Why** — `askMarque` and `withScanAllowance` only matched `clientDate` against `\d{4}-\d{2}-\d{2}`, so a modified client could send a new date per call and get unlimited Anthropic calls on a free account (it even accepted `9999-99-99`). The implementer copied the same shape into the new scan code; a QA pass caught it, not the review that shipped `askMarque`.
- **Detect** — `grep -n "clientDate" functions/src/index.ts` — every use as a Firestore doc ID must go through `assertPlausibleClientDate` first.

### A hand-written Xcode scheme can crash Xcode on open, and `xcodebuild` won't tell you
- **Rule** — Never hand-write or hand-edit an `.xcscheme` (or anything else Xcode loads when it opens the project) in a location the user's Xcode will read. The StoreKit reference in particular (`StoreKitConfigurationFileReference identifier`) must be a **relative** path; an absolute one aborts Xcode. Have Xcode's scheme editor write it, or try the file first on a scratch copy of the project (`cp -R` to `/tmp`), never in the live checkout.
- **Why** — A local scheme with an absolute `.storekit` path passed `xcodebuild -list`, but crashed the user's Xcode on every open (five crash reports in three minutes) with `dvt_stringByMakingAbsolutePathWithBasePath:` asserting inside `IDESchemeOptionReference.resolvedReference`. It was invisible while their already-running Xcode session hadn't rescanned, and fatal on the restart.
- **Detect** — `ls -t ~/Library/Logs/DiagnosticReports | grep '^Xcode'`; an `.ips` whose crashed thread has `IDESchemeOptionReference` is this. Removing the scheme file from `<project>.xcodeproj/xcuserdata/*/xcschemes/` restores the project. Note a user scheme also hides the auto-generated default `Marque` scheme from `xcodebuild -list`, breaking the build command above.

### Rules tests must use values copied from production, not hand-typed ones
- **Rule** — Any rule that pattern-matches a URL or ID needs at least one test whose value is copied verbatim from a real production document. The iOS SDK's Storage `downloadURL()` includes `:443` (`https://firebasestorage.googleapis.com:443/...`); an emulator URL (`127.0.0.1:9199`) or a hand-typed one does not.
- **Why** — `storageObjectPrefix()` matched only the portless host. 203 emulator tests passed, and after the deploy every production publish carrying an avatar or photo URL was denied.
- **Detect** — Read one real `publicCars` doc (Firebase MCP `firestore_get_document`) and check its URL fields against each `matches(` pattern in `firestore.rules`.

### Documentation drifts silently and agents act on it
- **Rule** — When you change an architectural pattern, update `CLAUDE.md` **and** every `.claude/agents/*.md` that repeats the claim, in the same change.
- **Why** — Both this file and both agent definitions asserted a `#if canImport(FirebaseCore)` mock-branch pattern for ~4 months after it was removed. Agents were being briefed with a false architecture.
- **Detect** — `grep -rn "canImport\|UserDefaults\|5 tabs" CLAUDE.md .claude/agents/`

---

# Build & Run

Build and run through **Xcode** — open `Marque.xcodeproj`. One native target, no XCTest bundle, no `test` script in `functions/`. The only automated tests are the **security-rules suites** in `tests/rules/` (Firestore + Storage, run against the emulators; needs Java, e.g. `export PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH`): `cd tests/rules && npm install && npm test`. Run them after any change to `firestore.rules` or `storage.rules`, and add cases for every new rule. They use their own emulator ports (8180/9189), so they don't clash with a running dev emulator. Three SPM packages: `firebase-ios-sdk` (linked products `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseFunctions`, `FirebaseRemoteConfig`, `FirebaseCrashlytics`), `GoogleSignIn-iOS` (`GoogleSignIn`, `GoogleSignInSwift`), and `posthog-ios` @ 3.77.0 (`PostHog`).

The target has one Run Script build phase beyond the standard ones: **"Upload Crashlytics Symbols"**, which invokes the SPM-vendored `Crashlytics/run` script to upload dSYMs. It guards on `$CONFIGURATION` internally and exits immediately for anything but `Release` — Debug builds (including the `xcodebuild` command below) never make the network call. Don't remove that guard without confirming CI/local Debug builds still work offline. In `Release`, it redirects the underlying tool's own output to `${TEMP_DIR}/crashlytics-upload.log` and only echoes a `note:`-prefixed line on failure — never let that tool's raw output reach the build log directly. That's load-bearing, not cosmetic: `firebase-ios-sdk` has a known, open, unresolved bug (issues/11836) where this script can print `error: Could not get GOOGLE_APP_ID...` on an actual archive even with `GoogleService-Info.plist` correctly bundled, and Xcode fails the **whole archive** on any `error:`-prefixed line anywhere in a Run Script phase's output — independent of that phase's own exit code. Fixing only the exit code (`|| echo "warning: ..."`) is not enough; the raw text has to be kept out of the log entirely.

**Release archive** (TestFlight/App Store) — verified working end to end:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Marque.xcodeproj -scheme Marque -configuration Release \
  -destination "generic/platform=iOS" -archivePath /tmp/marque-release.xcarchive archive
```
No prior session had ever run this until 2026-09-22 — every build before that was Debug. `PrivacyInfo.xcprivacy` (app-level, `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` for the app's own direct `UserDefaults` use — re-check with `grep -rn "creationDate\|contentModificationDate\|systemUptime\|volumeAvailableCapacity" Marque --include='*.swift'` before assuming no other required-reason API category needs adding) must be present or App Store Connect can reject the binary at upload, TestFlight included, not just final review.

Command-line build. Copy this whole block — the three lines are load-bearing and verified working on this machine:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+' | tail -1)
xcodebuild -project Marque.xcodeproj -scheme Marque \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath /tmp/marque-verify
```
`export` must come first and be its own statement — see the pitfall below. `-derivedDataPath` avoids the lock Xcode holds on the default DerivedData when it's open.

**Local StoreKit testing** — `StoreKit/Marque.storekit` mirrors the two Pro products (`marque.pro.annual` $24.99, `marque.pro.monthly` $2.99, both family-shareable). There is deliberately no committed scheme for it: create one **through Xcode's own scheme editor** (Product ▸ Scheme ▸ Manage Schemes ▸ gear ▸ Duplicate, **untick Shared**, Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration ▸ Add StoreKit Configuration to Project… ▸ `StoreKit/Marque.storekit`), never by writing `.xcscheme` XML — see the pitfall on hand-written schemes. The scheme lands in gitignored `xcuserdata` (nothing about it is committed), **but while it exists `xcodebuild` no longer sees the auto-generated `Marque` scheme** — `xcodebuild -list` shows only `Marque StoreKit Test`, and the build command above fails with "does not contain a scheme named Marque". Use `-scheme "Marque StoreKit Test"` in that case (same target and Debug configuration; verified to build), or delete the local scheme (`rm "Marque.xcodeproj/xcuserdata/<you>.xcuserdatad/xcschemes/Marque StoreKit Test.xcscheme"`), which brings the default back. Check with `xcodebuild -list` when a build says a scheme is missing. What this can and can't show: a purchase made under it makes the *client* Pro (Garage PRO badge, `SubscriptionStore.isPro`) while the *server* stays free — `syncEntitlement` receives Xcode's locally-signed JWS, fails both Apple verifiers, and writes nothing (`syncEntitlement: unverifiable signedTransaction` in the logs; correct, since a local receipt must not grant Pro) — which is exactly the Family Sharing shape the Assistant cap and scan allowance must handle. Xcode's local testing **cannot simulate Family Sharing itself** (`ownershipType == .familyShared`, and the server's Family-Shared branch in `syncEntitlement`); that needs App Store sandbox testers with family-shareable products on a real device.

Cloud Functions live in `functions/` (TypeScript, `firebase-functions` v6). Build with `cd functions && npm run build`. **Never deploy (`firebase deploy`) without explicit user approval.**

# Architecture

## Navigation & Root State

`Marque.swift` bootstraps ten `@StateObject`s injected as environment objects: `CarStore`, `AuthService`, `ExploreStore`, `FollowStore`, `SubscriptionStore`, `BlockStore`, `NotificationStore`, `ChatStore`, `ScanAllowanceStore`, and `FeatureFlagsStore`. `RootView` drives top-level navigation:

```
Onboarding (once) → LoginView → VerifyEmailView (if email unverified)
                              → ProfileResolvingView (only while AuthService looks up an existing profile in Firestore)
                              → ProfileSetupView (if incomplete)
                              → AddCarView (onboarding mode, if needsFirstCarStep)
                              → MainTabView
```

`AddCarView` (onboarding mode) is FR-13's add-first-car step, gated by `AuthService.needsFirstCarStep`. It's session-local, not persisted: `completeProfileSetup()` sets it true, and either adding a car or tapping "Skip" (both routed through `completeFirstCarStep(addedCar:)`) sets it false and advances to `MainTabView`. An existing user never sees this step and no migration flag was needed: their `hasCompletedProfileSetup` is either already true locally, or — on a fresh install / new device, where the UserDefaults copy is gone — restored from Firestore by `AuthService.resolveProfileFromFirestore` before `RootView` routes (a non-empty `users/{uid}.username` means setup was completed; only `completeProfileSetup` and `changeUsername` write it, and the server can create a `users/{uid}` doc holding just `isPro`, so the doc merely *existing* is **not** the signal). While that lookup runs, `isResolvingProfile` holds `RootView` on `ProfileResolvingView`, with an 8 s backstop so it can never pin the user.

`MainTabView` currently has 3 tabs (Garage, an Add "+" tab, Explore). None of Notifications, Profile, or Settings are tab items — each is reached differently: **Settings** is a toolbar gear icon on Garage; **Notifications** is a toolbar bell icon on Explore; **Profile** isn't a toolbar item anywhere — it's the inline header on Garage (Edit Profile button, follower/following stat chips). The PRD's 5-tab layout (Garage / Explore / Notifications / Profile / Settings) is the eventual target; the current arrangement is a deliberate interim state.

## Stores

All stores are `@MainActor` classes. Firestore listeners are started/stopped in response to auth state changes (see `Marque_PrototypeApp.body`).

| Store | Responsibility |
|---|---|
| `CarStore` | User's cars — Firestore-backed with local persistence cache; propagates changes to `NotificationManager`. |
| `AuthService` | Firebase Auth (Apple, Google, Email + email verification). Owns profile extras: username/bio/location sync to Firestore `users/{uid}`; driver license fields live in UserDefaults only (`marque_profile_{uid}`) per FR-09.4. `hasCompletedProfileSetup` is UserDefaults-primary with a Firestore backstop (`resolveProfileFromFirestore`: non-empty `users/{uid}.username` = setup complete) so a reinstall or new device doesn't force an existing account back through Set Up Your Profile. `completeProfileSetup` never overwrites an existing `bio`, `createdAt`, `displayName` or `avatarURL` with an empty/fallback value. A username change or avatar upload copies `ownerUsername`/`ownerAvatarURL` onto the user's own `publicCars` (`updateOwnPublicCars`); only the owner can write those docs, so never backfill them from a viewer's client. |
| `ChatStore` | Marque Assistant conversations + messages at `users/{uid}/conversations/{convId}/messages/`. Also tracks today's message count (`usage/assistant_{date}`; the listener re-attaches on `NSCalendarDayChanged` / `didBecomeActive` when the local date has changed, so the counter never carries yesterday's count across midnight) and, like `ScanAllowanceStore`, follows the **server-side** plan (`users/{uid}.isPro`, not StoreKit's — FR-08.3; `serverIsPro` is `nil` until known) so the "n / 10 today" counter and the cap-reached copy match what `askMarque` enforces (10 free / 500 Pro; the client constants are display copies — change them together). A cap-reached `sendError` is sticky (it swaps the composer for the cap bar), so `clearStaleCapError()` clears it whenever the plan or count listener says the user is under today's cap — after upgrading from the bar (plan flips to Pro) or at midnight (count resets); the bar's *copy* is computed live from `serverIsPro`, so a stale error would otherwise tell a fresh Pro user they'd used all 500. Conversation management surfaces failures: `deleteConversation` pages through *all* messages (500 per batch) and deletes the parent doc **last** (Firestore doesn't cascade; a partial failure leaves the parent listed and retryable) and returns a `Bool`; `deleteConversation`/`togglePin` set `conversationActionError` (also the 10-pin limit), which the Conversations sheet shows as an alert. Automatic FR-10.19 cap enforcement only logs — the user didn't ask for that delete. |
| `SubscriptionStore` | StoreKit purchases + Firestore `isPro` sync for Pro tier. `isPro` is the *device's* StoreKit entitlement; `isFamilyShared` is true when that entitlement is Pro but not a direct purchase (Family Sharing) — such a member is Pro locally while the server withholds `users/{uid}.isPro`, so their Assistant/scan limits stay free. `ProUpgradeView` shows a no-CTA "already Pro" state only for a direct purchaser (`isPro && !isFamilyShared`); a Family Sharing member instead gets the same purchase flow as a non-Pro user, with the feature list trimmed to just Assistant/scans (FR-08.7 — they already have the other benefits) — the product decision to allow this was made 2026-09-21, since it needed no `SubscriptionStore` change (`refreshProStatus()` already prefers a direct `PURCHASED` transaction over a `FAMILY_SHARED` one when syncing). The Assistant cap bar has a matching "Pro on this device, free on the server" branch, unchanged by this. **Fixed 2026-09-21:** the Garage/Settings PRO badge (`AppUser.isProMember`) is set from an `isPro` change handler in `Marque_PrototypeApp`, but `load()` sets `isPro` before its `defer` sets `hasLoaded`, so a device already entitled at launch (Family Sharing, or a direct purchase StoreKit already recognizes) flipped `isPro` while the handler's `hasLoaded` guard was still false — the badge silently never appeared for that session. A second `onChange(of: subscriptionStore.hasLoaded)` now re-propagates `isPro` once loading is confirmed done, catching the missed flip without touching `SubscriptionStore`'s internal ordering. Verified on the Simulator: cold-launched with an already-active local Pro entitlement, the badge now appears immediately (previously confirmed absent under the same conditions before the fix). |
| `ExploreStore` | Public cars feed for Explore tab (Firestore listener on `publicCars`). |
| `FollowStore` | Following/followers subcollections. |
| `BlockStore` | Blocked users. |
| `NotificationStore` | In-app notification inbox (Firestore). |
| `ScanAllowanceStore` | FR-14.4 read-only listeners on `users/{uid}/usage/scans_{date}` (today's count) and `users/{uid}` (the **server-side** `isPro`, deliberately not StoreKit's — a Family Sharing member has local Pro but the server withholds the flag and enforces the free cap, so the caption must show the server's number). Drives the "n of M scans left today" caption and the pre-scan paywall gate; both hide/fail open while the plan is unknown. Display only; the parsers enforce. The usage listener re-attaches when the local day rolls over; the plan listener only if it died. |
| `LikeStore` | Current user's likes (collection-group listener on `likes` where `uid == me`); optimistic `toggleLike` with rollback. `likeCount`/`weeklyLikeCount` on `publicCars` are server-maintained. |
| `CommentStore` | One car's comments listener (newest 100), `post`/`delete`/`report`. Retries on permission-denied (a car just made public races its own public doc). Client `CommentFilter` mirrors `functions/src/commentFilter.ts` — the server is authoritative; edit both together. |
| `PushStore` | FCM token at `users/{uid}/devices/{token}` and per-type preferences at `users/{uid}/settings/notifications`. Sign-out awaits the token delete (≤3 s) via `AuthService.willSignOut`. |
| `FeatureFlagsStore` | Firebase Remote Config gate (e.g. `marque_assistant_enabled`, default false). DEBUG builds only: launching with `-marque_assistant_enabled_override YES` (or `NO`) forces the flag locally without touching production config — compiled out of Release. |

## Firebase

**Local emulator suite (Debug only).** Launch a Debug build with `-use_firebase_emulators YES` and it talks to `firebase emulators:start --only auth,firestore,storage,functions` on 127.0.0.1 (ports in `firebase.json`). Functions need `functions/.secret.local` with a placeholder `ANTHROPIC_API_KEY` (gitignored). A macOS "SimulatorTrampoline wants the Microphone" dialog sits over the Simulator window and silently eats clicks until answered.

Firebase iOS SDK is a required build dependency. `FirebaseApp.configure()` runs unguarded in `Marque_PrototypeApp.init()`; Firestore offline persistence is enabled with a 100MB cache.

An earlier `#if canImport(FirebaseCore)` conditional-compilation pattern with `#else` mock branches existed until May 2026 and was removed when Firebase became a hard dependency. **Do not reintroduce it.** Two vestigial `#if canImport(FirebaseAuth)` guards remain in `Models/AppUser.swift` (lines 2 and 50) — dead code, safe to strip.

**App Check** — **enforced on the five AI callables since 2026-09-21** (client and server both in). `Marque.swift` registers `MarqueAppCheckProviderFactory` *before* `FirebaseApp.configure()`: the debug provider on the Simulator (`#if targetEnvironment(simulator)`), App Attest everywhere else — keyed on the Simulator and **not** on `DEBUG`, so a Debug build on a real device exercises App Attest and a Release build can never fall back to the debug provider. `FirebaseAppCheck` is linked in the pbxproj and `Marque-Prototype.entitlements` carries `com.apple.developer.devicecheck.appattest-environment = production` — **not** `development`: Firebase's docs require `production` and say App Check does not accept tokens from the App Attest sandbox, so `development` would make every on-device attestation fail. On the server, `askMarque`, the three parsers and `suggestServiceReminders` carry `enforceAppCheck: ENFORCE_APP_CHECK`, a constant in `functions/src/index.ts` that is now `true` (deployed). It was turned on only after the app was registered for App Attest in the Firebase console and both the Simulator (debug token) and a real iPhone (App Attest) logged `verifications.app = "VALID"`. Verified against production: a signed-in account with no App Check header, or a forged one, gets `401 UNAUTHENTICATED` from all five (before enforcement the same unverified account got `PERMISSION_DENIED` from the verified-email gate, so the error code tells the two gates apart). **A client build without App Check tokens loses these five features; a freshly erased Simulator needs its new debug token registered.** If a legitimate client is rejected, set the constant back to `false` and redeploy. Reading the logs while unenforced: `MISSING` = no token sent; `INVALID` = a token was sent but is bad — including the SDK's *placeholder* token, which the Functions SDK sends when a fetch fails (console not set up, attestation failure), because a failed fetch never blocks the call; `VALID` = working. Flipping the constant either way is a deploy and needs explicit user approval. The SDK also attaches tokens to Firestore/Storage/Auth requests; enforcing those is a separate per-product console toggle — don't, until `VALID` has been seen. `getAppAccountToken` and `syncEntitlement` are candidates for `enforceAppCheck` later. The Simulator's debug token is printed to the console on first launch — register it in the console, and never commit it.

## Data Model Relationships

- `Car` embeds `[MaintenanceRecord]`, `[ServiceReminder]` and `[CarMod]` directly (not normalized). `CarMod.notes` is private; `PublicCarMod` carries only category/name/brand. `Car.maxMods`, `PublicCar.maxMods` and the rules' `validMods` (`size() <= 30`) must change together.
- `Car.photoFileNames: [String]` — filenames managed by `ImageManager` locally under `Documents/CarPhotos/` and mirrored to Firebase Storage at `users/{userId}/cars/{carId}/{fileName}`. The first entry is the cover photo. Custom `Codable` handles migration from the legacy single-photo `photoFileName` key.
- `PublicCar` is the read-only projection of `Car` exposed via the `publicCars` collection — VIN, license plate, insurance fields and per-record costs are stripped per FR-06.3; owner notes ARE public per FR-06.4.
- `AppUser` includes fields backed by Firestore (`username`, `bio`, `location`) and fields backed by UserDefaults only (`driverLicenseNumber`, `driverLicenseState`, `driverLicenseExpiry`).

## Service Layer

- **`VINDecodeService`** — calls the NHTSA VPIC public API to auto-fill car fields from a 17-character VIN.
- **`NotificationManager`** — pure static functions that reschedule all local push notifications (registration/insurance/service/license expiry at 30d, 7d, on-day). Called on launch and on every `carStore.cars` change.
- **`ServiceReminderEngine`** — pure static functions that suggest `ServiceReminder` objects from maintenance history + hardcoded service intervals. No state.
- **`AIServiceSuggestionService`** — Cloud Function wrapper for AI-generated service suggestions.
- **`DocumentScanService`** — VisionKit / on-device OCR wrapper for scanning insurance/registration/license documents.
- **`ImageManager`** — local `Documents/CarPhotos/` file management (add, load, delete).
- **`AnalyticsService`** — FR-11 PostHog wrapper. A struct of static functions (the `NotificationManager` pattern): no `ObservableObject`, no environment injection, no observable state. One typed method per FR-11.4 event; the generic `capture` is private. Configured once in `Marque_PrototypeApp.init()`, with `identify`/`reset` driven off the auth-state change. Autocapture, session replay, surveys, screen views, lifecycle events, and swizzling are all explicitly disabled — several default to *true*, and screen-view capture in particular would stamp `Car.displayName` onto every event. See Key Conventions.
- **`CrashReportingService`** — FR-11.8 Firebase Crashlytics wrapper, same static-struct pattern. Deliberately separate from `AnalyticsService`: PostHog is explicitly not the crash reporter. `identify`/`reset` are driven off the same auth-state change as `AnalyticsService`, tying crash reports to the reporting uid. No configure step needed — linking the SPM product plus the existing unguarded `FirebaseApp.configure()` is sufficient; collection is on by default.

## Cloud Functions

Callable and trigger functions live in `functions/src/index.ts`. The file uses a **v1/v2 mix** — check which namespace a function uses before editing it. Twenty-two functions are exported; the constants block at the top (`BUNDLE_ID`, `APP_STORE_APP_ID`, `PRO_PRODUCT_IDS`, `APPLE_ROOT_CA`) is shared across the entitlement functions.

**Assistant & AI**
- **`askMarque`** (v2 callable) — Marque Assistant chat proxy to Anthropic (Sonnet 4.6) with server-side daily cap enforcement (10/day free, 500/day Pro), prompt caching on the garage context block and system prompt, and streaming responses. Model ID is a constant at the top of the file so it can be bumped in one place. Per FR-10.17 the context block must never include VIN, plate, insurance fields, driver license, per-record costs, notes, or photo names.
- **`suggestServiceReminders`** (v2 callable) — AI-generated service suggestions from maintenance history (FR-16). Wrapped client-side by `AIServiceSuggestionService`, and the sheet falls back to `ServiceReminderEngine` on any error including the cap. Wrapped in `withSuggestCap`: a **flat** `SUGGEST_DAILY_CAP` of 10/day per user — an abuse guard, deliberately *not* a Pro gate and never on the paywall — reserved in a transaction at `usage/suggestions_{clientDate}` and released on any thrown error (a successful zero-suggestion result is not refunded). Order is load-bearing: auth → `sanitizeSuggestInput` (whitelists fields, clamps strings/arrays: 100 history / 50 active, 64/16-char fields; the prompt is built only from its output, never from the raw request) → `assertPlausibleClientDate` → reserve. Invalid requests must never consume a slot. The reserve/release helpers intentionally duplicate the scan ones rather than share code.
- **`parseDriverLicense`**, **`parseInsuranceCard`**, **`parseMaintenanceReceipt`** (v2 callable) — Anthropic vision document parsers behind `DocumentScanService`. All three share the `ANTHROPIC_API_KEY` secret and the media-type constants. All three are wrapped in `withScanAllowance`, which enforces the FR-14.4 daily allowance (`FREE_SCAN_DAILY_CAP` 5 / `PRO_SCAN_DAILY_CAP` 50, one counter shared across document types at `usage/scans_{clientDate}`). The slot is reserved before the Claude call and released on any thrown error or when the model read nothing (FR-14.5). Requests **must** carry `clientDate` (`yyyy-MM-dd`) within ±1 day of the server's UTC date (`assertPlausibleClientDate`, shared with `askMarque`) or they're rejected `invalid-argument` — the counter doc ID is derived from it, so an unbounded value would mint a fresh allowance per call. ±1 narrows the abuse rather than closing it: a client can still use up to three counter docs per UTC day. A spent allowance is `resource-exhausted`. The iOS caps in `ScanAllowanceStore` are display copies — change both together.
- **Verified-email gate (`requireVerifiedEmail`)** — `askMarque`, `withScanAllowance` (all three parsers) and `withSuggestCap` call it immediately after the `!request.auth` check, before anything that reserves a slot or reaches Anthropic, so an unverified email/password account can't call them directly (FR-01.3 server-side). Passes if the token's `email_verified` is true, or the provider is `google.com`/`apple.com`; otherwise it falls back to `admin.auth().getUser()` because the token claim only refreshes about hourly (a user who just verified would be wrongly rejected), and fails closed with `unavailable` if that lookup throws. Rejection is `permission-denied`. `AuthService.reloadEmailVerification()` forces a token refresh before flipping `isEmailVerified`. It raises the cost of abuse but doesn't stop real or disposable mailboxes — App Check is the stronger control (client shipped, server **not yet enforcing**; see Firebase). **Any new cost-bearing callable must call it too**; nothing enforces that structurally.

**Data export**
- **`exportAccountData`** (v2 callable) — FR-15.7 / GDPR Art. 20 machine-readable export of everything stored about the caller, gathered with the Admin SDK so it also reaches paths rules deny the client (`usage/`, `appAccountTokens/`, `familyGrants/`, `publicCarOwners/`, `reports/`, `pushThrottle/`). Deliberately **not** behind `requireVerifiedEmail`: unlike the AI callables it never calls Anthropic, so there's no per-call spend for an unverified mailbox to abuse — App Check plus a flat `EXPORT_DAILY_CAP` of 5/day (`usage/exports_{serverUTCDate}`, server-clock-keyed only, never refunded on throw) are the throttle instead. Walks `users/{uid}` and every subcollection recursively via `listCollections()` (auto-picks up a future subcollection), plus `publicCars`/`publicCarOwners` owned by the uid, the caller's own `likes`/`comments` left on *other* users' cars (collection-group queries, reusing the same indexes `onAuthUserDeleted` needs), `reports` the caller filed (not reports filed against them — excluded for reporter-safety/Art. 20-scope reasons), the username reservation, and Storage object **metadata only** (name/size/contentType/updated, never bytes) under `users/{uid}/`. Excludes password hash/salt (never spread the raw `UserRecord`), other users' profile data, and other users' activity on the caller's cars (their likes/comments, and `pushThrottle` docs where the caller is only the owner). The walk reuses each query's snapshots and fans out in parallel; keep it that way, since a sequential per-doc re-read is thousands of RPCs for a heavy Assistant user. The Settings row ("Download My Account Data", `AccountDataExportView`) is separate from the car-report screen so users with no cars can still reach it. Fails `failed-precondition` rather than truncating if the serialized JSON would exceed ~9 MB. The iOS wrapper (`AccountExportService`) merges in the UserDefaults-only driver-license fields (FR-09.4, invisible to the server) under a `deviceOnly` key before writing the file.

**Entitlements (Pro)** — these three are one system; a change to any of them needs the other two checked.
- **`getAppAccountToken`** (v2 callable) — mints or returns this uid's `appAccountToken`, persisted at `appAccountTokens/{token}` (rules: `allow read, write: if false` — server-only). The client attaches it to the StoreKit purchase so a transaction can be bound to an account. Minting is contention-safe: a concurrent second call loses the transaction, retries, and finds the first token rather than minting a duplicate.
- **`appStoreNotifications`** (v1 HTTPS) — App Store Server Notifications V2 webhook. `SignedDataVerifier` **requires `appAppleId` for the PRODUCTION environment** — omitting it means production notifications never verify, which was a live bug that went unnoticed precisely because it only failed in production. Returns 500 only for `RETRYABLE_VERIFICATION_FAILURE`, so Apple redelivers on a transient OCSP failure instead of treating a swallowed error as success.
- **`syncEntitlement`** (v2 callable) — client-initiated entitlement sync. Grants `isPro` **only** when the transaction's `appAccountToken` maps back to the calling uid. No token match means the write is skipped, not granted — that's either a replayed JWS or a Family Sharing member, and self-granting off another account's transaction is the entitlement-hijack this guard exists to stop. Family members still get local Pro from StoreKit; only the server flag is withheld.

**Social & limits**
- **`estimateCarValue`** (v2 callable) — AI value range (Haiku); same wrapper order as the parsers (auth → verified email → sanitize → clientDate → reserve `usage/valuations_{date}`, 10/day, refunded on throw). Never sees VIN/plate/notes. Public display is only `PublicCar.valueRange` (rounded; `CarValueRange.publicLabel`).
- **`onCarLikeWritten` / `onCarCommentWritten`** — recompute counts transactionally, write like/comment notifications server-side (deterministic like ID; comment push throttled 1 per actor per car per 10 min via server-only `pushThrottle/`), and delete comments whose text or author name fails the word filter. **`onPublicCarModsWritten`** strips public mods whose name/brand fails it (the rules only check `mods` is a list of ≤ 30; the client gate is `CarStore.addMod`/`updateMod`). **`onUserProfileWritten`** neutralizes filtered display names/bios.
- **`onPublicCarCreated` / `onPublicCarDeleted`** — a car made private keeps its `likes/` and `comments/` hidden (rules deny reads while `publicCars/{id}` is absent) and restores counts on re-publish; a real delete sweeps them. **The ownership proof for every sweep is the `publicCarOwners/{carId}` claim**, never a query over `users/*/cars` (client-chosen IDs are spoofable).
- **`onFollowerCreated`, `onDeviceTokenCreated`, `recomputeWeeklyLikes`** (hourly) — follow push, token de-dup across accounts, weekly Top Cars count. `sendPush` honors preferences and prunes dead tokens.
- Use the modular `import { FieldValue, Timestamp } from "firebase-admin/firestore"` — `admin.firestore.FieldValue/Timestamp` are undefined in the Functions runtime (crashed triggers under the emulator).
- **`onUserBlocked`** (v2 Firestore trigger on `users/{blocker}/blocked/{blocked}` create) — deletes all four follow edges between the pair with the Admin SDK (the client can't: `followers/` binds the follower, `following/` the path owner). `retry: true`; idempotent.
- **`onCarWritten`** (v2 Firestore trigger on `users/{uid}/cars/{carId}` writes) — recomputes `usage/limits.carCount` with a `count()` aggregate. Returns early if the Auth user no longer exists, because `onAuthUserDeleted`'s `recursiveDelete` fires it for every car and a late run would otherwise recreate `usage/limits` after the cascade.
- `syncEntitlement` also writes `usage/limits.familyProUntil` (car-cap exemption only, never `isPro`) for a verified `FAMILY_SHARED` transaction, claimed first-come in `familyGrants/`.

**Lifecycle**
- **`onAuthUserDeleted`** (v1 auth trigger, imported as `functionsV1`) — the FR-10.15 / EC-08 / EC-22 deletion cascade, using the Admin SDK to reach the many paths `firestore.rules` denies to clients. Runs in six ordered phases behind a gate: **(1)** read what later phases need (username, `following[]`, `followers[]`) **(2)** reverse follow pointers **(3)** cross-user notifications **(4)** `publicCars`, then the Storage prefix, then `appAccountTokens` **(5)** username release **→ gate: throw if any error accumulated →** **(6)** `recursiveDelete(users/{uid})` **last**. The ordering is load-bearing: `recursiveDelete` destroys the data phases 2–5 read from, so running it early made every retry read an emptied graph and exit green while leaving orphans behind. See Known Pitfalls.

Dependency CVEs are handled via the `overrides` block in `functions/package.json` (currently pins `debug`, `uuid`, `qs`) — see Known Pitfalls.

## Firestore Rules

Live in `firestore.rules`. **Read the actual rule before assuming a path is writable — the per-path grants are not uniform, and "owner-scoped" is wrong often enough to be dangerous:**

- `users/{userId}` — grants `create, update` only. **`delete` is denied**, because Firestore decomposes `write` into create/update/delete and this rule never enumerates delete. Read is open to any authenticated user.
- `users/{uid}/followers/{followerId}` — writes bind the **follower**, not the path owner. The account owner cannot delete their own followers subcollection.
- `users/{uid}/following/{followedId}` — writes bind the **path owner**, so nobody can clean up a reverse pointer in someone else's `following`.
- `users/{uid}/notifications/{id}` — owner `read, update, delete`. `create` is locked to a self-attributed `follow` notification (`actorUID == auth.uid`, `type == 'follow'`, a `hasOnly` key allowlist matching `NotificationStore.writeFollowNotification`) and denied if the recipient has blocked the actor. Adding a new notification type means widening this rule.
- `users/{uid}/usage/{docId}` — `allow read` to the owner, `allow write: if false`. Writes are server-only, to prevent Assistant, document-scan and AI-suggestion daily-cap bypass. The owner **read** is load-bearing: `ScanAllowanceStore` (FR-14.4) listens on `scans_{date}`, so "locking down" `usage/` to match a write-only description would freeze the caption and gate silently.
- `users/{uid}/cars` — owner read/update/delete. **`create` enforces the FR-08.8 free 2-car cap**: allowed only if `users/{uid}.isPro`, or `usage/limits.familyProUntil` is in the future, or `usage/limits.carCount < 2` (missing doc = 0). The client's copy of the number is `CarStore.freeCarLimit` (gates and paywall/alert copy) — change both together. `carCount` is recomputed by the `onCarWritten` trigger, so a fast burst can briefly exceed 2. A rejected create is rolled back client-side and surfaces as `CarStore.carLimitRejected`.
- `users/{uid}/following/{id}` and `followers/{id}` — `create, update` are also denied if either party has blocked the other; `delete` is unrestricted for the same principal.
- `users/{uid}/blocked`, `conversations/**` — genuinely owner-scoped read/write.
- `publicCars` — read-any-auth; owner writes only an allowlist of fields (counts are server-only; URL fields must point at the car's own Storage folder; `photoURLs` ≤ 12 for the rules' 1,000-expression budget). Create/update/delete also require the caller's `publicCarOwners/{carId}` claim, written in the same batch on first publish (first-come; prevents car-ID squatting). `likes/` and `comments/` subcollections: see the rules header comments; comment author fields must match the author's own profile and reserved username.
- `users/{uid}/cars/{carId}` also requires `id == carId` and denies an ID claimed by another uid.
- `storage.rules` (now in the repo) — owner-only; writes limited to the app's real paths: images (`image/*` or `application/octet-stream`, < 10 MB), `sound.m4a` (`audio/*`, < 500 KB). `reports` — create-only client-side. `usernames` — delete permitted to the owning uid.
- **`purchases/` has no rule at all** (default deny) — see Known Pitfalls.
- `familyGrants/{originalTransactionId}` — server-only (`allow read, write: if false`). First-claim-wins record binding a Family Sharing transaction to one uid, so a replayed Family-Shared JWS can't exempt other accounts from the car cap. Swept by `onAuthUserDeleted` phase 4d.

Client-side deletes on any denied path fail with `PERMISSION_DENIED`, and the cascade swallows those with `try?`. Anything the client cannot delete must be handled server-side in `onAuthUserDeleted`, which uses the Admin SDK and bypasses rules. **Do not relax a rule to make a client delete work** — these grants are deliberately narrow.

**When adding a new subcollection under `users/{uid}/`, add its rule explicitly** — the previous wildcard `{document=**}` match was removed intentionally so `usage/` could be locked down, so an unlisted path is denied by default.

## Shared UI Components (`Components/MarqueComponents.swift`)

Reusable components used across views: `MarquePrimaryButton`, `MarqueEmptyState`, `MarqueErrorBanner`, `MarqueSectionHeader`, `UserAvatar`, `FollowButton`, `ProBadge`, `StatChip`, `LabeledDivider`.

## Directory Layout

```
Marque/
  Models/          — Car, AppUser, AppNotification, ServiceReminder, MaintenanceRecord,
                     CarData, PublicCar, ChatMessage, Conversation, AIServiceSuggestion, AppLinks
  Stores/          — CarStore, AuthService, ChatStore, ExploreStore, FollowStore, LikeStore, CommentStore, PushStore, CarValueService,
                     BlockStore, NotificationStore, SubscriptionStore,
                     ImageManager, NotificationManager, VINDecodeService, ServiceReminderEngine,
                     AIServiceSuggestionService, DocumentScanService, AnalyticsService,
                     CrashReportingService, ScanAllowanceStore
                     (note: FeatureFlagsStore.swift sits at the Marque/ root,
                      not in Stores/, alongside AppDelegate.swift)
  Components/      — MarqueComponents.swift, CarPhotoImage.swift, ScanAllowanceViews.swift
  Views/           — Legacy flat views (CarListView, CarDetailView, AddCarView, EditCarDetailView,
                     AddMaintenanceView, ExpenseSummaryView). Migration target: Features/.
  Features/        — Assistant, Auth, Expenses, Explore, Garage, Onboarding, Profile, Settings, Social
.claude/agents/    — frontend.md, backend.md, qa.md (team definitions)
functions/         — TypeScript Cloud Functions (askMarque, appStoreNotifications, onAuthUserDeleted, ...)
firestore.rules    — Firestore security rules
firebase.json      — Firebase project + emulator config
tests/rules/       — security-rules suites for firestore.rules + storage.rules (`npm test`)
docs/              — Product docs (Marque-PRD.md)
scripts/           — Dev tooling: check-anthropic-schemas.js (lint / --live check of every Anthropic output_config schema)
```

New feature views should go under `Features/<FeatureName>/`. Do not add new files to `Views/`.

# Key Conventions

- All stores are `@MainActor` classes. Avoid dispatching off the main actor inside stores.
- Stores are decoupled — `CarStore` does not know about `AuthService`, `FollowStore`, or others. Cross-store coordination happens in `Marque_PrototypeApp.body`.
- `AppUser.preview` and `CarStore.previewCars` are the canonical mock data for SwiftUI `#Preview` blocks.
- `Car.displayName` (`"<year> <make> <model>"`) is the canonical display string — don't reconstruct it inline.
- `ExpensePeriod` is the source of truth for expense filter options; `Car.expenses(in:)` and `Car.expensesByCategory(in:)` use it.
- **Never deploy Cloud Functions or Firestore rules without explicit user approval.** Build/typecheck locally, then stop and confirm. This is not delegable — no agent may deploy on its own judgment.
- Adding a new subcollection under `users/{uid}/` requires a matching rule in `firestore.rules` — the wildcard was removed intentionally.
- The Marque Assistant ships behind `FeatureFlagsStore.assistantEnabled` (Remote Config `marque_assistant_enabled`). Entry points must gate on this flag. To exercise the Assistant in the Simulator, launch a Debug build with `-marque_assistant_enabled_override YES` (`xcrun simctl launch <udid> <bundle id> -marque_assistant_enabled_override YES`) — it never affects Release or the production Remote Config value.
- **Analytics goes through `AnalyticsService`'s typed static methods — never a raw `PostHogSDK.shared.capture`.** The generic `capture` is private on purpose: it's what makes FR-11.6 (no PII in analytics) structural rather than a rule someone has to remember. Adding an event means adding a typed method whose parameters are enums, `Bool`s, and counts only. A signature that accepts a `String` from a user-editable field is a bug.
- Analytics is fire-and-forget and must never affect control flow. No `try`, no `await` that can fail a user action. A capture call that can break a save or a purchase is in the wrong place.
- Instrument on **success**, after the operation completed — not on attempt. Events fired on attempt silently corrupt every funnel in PRD Section 9.
- Smartcar/telematics was built, abandoned, and deleted in PRD v1.2 (see PRD Appendix A). Don't re-propose it without reading that entry first.
