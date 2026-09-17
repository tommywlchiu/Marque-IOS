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
- **Detect** — `grep -n "Filename.swift" Marque-Prototype.xcodeproj/project.pbxproj`

### A swallowed error inside a retry loop is an infinite loop
- **Rule** — Any `while` loop whose exit condition depends on a mutation must not swallow that mutation's failure. Use `guard (try? await op()) != nil else { break }`, not bare `try? await op()`.
- **Why** — The message-deletion pager re-queried the same 500 docs forever if the batch commit kept failing, hanging `deleteAccount()`.
- **Detect** — Grep for `try?` inside `while` bodies in `Stores/**`.

### `npm audit fix` does nothing for transitive dependencies
- **Rule** — For CVEs inside the `firebase-admin` / `firebase-functions` trees, add an `overrides` entry in `functions/package.json`. Don't rely on `npm audit fix`; it only bumps direct dependencies.
- **Why** — `npm audit fix` cleared 1 of 12 CVEs. Overrides on `uuid` and `qs` cleared the remaining 11 to zero.
- **Detect** — `cd functions && npm audit` after any dependency change.

### npm's suggested fix version can be wrong
- **Rule** — Before committing to a major upgrade that audit recommends, install the proposed version in a scratch dir and re-run `npm audit` to confirm it actually clears the CVE.
- **Why** — audit recommended `firebase-admin@14.3.0` for a `uuid` CVE; 14.3.0 pins the same vulnerable `@google-cloud/storage`, so the upgrade would have cleared nothing and added a peer-dep conflict with `firebase-functions@6`.
- **Detect** — `mkdir /tmp/scratch && cd /tmp/scratch && npm i <pkg>@<version> && npm audit`

### Simulator names are machine-specific
- **Rule** — Never hardcode a simulator in an `xcodebuild` destination. Query for an installed one.
- **Why** — `iPhone 16` is not installed on this machine; every hardcoded build command failed until agents discovered iPhone 17.
- **Detect** — `xcrun simctl list devices available | grep iPhone`

### `DEVELOPER_DIR` must be exported, not inline-prefixed
- **Rule** — This machine's `xcode-select` points at CommandLineTools, so both `xcodebuild` and `xcrun` fail without `DEVELOPER_DIR`. It must be `export`ed as its own statement first. `DEVELOPER_DIR=... xcodebuild -destination "...$(xcrun ...)"` does **not** work: the shell expands the subshell before applying the command-prefix assignment, so `xcrun` runs without it, returns empty, and `xcodebuild` gets a malformed destination and silently dumps its help text instead of building. Also pass `-derivedDataPath` to a scratch dir — Xcode locks the default when open.
- **Why** — The first fix for the hardcoded-simulator pitfall used the inline-prefix one-liner. It looked correct, was committed to three files, and produced a help dump rather than a build on the first run.
- **Detect** — `xcode-select -p`. If a build prints flag documentation instead of compiling, the destination is malformed — echo the resolved `$SIM` and check it isn't empty.

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
- **Detect** — `grep -rn 'collection("' Marque-Prototype/ functions/src/ | grep -oE 'collection\("[^"]+"\)' | sort -u` then cross-check each against `firestore.rules` and against both deletion paths.

### A retry that destroys its own inputs reports success
- **Rule** — "Every step is idempotent" is a claim about individual operations, not about the function. Before enabling retries, ask what the *second* run reads. If an earlier run deleted the state a later phase depends on, the retry does nothing, finds no errors, and exits green — worse than no retry, because it looks like it worked. Order destructive work so the widest-blast-radius delete happens **last**, and abort before it if any earlier phase failed.
- **Why** — `onAuthUserDeleted` ran `recursiveDelete(users/{uid})` even when reverse-pointer cleanup had failed. The retry then read empty follower lists, cleaned nothing, and reported success — leaving ghost pointers permanently. The same shape burned the username reservation: once the profile doc was gone, the retry could no longer read the username it needed to release.
- **Detect** — For every phase in a retryable function, list what it reads and what it deletes. Any phase that deletes something an earlier phase read is a retry hazard.

### A constant that "looks right" still needs checking against the actual build artifact
- **Rule** — Never assert a bundle ID, app ID, or similar identifying constant in code or docs without checking it against the real source: `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`, or `CFBundleIdentifier` in the built `Info.plist`. A value that reads as plausible — especially one matching the product's own name — is not evidence it's correct.
- **Why** — `CLAUDE.md`, every agent brief, and the Cloud Functions `BUNDLE_ID` constant all asserted `com.marque.app` for the entire session. The real bundle ID, set in the very first commit, is `com.tommychiu.marque`. This silently broke `SignedDataVerifier`'s bundle-ID check on every production and sandbox verification, on top of the separate `appAppleId` constructor bug found the same week — two independent reasons the same code path never worked, neither visible from reading the code alone.
- **Detect** — `grep PRODUCT_BUNDLE_IDENTIFIER Marque-Prototype.xcodeproj/project.pbxproj` and diff against any hardcoded bundle ID elsewhere in the repo.

### Documentation drifts silently and agents act on it
- **Rule** — When you change an architectural pattern, update `CLAUDE.md` **and** every `.claude/agents/*.md` that repeats the claim, in the same change.
- **Why** — Both this file and both agent definitions asserted a `#if canImport(FirebaseCore)` mock-branch pattern for ~4 months after it was removed. Agents were being briefed with a false architecture.
- **Detect** — `grep -rn "canImport\|UserDefaults\|5 tabs" CLAUDE.md .claude/agents/`

---

# Build & Run

Build and run through **Xcode** — open `Marque-Prototype.xcodeproj`. One native target, no test harness (no XCTest bundle, no `test` script in `functions/`). Three SPM packages: `firebase-ios-sdk` (linked products `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseFunctions`, `FirebaseRemoteConfig`), `GoogleSignIn-iOS` (`GoogleSignIn`, `GoogleSignInSwift`), and `posthog-ios` @ 3.77.0 (`PostHog`).

Command-line build. Copy this whole block — the three lines are load-bearing and verified working on this machine:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+' | tail -1)
xcodebuild -project Marque-Prototype.xcodeproj -scheme Marque-Prototype \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath /tmp/marque-verify
```
`export` must come first and be its own statement — see the pitfall below. `-derivedDataPath` avoids the lock Xcode holds on the default DerivedData when it's open.

Cloud Functions live in `functions/` (TypeScript, `firebase-functions` v6). Build with `cd functions && npm run build`. **Never deploy (`firebase deploy`) without explicit user approval.**

# Architecture

## Navigation & Root State

`Marque_PrototypeApp.swift` bootstraps nine `@StateObject`s injected as environment objects: `CarStore`, `AuthService`, `ExploreStore`, `FollowStore`, `SubscriptionStore`, `BlockStore`, `NotificationStore`, `ChatStore`, and `FeatureFlagsStore`. `RootView` drives top-level navigation:

```
Onboarding (once) → LoginView → VerifyEmailView (if email unverified)
                              → ProfileSetupView (if incomplete)
                              → MainTabView
```

`MainTabView` currently has 3 tabs (Garage, an Add "+" tab, Explore). None of Notifications, Profile, or Settings are tab items — each is reached differently: **Settings** is a toolbar gear icon on Garage; **Notifications** is a toolbar bell icon on Explore; **Profile** isn't a toolbar item anywhere — it's the inline header on Garage (Edit Profile button, follower/following stat chips). The PRD's 5-tab layout (Garage / Explore / Notifications / Profile / Settings) is the eventual target; the current arrangement is a deliberate interim state.

## Stores

All stores are `@MainActor` classes. Firestore listeners are started/stopped in response to auth state changes (see `Marque_PrototypeApp.body`).

| Store | Responsibility |
|---|---|
| `CarStore` | User's cars — Firestore-backed with local persistence cache; propagates changes to `NotificationManager`. |
| `AuthService` | Firebase Auth (Apple, Google, Email + email verification). Owns profile extras: username/bio/location sync to Firestore `users/{uid}`; driver license fields live in UserDefaults only (`marque_profile_{uid}`) per FR-09.4. |
| `ChatStore` | Marque Assistant conversations + messages at `users/{uid}/conversations/{convId}/messages/`. |
| `SubscriptionStore` | StoreKit purchases + Firestore `isPro` sync for Pro tier. |
| `ExploreStore` | Public cars feed for Explore tab (Firestore listener on `publicCars`). |
| `FollowStore` | Following/followers subcollections. |
| `BlockStore` | Blocked users. |
| `NotificationStore` | In-app notification inbox (Firestore). |
| `FeatureFlagsStore` | Firebase Remote Config gate (e.g. `marque_assistant_enabled`, default false). |

## Firebase

Firebase iOS SDK is a required build dependency. `FirebaseApp.configure()` runs unguarded in `Marque_PrototypeApp.init()`; Firestore offline persistence is enabled with a 100MB cache.

An earlier `#if canImport(FirebaseCore)` conditional-compilation pattern with `#else` mock branches existed until May 2026 and was removed when Firebase became a hard dependency. **Do not reintroduce it.** Two vestigial `#if canImport(FirebaseAuth)` guards remain in `Models/AppUser.swift` (lines 2 and 50) — dead code, safe to strip.

## Data Model Relationships

- `Car` embeds `[MaintenanceRecord]` and `[ServiceReminder]` directly (not normalized).
- `Car.photoFileNames: [String]` — filenames managed by `ImageManager` locally under `Documents/CarPhotos/` and mirrored to Firebase Storage at `users/{userId}/cars/{carId}/{fileName}`. The first entry is the cover photo. Custom `Codable` handles migration from the legacy single-photo `photoFileName` key.
- `PublicCar` is the read-only projection of `Car` exposed via the `publicCars` collection — VIN, license plate, insurance fields, per-record costs, and notes are stripped per FR-06.3.
- `AppUser` includes fields backed by Firestore (`username`, `bio`, `location`) and fields backed by UserDefaults only (`driverLicenseNumber`, `driverLicenseState`, `driverLicenseExpiry`).

## Service Layer

- **`VINDecodeService`** — calls the NHTSA VPIC public API to auto-fill car fields from a 17-character VIN.
- **`NotificationManager`** — pure static functions that reschedule all local push notifications (registration/insurance/service/license expiry at 30d, 7d, on-day). Called on launch and on every `carStore.cars` change.
- **`ServiceReminderEngine`** — pure static functions that suggest `ServiceReminder` objects from maintenance history + hardcoded service intervals. No state.
- **`AIServiceSuggestionService`** — Cloud Function wrapper for AI-generated service suggestions.
- **`DocumentScanService`** — VisionKit / on-device OCR wrapper for scanning insurance/registration/license documents.
- **`ImageManager`** — local `Documents/CarPhotos/` file management (add, load, delete).
- **`AnalyticsService`** — FR-11 PostHog wrapper. A struct of static functions (the `NotificationManager` pattern): no `ObservableObject`, no environment injection, no observable state. One typed method per FR-11.4 event; the generic `capture` is private. Configured once in `Marque_PrototypeApp.init()`, with `identify`/`reset` driven off the auth-state change. Autocapture, session replay, surveys, screen views, lifecycle events, and swizzling are all explicitly disabled — several default to *true*, and screen-view capture in particular would stamp `Car.displayName` onto every event. See Key Conventions.

## Cloud Functions

Callable and trigger functions live in `functions/src/index.ts`. The file uses a **v1/v2 mix** — check which namespace a function uses before editing it. Nine functions are exported; the constants block at the top (`BUNDLE_ID`, `APP_STORE_APP_ID`, `PRO_PRODUCT_IDS`, `APPLE_ROOT_CA`) is shared across the entitlement functions.

**Assistant & AI**
- **`askMarque`** (v2 callable) — Marque Assistant chat proxy to Anthropic (Sonnet 4.6) with server-side daily cap enforcement (10/day free, 500/day Pro), prompt caching on the garage context block and system prompt, and streaming responses. Model ID is a constant at the top of the file so it can be bumped in one place. Per FR-10.17 the context block must never include VIN, plate, insurance fields, driver license, per-record costs, notes, or photo names.
- **`suggestServiceReminders`** (v2 callable) — AI-generated service suggestions from maintenance history. Wrapped client-side by `AIServiceSuggestionService`.
- **`parseDriverLicense`**, **`parseInsuranceCard`**, **`parseMaintenanceReceipt`** (v2 callable) — Anthropic vision document parsers behind `DocumentScanService`. All three share the `ANTHROPIC_API_KEY` secret and the media-type constants.

**Entitlements (Pro)** — these three are one system; a change to any of them needs the other two checked.
- **`getAppAccountToken`** (v2 callable) — mints or returns this uid's `appAccountToken`, persisted at `appAccountTokens/{token}` (rules: `allow read, write: if false` — server-only). The client attaches it to the StoreKit purchase so a transaction can be bound to an account. Minting is contention-safe: a concurrent second call loses the transaction, retries, and finds the first token rather than minting a duplicate.
- **`appStoreNotifications`** (v1 HTTPS) — App Store Server Notifications V2 webhook. `SignedDataVerifier` **requires `appAppleId` for the PRODUCTION environment** — omitting it means production notifications never verify, which was a live bug that went unnoticed precisely because it only failed in production. Returns 500 only for `RETRYABLE_VERIFICATION_FAILURE`, so Apple redelivers on a transient OCSP failure instead of treating a swallowed error as success.
- **`syncEntitlement`** (v2 callable) — client-initiated entitlement sync. Grants `isPro` **only** when the transaction's `appAccountToken` maps back to the calling uid. No token match means the write is skipped, not granted — that's either a replayed JWS or a Family Sharing member, and self-granting off another account's transaction is the entitlement-hijack this guard exists to stop. Family members still get local Pro from StoreKit; only the server flag is withheld.

**Lifecycle**
- **`onAuthUserDeleted`** (v1 auth trigger, imported as `functionsV1`) — the FR-10.15 / EC-08 / EC-22 deletion cascade, using the Admin SDK to reach the many paths `firestore.rules` denies to clients. Runs in six ordered phases behind a gate: **(1)** read what later phases need (username, `following[]`, `followers[]`) **(2)** reverse follow pointers **(3)** cross-user notifications **(4)** `publicCars`, then the Storage prefix, then `appAccountTokens` **(5)** username release **→ gate: throw if any error accumulated →** **(6)** `recursiveDelete(users/{uid})` **last**. The ordering is load-bearing: `recursiveDelete` destroys the data phases 2–5 read from, so running it early made every retry read an emptied graph and exit green while leaving orphans behind. See Known Pitfalls.

Dependency CVEs are handled via the `overrides` block in `functions/package.json` (currently pins `debug`, `uuid`, `qs`) — see Known Pitfalls.

## Firestore Rules

Live in `firestore.rules`. **Read the actual rule before assuming a path is writable — the per-path grants are not uniform, and "owner-scoped" is wrong often enough to be dangerous:**

- `users/{userId}` — grants `create, update` only. **`delete` is denied**, because Firestore decomposes `write` into create/update/delete and this rule never enumerates delete. Read is open to any authenticated user.
- `users/{uid}/followers/{followerId}` — writes bind the **follower**, not the path owner. The account owner cannot delete their own followers subcollection.
- `users/{uid}/following/{followedId}` — writes bind the **path owner**, so nobody can clean up a reverse pointer in someone else's `following`.
- `users/{uid}/notifications/{id}` — grants `read, update, create`. No delete.
- `users/{uid}/usage/{docId}` — `allow write: if false`. Server-only, to prevent Assistant daily-cap bypass.
- `users/{uid}/cars`, `blocked`, `conversations/**` — genuinely owner-scoped read/write.
- `publicCars` — read-any-auth, write-owner. `reports` — create-only client-side. `usernames` — delete permitted to the owning uid.
- **`purchases/` has no rule at all** (default deny) — see Known Pitfalls.

Client-side deletes on any denied path fail with `PERMISSION_DENIED`, and the cascade swallows those with `try?`. Anything the client cannot delete must be handled server-side in `onAuthUserDeleted`, which uses the Admin SDK and bypasses rules. **Do not relax a rule to make a client delete work** — these grants are deliberately narrow.

**When adding a new subcollection under `users/{uid}/`, add its rule explicitly** — the previous wildcard `{document=**}` match was removed intentionally so `usage/` could be locked down, so an unlisted path is denied by default.

## Shared UI Components (`Components/MarqueComponents.swift`)

Reusable components used across views: `MarquePrimaryButton`, `MarqueEmptyState`, `MarqueErrorBanner`, `MarqueSectionHeader`, `UserAvatar`, `FollowButton`, `ProBadge`, `StatChip`, `LabeledDivider`.

## Directory Layout

```
Marque-Prototype/
  Models/          — Car, AppUser, AppNotification, ServiceReminder, MaintenanceRecord,
                     CarData, PublicCar, ChatMessage, Conversation, AIServiceSuggestion, AppLinks
  Stores/          — CarStore, AuthService, ChatStore, ExploreStore, FollowStore,
                     BlockStore, NotificationStore, SubscriptionStore,
                     ImageManager, NotificationManager, VINDecodeService, ServiceReminderEngine,
                     AIServiceSuggestionService, DocumentScanService, AnalyticsService
                     (note: FeatureFlagsStore.swift sits at the Marque-Prototype/ root,
                      not in Stores/, alongside AppDelegate.swift)
  Components/      — MarqueComponents.swift, CarPhotoImage.swift
  Views/           — Legacy flat views (CarListView, CarDetailView, AddCarView, EditCarDetailView,
                     AddMaintenanceView, ExpenseSummaryView). Migration target: Features/.
  Features/        — Assistant, Auth, Expenses, Explore, Garage, Onboarding, Profile, Settings, Social
.claude/agents/    — frontend.md, backend.md, qa.md (team definitions)
functions/         — TypeScript Cloud Functions (askMarque, appStoreNotifications, onAuthUserDeleted, ...)
firestore.rules    — Firestore security rules
firebase.json      — Firebase project + emulator config
docs/              — Product docs (Marque-PRD.md)
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
- The Marque Assistant ships behind `FeatureFlagsStore.assistantEnabled` (Remote Config `marque_assistant_enabled`). Entry points must gate on this flag.
- **Analytics goes through `AnalyticsService`'s typed static methods — never a raw `PostHogSDK.shared.capture`.** The generic `capture` is private on purpose: it's what makes FR-11.6 (no PII in analytics) structural rather than a rule someone has to remember. Adding an event means adding a typed method whose parameters are enums, `Bool`s, and counts only. A signature that accepts a `String` from a user-editable field is a bug.
- Analytics is fire-and-forget and must never affect control flow. No `try`, no `await` that can fail a user action. A capture call that can break a save or a purchase is in the wrong place.
- Instrument on **success**, after the operation completed — not on attempt. Events fired on attempt silently corrupt every funnel in PRD Section 9.
- Smartcar/telematics was built, abandoned, and deleted in PRD v1.2 (see PRD Appendix A). Don't re-propose it without reading that entry first.
