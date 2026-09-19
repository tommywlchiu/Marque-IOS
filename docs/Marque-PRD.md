# Marque — Product Requirements Document

**Version:** 1.2
**Status:** Ready for Development
**Author:** Product
**Last Updated:** September 2026
**Audience:** Engineering, Design, Investors

**v1.1 changes:** Added Tier 4 (Intelligence) with the Marque Assistant — an in-app AI chatbot for car-related questions. See Section 5 (Tier 4), Section 6 (Assistant stories), Section 7 (FR-10), Section 8 (EC-16–EC-20), Section 10 (R-11–R-12), and Section 11.

**v1.2 changes:** A gap review against the built codebase found several places where this document was unmeasurable, self-contradictory, or drifted from reality. Corrected:

1. **Instrumentation (new FR-11).** Section 9 defined ~20 success metrics and the document contained zero mentions of analytics. Nothing in the app measured any of them — `FirebaseAnalytics` was not even a linked dependency. Without instrumentation, none of G1–G5 can be validated. PostHog selected; events now specified per metric.
2. **Pro tier repositioned (FR-08 rewritten).** Pro was advertising four benefits, three of which were free in the shipped code (expense analytics, notification customization, social profile). PDF export — the fourth — was listed as v1.0 in Section 5 *and* as cut-to-v1.1 in Section 11, and was built in neither. Pro now anchors on **metered AI** (Assistant, document scanning), the features with genuine recurring cost per use. Export is now free — see item 4.
3. **Onboarding specified (new FR-13).** R-01 (low activation) is the only High/High risk in this document and its entire mitigation lived in a table cell. It now has requirements.
4. **Export rescoped and freed (new FR-15).** The original framing — a service history to show a buyer — does not survive comparison to Carfax: a seller-generated PDF is unverified, and buyers already have a trusted third-party report for accidents and title. What survives is **tax and business expense reporting**, where Carfax is irrelevant. Rescoped accordingly, moved out of Pro, and paired with GDPR data portability.
5. **Accessibility (new FR-12).** Previously absent entirely. Baseline requirements added while retrofit cost is still low.
6. **Document scanning documented (new FR-14).** Shipped and in production, but listed in this document only as a deferred v2 *non-goal*. Corrected.
7. **Smartcar removed.** A built-but-disabled telematics integration (store, three Cloud Functions, Car Detail UI) existed in the codebase and appeared nowhere in this document. Decision: abandon and delete. Recorded in Appendix A so the decision is not silently re-litigated.
8. **Reality corrections.** Tab structure (3, not the 5 described), bundle identifier, subscription product IDs, and shipped-state of the Assistant all reconciled with the codebase.
9. **AI service suggestions documented (new FR-16).** The iOS client already contained an AI-powered "Suggested Reminders" sheet that this document never mentioned, calling a Cloud Function that was not deployed — so the sheet fell back to rule-based suggestions every time — and that, as written, had no usage cap and no bound on request size. Specified here as a free feature behind a flat server-side abuse cap, with a cost note added to R-12.

---

## Document Control

| Field | Detail |
|---|---|
| Product Name | Marque |
| Platform | iOS (iPhone first) |
| Target Launch | v1.0 MVP |
| Prototype Status | Local garage app fully built; cloud/social layer to be developed |
| Stakeholders | Founder, Design, Engineering, QA |

---

# Section 1 — Product Summary

Marque is an iOS app that helps car owners store, track, and share their vehicle information. It solves the universal problem of scattered car records — insurance cards in glove boxes, service receipts in drawers, expiry dates forgotten in emails — by giving every car a permanent, organized home on your phone.

For car enthusiasts, Marque goes further: it lets them build a public garage, follow other collectors, and showcase the vehicles they're proud of.

The app works for two audiences simultaneously. A Toyota Camry owner who just wants to remember when their registration expires. A BMW collector with six cars who wants an audience for their fleet. Both use the same product and neither compromises the other's experience.

A functional prototype exists covering the core garage experience: adding cars by VIN or manually, tracking maintenance and service history, storing photos, calculating expenses, and scheduling expiry reminders. The v1.0 PRD covers the full product including authentication, cloud sync, and the social layer.

---

# Section 2 — User Personas

### Persona 1: The Practical Owner

> **"I just want to know when my insurance expires and what my mechanic did last time."**

- **Name:** Marcus, 34
- **Occupation:** Software engineer
- **Cars:** 1 daily driver (Honda Accord)
- **Pain point:** Keeps insurance and registration info in his email. Loses service receipts. Missed a registration renewal last year.
- **What he wants:** A simple, private record of everything about his car. No friction, no social pressure.
- **What he doesn't want:** Notifications he didn't ask for. Apps that upsell him every screen.
- **Platform behavior:** Checks the app a few times a year, mostly around renewal dates.

---

### Persona 2: The Enthusiast

> **"I've owned 11 cars. I want to show my collection and find people who understand why I have three of them."**

- **Name:** Sofia, 27
- **Occupation:** Freelance photographer
- **Cars:** 3 currently (Porsche 944, Miata, daily BMW)
- **Pain point:** Posts car content on Instagram but it's lost in her general feed. No dedicated place for her car identity. Can't find local enthusiasts by what they drive.
- **What she wants:** A garage that feels like a portfolio. A feed of people who share her taste.
- **What she doesn't want:** A generic social feed full of noise. A product that feels like a DMV form.
- **Platform behavior:** Opens the app several times a week. Adds photos, browses Explore, follows new accounts.

---

### Persona 3: The Upgrader

> **"I track everything about my cars. I need all of this synced across my iPhone and iPad, and I want to export service history when I sell."**

- **Name:** David, 42
- **Occupation:** Contractor and car restorer
- **Cars:** 5 (3 project cars + 2 dailies)
- **Pain point:** Keeps spreadsheets. Wants everything in one place across devices. Buyers want to see full service history when purchasing.
- **What he wants:** Unlimited cars, PDF export, cloud sync, reliability.
- **What he doesn't want:** Apps that lose his data or reset between updates.
- **Platform behavior:** Power user. Will hit the free tier limit. Natural Pro subscriber.

---

# Section 3 — Problem Statement

### The core problem
There is no purpose-built app for managing personal vehicle information that is simultaneously useful enough for a practical owner and compelling enough for an enthusiast.

**Current workarounds and why they fail:**

| Workaround | Why It Fails |
|---|---|
| Notes / spreadsheets | No structure, no reminders, no sharing |
| Insurance company apps | One car, one company, no maintenance tracking |
| General garage apps (CarFax, etc.) | Dealer-centric, not owner-centric; ugly, no social layer |
| Instagram / Facebook | General social feed; no car-specific organization; no private records |
| Paper / glove box | Lost, damaged, inaccessible remotely |

### The specific gaps Marque fills

1. **Centralized, structured storage** for every piece of car information a person cares about — specs, service records, photos, insurance, registration.
2. **Proactive reminders** before things expire, without the user having to remember to check.
3. **A public identity layer** that lets enthusiasts show off their collection without polluting a general social feed.
4. **A community discovery tool** so enthusiasts can find and follow people based on what they actually drive.

---

# Section 4 — Goals and Non-Goals

## Goals — v1.0

| # | Goal | Metric |
|---|---|---|
| G1 | Give any car owner a better place to store vehicle info than their email/notes | 1,000 cars added in first 30 days |
| G2 | Make expiry reminders reliable and actionable | >50% of users with expiry dates enable notifications |
| G3 | Create a social layer that enthusiasts want to share | 20% of users make at least one car public within 7 days of signup |
| G4 | Establish a monetization path that doesn't compromise free-tier value | >3% conversion to Pro within 90 days of launch |
| G5 | Deliver a crash-free, fast experience | >99.5% crash-free sessions, <2s cold launch |

## Non-Goals — v1.0

These are explicitly deferred. Any feature request that falls under these should be rejected for v1.

| Non-Goal | Why Deferred |
|---|---|
| Direct messaging / chat | High complexity, moderation liability, distraction from core |
| Fuel / mileage logbook | Valuable but a separate use case; validate core first |
| Telematics / connected-car (Smartcar) | Built as a prototype integration, then abandoned and deleted in v1.2. OAuth complexity and per-read vendor cost were not justified by the single feature it enabled (odometer auto-sync). See Appendix A |
| Car valuation / market pricing | Third-party API cost, legal liability; v2 |
| Android version | Platform focus required for quality; v2 |
| Web app or dashboard | iOS-first strategy; v2 |
| Marketplace / classifieds | Completely different product; v3 |
| Dealer / business accounts | B2B is a different sales motion; future |
| Comments on public cars | Moderation burden, distraction from core; v1.5 |
| Algorithmic feed | No data to train on at launch; chronological for v1 |

---

# Section 5 — Key Features

Organized by priority tier:

## Tier 1 — Core Garage (Prototype Complete)

| Feature | Description | Status |
|---|---|---|
| **VIN Decode** | Add a car by entering its 17-digit VIN; fields auto-populate via NHTSA API | Built |
| **Manual Entry** | Add a car by picking make from a list and entering model/year | Built |
| **Car Detail** | Full record per car: specs, photo, registration, insurance, notes | Built |
| **Maintenance Log** | Log service records (type, date, mileage, cost, shop, notes) | Built |
| **Expense Tracking** | Aggregated cost view by vehicle and category, filterable by time period | Built |
| **Expiry Alerts** | Push notifications 30 days, 7 days, and on the day for insurance and registration expiry | Built |
| **Car Photo** | Add, change, reposition (drag), and remove car photos | Built |

## Tier 2 — Cloud + Identity (v1.0 New)

| Feature | Description | Priority |
|---|---|---|
| **Authentication** | Sign in with Apple, Google, and Email; 2FA via Firebase | P0 |
| **Cloud Sync** | All cars, records, and photos synced to Firestore and Firebase Storage | P0 |
| **Offline Mode** | Full read/write access with auto-sync when connection restores | P0 |
| **User Profile** | Username, display name, profile photo, bio, public stats | P0 |
| **Profile Setup** | Post-signup onboarding: username, photo, bio | P0 |
| **Driver License Storage** | Optional private storage of license number, state, and expiry date for personal reference | P2 |
| **Local Data Import** | Migrate existing prototype data to cloud on first login | P1 |
| **Document Scanning** | Camera/photo capture of insurance cards, registrations, and maintenance receipts, parsed by AI into structured fields. **Shipped** — three Cloud Functions in production. Previously undocumented; see FR-14 | P1 |
| **Pro Tier** | Higher AI limits — Assistant messages and document scans — plus unlimited cars and the Pro badge, via monthly/annual subscription. See FR-08 | P1 |

## Tier 3 — Social Layer (v1.0 New)

| Feature | Description | Priority |
|---|---|---|
| **Public/Private Toggle** | Per-car visibility control, default private | P0 |
| **Public Profile** | Read-only view of another user's public garage | P1 |
| **Follow / Unfollow** | Follow other users; see their new cars in a following feed | P1 |
| **Explore** | Browse public garages, search by make/model/username | P1 |
| **Following Feed** | Chronological list of new cars from followed users | P1 |

## Tier 4 — Intelligence (v1.1 New)

| Feature | Description | Priority |
|---|---|---|
| **Marque Assistant** | Floating "Ask Marque" chatbot that answers car questions using the user's garage as context plus general automotive knowledge; read-only in v1 (no writes to user data). **Deployed** behind the `marque_assistant_enabled` Remote Config flag | P1 |
| **AI Service Suggestions** | The Suggested Reminders sheet proposes service reminders specific to the car using an AI model, falling back to the rule-based engine when the AI path is unavailable. Free for all users, behind a flat daily abuse cap — deliberately not a Pro lever. See FR-16 | P2 |

## Tier 5 — Foundations (v1.2 New)

Not user-facing features. These exist because the document previously assumed them without requiring them.

| Feature | Description | Priority |
|---|---|---|
| **Analytics Instrumentation** | PostHog event tracking covering every metric in Section 9. Without this, none of G1–G5 is measurable. See FR-11 | P0 |
| **Accessibility Baseline** | Dynamic Type, VoiceOver labels, tap-target minimums, contrast. See FR-12 | P1 |
| **Onboarding Flow** | First-run experience that ends at a saved car, not an empty garage — the mitigation for R-01, the highest-rated risk in this document. See FR-13 | P0 |
| **Data Export** | Expense/service reporting for tax and business use, plus GDPR Art. 20 portability. Free, not Pro. See FR-15 | P2 |

---

# Section 6 — User Stories

### Authentication

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-01 | As a new user, I want to sign up with Apple ID so that I don't need to create a new password | Auth completes in <3 taps with no form entry |
| US-02 | As a new user, I want to sign up with Google so that I can use my existing account | Google sheet appears, auth completes on return |
| US-03 | As a new user, I want to sign up with email so that I have an account independent of Apple/Google | Email verified before full access granted |
| US-04 | As a returning user, I want to be automatically signed in so that I don't have to log in every time | Auto sign-in on launch if token valid |
| US-05 | As a user who forgot my password, I want to reset it via email | Reset email delivered; new password works immediately |

### Garage

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-06 | As a car owner, I want to add my car by VIN so that I don't have to type all the specs manually | VIN search auto-populates make, model, year, trim, engine, fuel, transmission within 3s |
| US-07 | As a car owner, I want to add my car manually when I don't have the VIN | Manual path requires only make, model, year to save |
| US-08 | As a car owner, I want to add a photo to my car and reposition it | Photo picker opens with permission request; drag gesture repositions |
| US-09 | As a car owner, I want to log a service record with cost, shop, and notes | Form accepts all fields; service type is required; all others optional |
| US-10 | As a car owner, I want to see my total maintenance spend over time | Expense view shows totals by vehicle and by category, filterable by period |
| US-11 | As a car owner, I want to be reminded before my insurance and registration expire | Notifications fire at 30 days, 7 days, and on the day; tap goes to that car |
| US-12 | As a car owner, I want my data accessible even when I'm offline | App shows full garage from local cache when offline |
| US-13 | As a user with existing local data, I want to import it to my account | Import prompt on first login; all cars and records transferred |

### Social

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-14 | As an enthusiast, I want to make individual cars public so that others can see them | Per-car toggle; changes visibility immediately; default is private |
| US-15 | As a user, I want a profile page others can visit to see my public cars | Profile shows avatar, bio, stats, and public car grid |
| US-16 | As a user, I want to follow others so that I can see their new cars | Follow/unfollow from public profile; following feed updates accordingly |
| US-17 | As a user, I want to discover new garages in Explore | Explore shows public cars, searchable by make/model/username |
| US-18 | As a user, I want to view another user's public car without seeing their private info | VIN, license plate, insurance details, costs never shown on public view |

### Pro

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-19 | As a user with 4+ cars, I want to upgrade to Pro to add more | Paywall shown on 4th car add; purchase unlocks immediately |
| US-20 | As a Pro user, I want my subscription restored on a new device | Restore purchase link on paywall; Firestore updated on restore |
| US-30 | As a heavy Assistant user, I want to keep asking questions after the free daily limit so my research isn't interrupted mid-task | Free tier caps at 10 messages/day; the cap notice states plainly what Pro raises it to; upgrading lifts the cap immediately without re-launching |
| US-31 | As someone photographing a stack of maintenance receipts, I want to scan more than the free daily allowance in one sitting | Free tier caps document scans per day; the cap is shown before the scan is attempted, not after; Pro raises it |
| US-32 | As a prospective subscriber, I want the paywall to describe only what Pro actually unlocks so I don't feel misled after paying | Every benefit listed on the upgrade sheet maps to an enforced gate in code. No benefit may be advertised that free users already receive |

### Driver License

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-21 | As a car owner, I want to store my driver's license number so I can retrieve it when filling out forms or at the DMV | Number, state, and expiry date are editable from Edit Profile; data is stored only on this device by default |
| US-22 | As a user, I want my license number hidden by default so a glance at my screen doesn't expose it | Number rendered via `SecureField` with a reveal toggle, matching the iOS Settings password-reveal pattern |
| US-23 | As a user, I want a reminder before my driver's license expires | If expiry is set, schedule local notifications at 30 days, 7 days, and on the day of expiry, reusing the existing notification engine |

### Assistant

| ID | Story | Acceptance Criteria |
|---|---|---|
| US-24 | As a car owner, I want to ask questions about my specific vehicles so the answers factor in my actual make, model, mileage, and service history | Assistant references the user's own cars by name (e.g., "Your 2018 Miata is due for…") when the question is contextually relevant to a car in the garage |
| US-25 | As a car owner, I want to ask general car questions (comparisons, buying advice, common issues, DIY guidance) so I don't have to search the web | Assistant answers general automotive questions with model-neutral advice when no user car is contextually relevant |
| US-26 | As a user, I want to open the assistant from anywhere in the app | A floating "Ask Marque" button is visible on the primary tabs; tapping it opens a chat surface |
| US-27 | As a user viewing a car, I want to ask questions about *that* car specifically | An "Ask Marque about this car" entry point on Car Detail opens the chat pre-scoped to that car |
| US-28 | As a free user, I want to know when I'm approaching my daily message limit so I'm not surprised | Remaining-message indicator visible in the chat surface; upgrade prompt shown on the 11th attempt |
| US-29 | As a returning user, I want my past conversations available so I can pick up where I left off | Conversation history persists across sessions in Firestore; conversation list accessible from the chat surface |

---

# Section 7 — Functional Requirements

## FR-01: Authentication

- **FR-01.1** App must support Sign in with Apple, Google, and Email/Password
- **FR-01.2** Sign in with Apple must be listed first (App Store requirement when offering any social login)
- **FR-01.3** Email accounts must verify their address before full access is granted
- **FR-01.4** Firebase Auth token must be refreshed silently; the user should not be prompted to re-authenticate within a 90-day session
- **FR-01.5** If the same email exists under two providers, the app must offer to link the accounts rather than show an error
- **FR-01.6** Profile setup (username, photo, bio) must be completed before the main app is accessible; only username is required
- **FR-01.7** Usernames must be 3–30 characters, alphanumeric and underscores only, globally unique
- **FR-01.8** Username availability must be checked in real-time with a 500ms debounce

## FR-02: Car Management

- **FR-02.1** VIN decode must call NHTSA VPIC API; response must populate make, model, year, trim, body style, drive type, engine, fuel type, and transmission
- **FR-02.2** VIN input must be validated as exactly 17 characters before the search button enables
- **FR-02.3** If VIN decode fails or returns no data, the user must be able to proceed with manual entry without re-opening the flow
- **FR-02.4** Minimum required fields to save a car: make, model, year
- **FR-02.5** All car records must be stored in Firestore under `users/{userId}/cars/{carId}`
- **FR-02.6** Car deletion must delete: the Firestore document, all maintenance subcollections, and the photo from Firebase Storage
- **FR-02.7** Car data must be readable offline via Firestore's local persistence cache

## FR-03: Photos

- **FR-03.1** The app must request `PHPhotoLibrary` authorization before opening the picker; never at app launch
- **FR-03.2** If authorization is denied, the app must show an alert with a direct link to iOS Settings
- **FR-03.3** Photos must be stored in Firebase Storage at `users/{userId}/cars/{carId}/photo.jpg`
- **FR-03.4** Photo upload must not block saving other car fields; it must proceed in the background
- **FR-03.5** The user must be able to drag the photo vertically to set a crop offset, stored as `photoOffsetY`
- **FR-03.6** Photo removal must be confirmed via a confirmation dialog before deletion
- **FR-03.7** Photo deletion from Firebase Storage must occur immediately on user confirmation, not deferred to save

## FR-04: Notifications

- **FR-04.1** Notification permission must be requested when the user first sets any expiry date, not on first app launch
- **FR-04.2** The app must schedule local notifications at 30 days, 7 days, and on the day of expiry for both insurance and registration
- **FR-04.3** Each notification must carry a deep link payload containing the car ID
- **FR-04.4** Tapping a notification must navigate directly to the relevant car's detail screen
- **FR-04.5** When a car's expiry date is updated, all existing notifications for that car must be cancelled and rescheduled
- **FR-04.6** When a car is deleted, all its associated notifications must be cancelled

## FR-05: Cloud Sync

- **FR-05.1** Firestore offline persistence must be enabled with a minimum 100MB cache
- **FR-05.2** Writes while offline must queue and sync automatically when connectivity is restored
- **FR-05.3** The UI must indicate offline status via a non-blocking banner; it must not prevent the user from reading or creating records
- **FR-05.4** Photo uploads that fail due to network conditions must be retryable without re-selecting the photo

## FR-06: Public / Private Visibility

- **FR-06.1** Every car must default to private (`isPublic = false`) at creation
- **FR-06.2** The user must be able to toggle individual cars public or private from the Car Detail screen
- **FR-06.3** A public car must never expose: VIN, license plate, insurance provider, insurance policy number, insurance expiry date, registration expiry date, or individual maintenance costs
- **FR-06.4** A public car must expose: make, model, year, color, mileage, trim, body style, drive type, engine, fuel type, transmission, photo, notes (if present), and service types + dates (without costs)
- **FR-06.5** Visibility changes must take effect in Firestore immediately on toggle

## FR-07: Social — Follow

- **FR-07.1** Any authenticated user can follow any other user from their public profile
- **FR-07.2** Follower and following counts must update optimistically on action and confirm on Firestore write
- **FR-07.3** The following feed must show new public cars added by followed users in reverse chronological order
- **FR-07.4** Unfollow must require confirmation: "Unfollow {username}?"
- **FR-07.5** A user must be able to block another user; a blocked user cannot view the blocker's profile or cars

## FR-08: Pro Tier

**Positioning (v1.2).** Pro anchors on **metered AI usage** — the Assistant and document scanning. This is deliberate: those are the only features with real recurring marginal cost per use (Anthropic API tokens), which makes charging for them economically honest rather than artificial gating. Car count and the badge remain Pro benefits but are secondary; neither costs anything to serve, and the 3-car limit only binds the minority of users with four or more vehicles.

What Pro is explicitly **not** anchored on, and why:

- **Expense analytics** — the PRD classifies expense aggregation as Tier 1 core. Gating it would contradict this document's own feature tiering.
- **Notification customization** — shipped free to all users; category toggles are table stakes, not a premium feature.
- **Social profile** — free; gating discovery would starve the social graph before it has any density (see R-02).
- **Export** — see FR-15. Free, for the reasons given there.

- **FR-08.1** Free tier is capped at 3 cars; the 4th add attempt surfaces the upgrade sheet
- **FR-08.2** The upgrade sheet must offer both monthly ($2.99) and annual ($24.99) plans; annual shown first as recommended
- **FR-08.3** Pro must be verified via Firestore (`user.isPro = true`), not StoreKit alone, to support cross-device unlock
- **FR-08.4** When a subscription lapses, existing cars must remain readable; only new car additions are blocked. Likewise, Assistant conversation history and previously scanned documents must remain readable — lapsing reduces future allowance, it never destroys or hides data the user already created
- **FR-08.5** "Restore purchase" must be visible on the upgrade screen without scrolling
- **FR-08.6** The app must handle App Store server-to-server notifications for subscription events (renewal, cancellation, billing failure) via Firebase Cloud Functions
- **FR-08.7** Every benefit shown on the upgrade sheet must correspond to a gate actually enforced in code. A benefit that free users already receive must not be advertised as a reason to subscribe. This requirement exists because the v1.1 paywall advertised four benefits, three of which were ungated — see the v1.2 changelog
- **FR-08.8** All Pro-gated limits must be enforced **server-side**, in the Cloud Function that incurs the cost, not client-side. A client-side check is a display convenience, never the enforcement point. (Already true of the Assistant cap per FR-10.5; FR-14 extends this to document scanning)
- **FR-08.9** Every Pro gate must be enumerated in one place in the codebase, so the paywall copy and the enforced gates can be diffed against each other rather than drifting independently

## FR-09: Driver License Storage

- **FR-09.1** Users may optionally store a driver license number, state, and expiry date from the Edit Profile screen
- **FR-09.2** The license number must be rendered via `SecureField` by default, with an eye-icon toggle that flips it to visible plaintext
- **FR-09.3** The license state field must be capped at two characters and auto-uppercased
- **FR-09.4** License fields persist locally only (UserDefaults under `marque_profile_{uid}`) — they must NOT be written to Firestore in v1.0 to avoid syncing high-sensitivity PII across devices
- **FR-09.5** License fields must never appear on any public profile, in Explore results, or in any other user's view
- **FR-09.6** If a license expiry date is set, the app must schedule local notifications at 30 days, 7 days, and on the day of expiry, using the same reschedule-on-change pattern as registration/insurance
- **FR-09.7** Account deletion must clear license fields from local storage (already covered by the existing `marque_profile_{uid}` cleanup in `deleteAccount`)

## FR-10: Marque Assistant

- **FR-10.1** A floating "Ask Marque" button must appear on the primary tab views (Garage, Explore) anchored bottom-right, above the tab bar; it must not overlap primary actions or the "+" tab
- **FR-10.2** Tapping the button opens a chat surface as a bottom sheet at ~90% height with message history, input field, close affordance, and a "New Chat" action. Sheet uses standard iOS sheet detents so the user can dismiss with a downward swipe
- **FR-10.3** From `CarDetailView`, an "Ask Marque about this car" entry point must open the chat pre-scoped to the current car (that car's context is injected into the system prompt)
- **FR-10.4** Free tier is capped at 10 assistant messages per calendar day (device local time, reset at midnight); Pro users have no daily cap (subject to an abuse throttle at 500/day). Starting cap is intentionally conservative — revisit after 30 days of production data
- **FR-10.5** The daily cap must be enforced server-side in the `askMarque` Cloud Function, not client-side. The client sends its local date (`yyyy-mm-dd`) with each request; the function increments a Firestore counter at `users/{uid}/usage/assistant_{yyyy-mm-dd}` and rejects the call if it exceeds the cap for that user's tier
- **FR-10.6** When the cap is reached, the message input must be disabled with a countdown to reset time and an upgrade sheet must be shown offering the Pro upsell
- **FR-10.7** The assistant must have read-only access to the user's garage data (cars, maintenance records, expenses, expiry dates), passed as a serialized context block to the Cloud Function on each request. The assistant must never mutate CarStore or Firestore data on the user's behalf in v1.1
- **FR-10.8** The backend must use Claude Sonnet 4.6 (`claude-sonnet-4-6`) via the existing `defineSecret("ANTHROPIC_API_KEY")` pattern; prompt caching must be enabled on the garage context block and the system prompt to reduce per-message cost. Model ID must be a string constant at the top of the Cloud Function file so it can be bumped in one place
- **FR-10.9** Conversations must persist in Firestore at `users/{uid}/conversations/{convId}/messages/`; each message stores role, content, timestamp, and (for assistant messages) the model used and token counts. A conversation list must be accessible from the chat surface
- **FR-10.10** The assistant's system prompt must (a) constrain responses to automotive topics with graceful decline on off-topic questions, (b) prefer facts derivable from the user's garage over generic advice when relevant, and (c) require recommending professional inspection for safety-critical concerns (brakes, suspension, steering, tires, structural)
- **FR-10.11** A first-use disclaimer must be shown as a chip in the empty conversation state: "Marque assists but doesn't replace a mechanic. For safety issues, get professional inspection."
- **FR-10.12** If the network is unavailable, the chat surface must show a non-blocking banner and disable the input; queued messages must not be silently sent later
- **FR-10.13** Assistant responses must be streamed to the client as tokens arrive (Anthropic streaming API). A visible loading indicator must appear within 300ms of send. Non-streaming delivery is not acceptable for v1.1 — the perceived latency degrades the chat experience
- **FR-10.14** Failed messages (network error, function error, model refusal) must not count against the daily cap; the message input must offer a Retry action
- **FR-10.15** Account deletion must delete all `conversations` subcollections alongside the existing cascade

### FR-10 — Data Scope in Context

- **FR-10.16** The garage-context block passed to the Cloud Function must include, per car: make, model, year, trim, mileage, engine, fuel type, transmission, drive type, body style, color, registration expiry date, insurance expiry date, and maintenance records from the last 12 months (type, date, mileage, shop). It must also include aggregate expense totals YTD (overall + by category)
- **FR-10.17** The context block must NEVER include: VIN, license plate, insurance provider, insurance policy number, driver license fields, per-record maintenance costs beyond aggregate totals, notes fields (any free-text field the user may have populated), or photo file names. This protects sensitive fields even if the model tries to echo them back
- **FR-10.18** If the assistant needs data outside the context block (e.g., a specific maintenance record's cost), it must ask the user rather than have the client re-send additional context. Keeps context deterministic and cache-friendly

### FR-10 — Conversation Lifecycle

- **FR-10.19** A user may retain up to 50 conversations; on creating the 51st, the oldest un-pinned conversation is auto-deleted. Users may pin up to 10 conversations to exempt them from auto-deletion
- **FR-10.20** Within a single conversation, the last 30 turns are sent as message history to the model. Older turns are omitted (not summarized) — this is a v1.1 simplification; summarization can come in v1.2 if 30 turns proves insufficient
- **FR-10.21** Users may delete individual conversations via swipe-to-delete from the conversation list. Deletion is immediate and unconfirmed (matches iOS mail conventions)

### FR-10 — Phased Rollout

- **FR-10.22** v1.1 must ship behind a Firebase Remote Config flag (`marque_assistant_enabled`, default false). The flag is enabled for TestFlight builds first (small cohort: the founder + a handful of hand-picked testers), then flipped to 100% of production once qualitative validation is complete. At this scale, statistical thresholds (cap-hit rate, cost trends) will be too thin to be meaningful; the gate is qualitative — no critical bugs, no clearly hallucinated advice on safety-critical topics, and per-user cost within the napkin-math envelope in R-12. A percentage rollout stage can be added later when the user base grows enough to make it useful
- **FR-10.23** The Cloud Function must log per-request telemetry (uid, model, input tokens, output tokens, cache hit rate, latency, error code if any) for cost attribution and quality monitoring. Formal success metrics targets in Section 9 are intentionally deferred until there is a large enough user base to measure against; telemetry is the source of truth in the meantime

---

## FR-11: Analytics & Instrumentation

Section 9 defines roughly twenty success metrics. Prior to v1.2 nothing measured any of them — the app did not link an analytics SDK at all. Every target in Section 9 was therefore unfalsifiable. This section exists so that the launch described by this document can actually be evaluated.

**Tool:** PostHog. Chosen over Firebase Analytics because Section 9 is dominated by retention curves and funnels, which are first-class in PostHog and require BigQuery export plus SQL in GA4. Free tier (~1M events/month) exceeds projected volume by a wide margin at the scale in Section 9.

- **FR-11.1** Every metric in Section 9 must be derivable from instrumented events. A metric that cannot be computed from the event stream must either gain an event or be removed from Section 9 — no metric may remain aspirational
- **FR-11.2** Events use `snake_case`, named as `object_verb` in the past tense (`car_added`, `paywall_viewed`, `purchase_completed`)
- **FR-11.3** Users are identified by Firebase `uid`, so analytics identity survives reinstall and matches server-side records. Anonymous pre-signup events must be aliased to the `uid` on signup so the install → signup funnel remains connected
- **FR-11.4** The minimum event set:

| Event | Key properties | Serves |
|---|---|---|
| `app_opened` | `is_first_open` | D1/D7/D30 retention |
| `app_launch_completed` | `duration_ms` | Cold launch <2s |
| `onboarding_step_viewed` | `step` | FR-13 funnel, R-01 |
| `onboarding_completed` | `added_car`, `skipped` | R-01 |
| `signup_completed` | `method` (apple/google/email) | Signup rate, auth distribution |
| `car_added` | `entry_method` (vin/manual), `seconds_since_signup` | Activation, time-to-first-car |
| `car_photo_added` | — | Photo upload rate |
| `maintenance_record_added` | — | Records per active car |
| `car_visibility_changed` | `is_public` | Public car rate |
| `user_followed` | — | Follow rate |
| `notification_permission_result` | `granted` | Opt-in rate |
| `assistant_message_sent` | `was_scoped_to_car` | Assistant engagement |
| `assistant_cap_reached` | — | Pro demand signal |
| `document_scan_completed` | `doc_type` | Scanning engagement |
| `document_scan_cap_reached` | — | Pro demand signal |
| `paywall_viewed` | `trigger` (car_limit/assistant_cap/scan_cap/settings) | Which gate actually converts |
| `purchase_completed` | `plan` (monthly/annual) | Conversion, plan split |

- **FR-11.5** `paywall_viewed.trigger` is the single most important property in this table. It is the only way to learn which Pro gate drives revenue, which directly determines whether the FR-08 positioning is correct. It must never be omitted
- **FR-11.6** Analytics must never receive: VIN, license plate, insurance provider or policy number, driver license fields, email address, free-text notes, photo contents, or Assistant message bodies. This matches the PII discipline already required by FR-06.3 and FR-10.17. Event properties carry counts, enums, and booleans — not user content
- **FR-11.7** No IDFA collection and no cross-app tracking. Analytics are first-party product measurement only, which keeps the app outside App Tracking Transparency prompt requirements. Adding any attribution SDK would change this and requires revisiting
- **FR-11.8** Crash reporting is **not** covered by PostHog. The >99.5% crash-free target in Section 9 requires a separate crash reporter (Firebase Crashlytics is the natural fit given the existing Firebase dependency). Section 9's quality metrics are not measurable until this is added
- **FR-11.9** Instrumentation must ship *before* launch, not after. Retention and activation metrics cannot be backfilled — a cohort not measured on day one is lost permanently

## FR-12: Accessibility

Absent from v1.0 and v1.1 entirely. Specified now because retrofitting Dynamic Type into a finished SwiftUI layout costs substantially more than building with it.

- **FR-12.1** All text must use Dynamic Type text styles rather than fixed point sizes, and must remain legible and non-truncating through the `.accessibility3` size class. Layouts must reflow rather than clip
- **FR-12.2** Every interactive control must have an accessibility label. This applies especially to icon-only buttons, of which the app has several (Settings gear, notifications bell, Ask Marque). An unlabeled icon button is unusable with VoiceOver
- **FR-12.3** Interactive targets must be at least 44×44pt, per Apple's Human Interface Guidelines
- **FR-12.4** Text and meaningful UI must meet WCAG AA contrast (4.5:1 for body text, 3:1 for large text) in both light and dark appearance
- **FR-12.5** Information must never be conveyed by color alone. Expiry state in particular — currently communicated by red/orange banners — must also carry text or an icon, since red/green distinction is the most common form of color vision deficiency
- **FR-12.6** Animations must respect Reduce Motion
- **FR-12.7** Every screen must be verified with VoiceOver enabled and Dynamic Type at maximum before release. This is a manual pass; no automated tooling substitutes for it

## FR-13: Onboarding & Activation

R-01 (low activation) is the only High-likelihood / High-impact risk in Section 10, and prior to v1.2 its entire mitigation was a single sentence in a risk table. This section makes it a requirement.

- **FR-13.1** Onboarding must end with a car saved to the user's garage, not at an empty Garage screen. An empty garage is the failure state R-01 describes, not a successful onboarding outcome
- **FR-13.2** The first-run sequence is: value framing → authentication → profile setup (username required, per FR-01.6) → **add first car** → Garage
- **FR-13.3** The add-first-car step must offer both VIN and manual entry with equal prominence. VIN is faster when the user is standing at the car; manual is the only option when they are not
- **FR-13.4** A skip affordance must exist — a user who cannot complete this step must not be trapped — but it must be visually secondary, and skipping must route to a Garage empty state carrying the same add-car call to action
- **FR-13.5** Every step must emit `onboarding_step_viewed` (FR-11.4) so the drop-off point is identifiable. R-01 cannot be managed without knowing *where* users abandon
- **FR-13.6** Notification permission must not be requested during onboarding. FR-04.1 already defers it to the first expiry-date entry; onboarding must not pre-empt that
- **FR-13.7** Time from `signup_completed` to first `car_added` is the primary activation measure, targeted at under 3 minutes per Section 9

## FR-14: Document Scanning

Shipped and in production — three Cloud Functions parse insurance cards, registrations, and maintenance receipts. This document previously listed document handling only as a deferred v2 *non-goal*, which was wrong in both directions: the feature exists, and it now carries Pro-tier significance under FR-08.

- **FR-14.1** Users may capture or select an image of a **driver license, insurance card, or maintenance receipt**, and have its fields extracted into the corresponding structured record. (v1.2 initially wrote "vehicle registration" here in place of driver license; the shipped scanners are `driverLicense`, `insuranceCard`, `maintenanceReceipt` per `DocumentScanService.DocumentKind` and the three matching Cloud Functions. Registration is manual-entry only — there is no registration parser. Corrected rather than treated as a missing feature, since nothing suggests a registration scanner was ever intended)
- **FR-14.2** Extraction runs server-side in a Cloud Function. The client must never call an AI provider directly, so that API credentials, quota enforcement, and cost attribution stay server-controlled — consistent with FR-10.5
- **FR-14.3** Extracted fields must be presented for user review and correction before being saved. Parsing is assistive; it must never write to a record without confirmation
- **FR-14.4** Free tier is limited to a daily document-scan allowance; Pro raises it. Like the Assistant cap, the limit must be enforced server-side per FR-08.8, and the remaining allowance must be visible *before* a scan is attempted, not surfaced as a failure afterward
- **FR-14.5** Scan failures — unreadable image, unrecognized document type, provider error — must not count against the allowance, matching FR-10.14
- **FR-14.6** Source images must not be retained server-side after extraction completes. Only the structured fields the user confirms are persisted. Insurance cards and registrations carry exactly the identifiers FR-06.3 and FR-10.17 already forbid exposing elsewhere
- **FR-14.7** Per-request telemetry equivalent to FR-10.23 (uid, document type, token counts, latency, error code) must be logged for cost attribution, since this feature now shares the Pro-tier cost thesis with the Assistant

## FR-15: Data Export

Repositioned in v1.2. The original framing — a PDF service history to show a prospective buyer — does not withstand scrutiny: a seller-generated document is unverified, and buyers already rely on Carfax for third-party-verified accident and title history. What survives is the case Carfax does not serve at all.

- **FR-15.1** Export is **free**, not a Pro benefit. It is not differentiated enough to anchor a subscription (see FR-08 positioning), and its strongest use case is periodic rather than recurring
- **FR-15.2** The primary use case is **tax and business expense reporting** — contractors, rideshare, and delivery drivers deducting vehicle expenses. Carfax is irrelevant here and an accountant needs categorized totals, not vehicle history
- **FR-15.3** Two formats, because they serve different readers: **PDF** for a human-readable service and expense report, and **CSV** for expense line items, which is what an accountant or spreadsheet actually wants
- **FR-15.4** Export scope is selectable: a single car or the whole garage, filtered by an `ExpensePeriod` consistent with the existing expense views
- **FR-15.5** The export includes vehicle identity, the full service log (date, mileage, service type, shop, cost, notes), and expense totals by category. Unlike public cars (FR-06.3), nothing is redacted — this is the user's own data being handed to the user
- **FR-15.6** Delivery is via the standard iOS share sheet, so the user chooses the destination. The app must not email, upload, or transmit the export anywhere on the user's behalf
- **FR-15.7** Separately from the product feature, the user must be able to request a complete machine-readable export of their account data (JSON), satisfying GDPR Article 20 data portability. R-10 commits to the deletion half of GDPR compliance; this is the other half

## FR-16: AI Service Suggestions

Added in v1.2 to document a feature the iOS client already contained and this document never mentioned. The Suggested Reminders sheet asks an AI model for service reminders specific to the car, and falls back to the rule-based `ServiceReminderEngine` whenever the AI path is unavailable. Unlike FR-10 and FR-14 it is deliberately **not** a Pro lever: the output is short and structured, the model is lightweight, and gating it would add a paywall benefit that FR-08.7 and FR-08.9 would then require us to keep in sync with an enforced gate.

- **FR-16.1** The sheet requests AI-generated reminders for a car: 3–6 suggestions, each with a service type, a due date and/or due mileage, a one-sentence reason specific to the car, and a priority. Suggestions are proposals — no reminder is created until the user reviews the list and taps Add
- **FR-16.2** Generation runs server-side in a Cloud Function. The client must never call an AI provider directly, consistent with FR-10.5 and FR-14.2
- **FR-16.3** The feature is free for all users and must not appear in paywall copy. A flat per-user cap of **10 requests per day**, identical for free and Pro, exists solely as an abuse guard and must be enforced server-side per FR-08.8. Because the sheet requests on every open, the cap must be high enough that a normal user never sees it; if `resource-exhausted` responses appear in ordinary use in the logs, raise it
- **FR-16.4** The cap's counter is keyed by the client's local date, so that date must be validated against server time — accepted only within one day of the server's UTC date. An unvalidated key lets a client mint a fresh allowance on every call. The same rule applies to the FR-10 and FR-14 counters. One day of tolerance narrows the abuse rather than closing it: a modified client can still reach up to three counters per UTC day
- **FR-16.5** Request size must be bounded server-side so a client cannot inflate the cost of an individual call: at most 100 maintenance records and 50 active reminders, short length-limited text fields, and only whitelisted fields are read. Worst case is roughly 20K characters of input (about 5–6K tokens); output is capped at 2,048 tokens
- **FR-16.6** A request that fails — provider error, unparseable response — must not count against the cap, matching FR-10.14 and FR-14.5. A successful request that returns zero suggestions does count, because it incurred cost
- **FR-16.7** When the cap is reached, or on any error, or when the device is offline, or when the AI returns nothing, the sheet must show the rule-based suggestions with a short explanatory hint. The user is never left at a dead end
- **FR-16.8** Data sent to the model is limited to: make, model, year, trim, mileage, fuel type, transmission, drive type, engine, body style; the last 24 months of service records (service type, date, mileage); and active reminders (service type, due date, due mileage). Never VIN, license plate, insurance details, driver license, costs, shop names, notes, or photo names — the same exclusions as FR-10.17
- **FR-16.9** Per-request usage telemetry (uid, reserved count, token counts, latency) must be logged for cost attribution, equivalent to FR-10.23 and FR-14.7

---

# Section 8 — Edge Cases

| ID | Scenario | Expected Behavior |
|---|---|---|
| EC-01 | User adds a car, immediately goes offline before Firestore write completes | Write queued; car shows in UI immediately; syncs on reconnect; no data lost |
| EC-02 | Two devices logged into same account simultaneously add a car | Firestore last-write-wins; both cars appear; no conflict |
| EC-03 | VIN decode returns partial data (some fields missing) | Available fields pre-filled; empty fields left blank for manual entry |
| EC-04 | User adds 3 cars, hits paywall, purchases Pro, then cancels subscription within 7 days (Apple refund) | Firestore updated via server notification; free limit reinstated; existing 3 cars unaffected |
| EC-05 | User attempts to sign up with email already linked to an Apple ID | "An account with this email exists. Sign in with Apple instead?" prompt with Apple button |
| EC-06 | Photo upload fails after car is already saved | Car saved without photo; car detail shows "Photo didn't upload. [Retry]" |
| EC-07 | User sets a registration expiry date in the past | Notification scheduled for the past silently dropped; expiry banner shows "Expired" in UI |
| EC-08 | User deletes account with 3 public cars | All Firestore documents deleted; Firebase Storage files deleted; follow relationships removed; public profile becomes 404 |
| EC-09 | User makes a car public then immediately deletes it | Car removed from Explore feed; anyone who bookmarked a direct link sees "This car is no longer available" |
| EC-10 | VIN search returns a result for a car with a non-English make name | Normalized against the `CarData.makes` list; falls back to raw API value if no match |
| EC-11 | User taps notification for a car that has been deleted | Deep link resolves; car not found; user lands on My Garage with no error message |
| EC-12 | User reinstalls the app with an active Pro subscription | Firebase Auth restores session; Firestore `isPro` flag restores Pro features; no re-purchase required |
| EC-13 | User opens app in airplane mode on first install | Auth cannot complete; "You need an internet connection to create your account" |
| EC-14 | User enters a duplicate username during profile setup | Real-time check shows "taken" before they submit; suggestions offered |
| EC-15 | User uploads a very large photo (12MP+ iPhone camera) | Photo compressed to JPEG at 0.8 quality before upload; original not stored |
| EC-16 | User asks the assistant about a car not in their garage (e.g., "should I buy a Miata?") | Assistant responds with generic advice; does not fabricate ownership details about the user's cars |
| EC-17 | User hits the 10-message daily cap mid-conversation | Input disabled with countdown to reset; upgrade sheet offered; existing conversation remains scrollable and re-readable |
| EC-18 | User asks a safety-critical question ("my brakes feel spongy", "I hear grinding when turning") | Assistant provides contextual information but explicitly recommends immediate mechanic inspection |
| EC-19 | Cloud Function times out or returns an error mid-message | Chat shows "Marque couldn't answer. Try again?" with a Retry button; the message is NOT counted against the daily cap |
| EC-20 | User asks an off-topic question ("write me a poem", "what's the weather?") | Assistant declines briefly and redirects back to automotive topics without a lecture |
| EC-21 | User with an empty garage opens the assistant | Assistant works normally for general questions; a hint suggests adding a car for personalized answers |
| EC-22 | User deletes account while active conversations exist | All `conversations` subcollections deleted alongside cars, per the account-deletion cascade |

---

# Section 9 — Success Metrics

**Every metric below is now backed by an instrumented event (FR-11.4).** Prior to v1.2 none of them were measurable. Any metric added here in future must arrive with its event, or it is aspiration rather than measurement.

## North Star

| Metric | Definition | Why this one |
|---|---|---|
| **Weekly active garages with a maintenance record added in the last 90 days** | Distinct users who opened the app this week *and* have logged at least one service record in the trailing 90 days | Twenty metrics with no hierarchy gives no basis for trading one against another. This is the single number that captures the product actually working: a user who logs maintenance has moved past storing a car photo into treating Marque as their system of record. It is the behavior that predicts retention, makes the Assistant useful (it needs history to be specific), and makes export worth generating. Install and signup counts can be bought; this cannot |

Supporting metrics below are diagnostic — they explain *why* the North Star moves, and should not be optimized against individually at its expense.

## Acquisition

| Metric | Target (30 days post-launch) |
|---|---|
| App Store installs | 2,500 |
| Signup completion rate (install → account created) | >60% |
| Auth method distribution | Apple >50%, Google >30%, Email <20% |

## Activation

| Metric | Target |
|---|---|
| Time to first car added | <3 minutes from signup |
| D1 activation (adds at least 1 car on day 1) | >50% of signups |
| Photo upload rate | >40% of cars have a photo within 7 days |
| Notification opt-in rate | >50% of users who set an expiry date |

## Engagement

| Metric | Target (Day 30) |
|---|---|
| D7 retention | >35% |
| D30 retention | >20% |
| Cars per active user | >1.8 |
| Maintenance records per active car | >2 |
| Public car rate | >20% of users make at least one car public |
| Follow rate (users who follow at least one person) | >15% |

## Monetization

| Metric | Target (90 days) |
|---|---|
| Paywall conversion rate | >3% of active free users |
| Annual vs monthly split | >60% annual |
| MRR | $500 (proves model; not a scale target) |
| Churn rate (monthly Pro) | <8%/month |

## Quality

| Metric | Target |
|---|---|
| Crash-free session rate | >99.5% |
| App Store rating | >4.3 stars |
| Cold launch time | <2 seconds |
| Firestore sync success rate | >99.9% |

---

# Section 10 — Launch Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-01 | Low activation — users sign up but don't add a car | High | High | **FR-13** specifies the onboarding flow (ends at a saved car, not an empty Garage) and **FR-11.4** instruments each step so the drop-off point is identifiable. Prior to v1.2 this mitigation was a sentence with no requirement and no measurement behind it — the highest-rated risk in this document was both unspecified and invisible |
| R-02 | Social layer feels empty at launch (no one to follow) | High | Medium | Pre-seed with founder accounts and curated public garages |
| R-03 | Firebase costs spike unexpectedly | Medium | High | Set Firebase budget alerts at $50/month; enforce photo compression; cache aggressively |
| R-04 | App Store rejection for Sign in with Apple parity | Medium | High | Apple requires Apple login to be equal prominence; design per HIG |
| R-05 | NHTSA API downtime breaks Add Car flow | Low | High | Fallback message with manual entry path always available |
| R-06 | StoreKit purchase loop or double-charge | Low | High | Test all StoreKit edge cases with Sandbox; idempotent purchase handling |
| R-07 | User data loss on UserDefaults → Firestore migration | Low | Very High | Import is additive only; never delete UserDefaults until Firestore write confirmed |
| R-08 | Content moderation exposure (public profiles) | Medium | Medium | Block and report flows from day one; Firebase App Check; ToS prohibiting illegal content |
| R-09 | Negative reviews from confusing UX for non-enthusiasts | Medium | Medium | Normal users should never see social features until they choose to |
| R-10 | GDPR / CCPA compliance gap | Low | High | Privacy policy on file before launch; "Delete Account" must actually delete all data (deletion cascade verified and deployed, including server-side cleanup of paths the client cannot reach); **FR-15.7** adds the Article 20 data-portability half, previously missing |
| R-11 | Assistant hallucinates incorrect car advice (wrong specs, wrong service intervals, unsafe DIY guidance) | Medium | High | System prompt constrains scope and forbids diagnostic certainty; safety disclaimer chip on first use; explicit "see a mechanic" language for safety-critical topics; read-only in v1 (no data mutations from the assistant); monitor user reports |
| R-12 | Anthropic API costs exceed budget as assistant usage scales | Medium | Medium | Server-side 10-msg/day cap for free tier; per-user 500/day abuse throttle for Pro; prompt caching on garage context block reduces repeated input token cost by ~90% within a conversation. **Cost math (Sonnet 4.6):** at 500 active users × 10 msg/day × ~2k input + 500 output tokens per turn with cache, expected spend is ~$150–300/month. At the 30-day install target (2,500 installs, ~50% activation → ~1,250 active users), expected spend is ~$400–800/month. Set Cloud Function budget alert at $500/month (soft warning) and $1,000/month (hard cap that pages the founder); revise thresholds based on actual usage after week 1. **v1.2 note:** document scanning (FR-14) draws on the same budget and must be included in these thresholds — the original math counted Assistant traffic only. **FR-16 note:** AI service suggestions are a third cost surface and are deliberately free for all users. They use a lightweight model with short structured output behind a flat 10 requests/day per-user abuse cap and server-side input bounds (worst case about 5–6K input tokens and at most 2,048 output tokens per request), so worst-case spend per user per day is bounded regardless of what a modified client sends — allow up to 3x for the one-day clock tolerance in FR-16.4. Include this function in the same budget alerts |
| R-13 | Pro value proposition is too thin to convert at the >3% target | High | High | Under FR-08, Pro now rests primarily on raising AI limits. If the free Assistant and scan allowances are set generously enough that few users ever reach them, there is no felt reason to upgrade; set too tightly, the free tier stops demonstrating value and hurts activation (R-01). This tension is not resolvable from first principles — it is an empirical calibration. `assistant_cap_reached`, `document_scan_cap_reached`, and `paywall_viewed.trigger` (FR-11.4) exist specifically to measure it. Revisit both allowances after 30 days of real usage rather than guessing pre-launch |
| R-14 | Advertised Pro benefits drift from enforced gates | Medium | Medium | This already happened: the v1.1 paywall advertised four benefits, three of which free users already received in the shipped build. It was caught by code review, not by anything structural. **FR-08.7** forbids advertising an unenforced benefit and **FR-08.9** requires the gates be enumerated in one place so copy and enforcement can be diffed. Treat any change to paywall copy as requiring a check against that list |

---

# Section 11 — MVP Definition

### What is in v1.0 MVP

**Must ship:**
- Sign in with Apple, Google, Email (+ email verification)
- Profile setup (username required; photo, bio optional)
- Local data import (for existing prototype users)
- Full garage experience: add by VIN/manual, edit, delete, photo, maintenance log, expense view
- Expiry notifications with deep links
- Firestore cloud sync + offline mode
- Public/Private per-car toggle
- Public profile page (read-only)
- Follow / Unfollow
- Following feed (chronological)
- Explore tab (public garages, basic search)
- Paywall at 3-car limit + Pro subscription (monthly + annual)
- Block and report (required for App Store social features approval)
- Privacy policy + Terms of Service in-app

**Added to v1.0 scope in v1.2** — these are not new features so much as requirements the launch was already depending on:
- Analytics instrumentation (FR-11) — **blocking**. Without it, nothing in Section 9 is measurable and the launch cannot be evaluated
- Onboarding flow (FR-13) — **blocking**. Mitigates R-01, the highest-rated risk
- Accessibility baseline (FR-12)
- Crash reporting (FR-11.8) — required by the >99.5% crash-free target

**Cut from v1.0, ship in v1.1:**
- Comments on public cars
- Likes / reactions
- Following feed notifications
- ~~Follower/following list screens~~ (shipped in v1.1)
- ~~PDF export (teased as Pro feature, delivered in v1.1)~~ — **superseded in v1.2.** This line contradicted Section 5, which listed PDF export as part of the v1.0 Pro tier; it was built in neither version. Export is now free and rescoped to tax/expense reporting (FR-15), targeted at v1.2

### What is in v1.1

Additive on top of v1.0. Ships behind a Remote Config flag; graduates to public release only after 7 days of TestFlight + limited-rollout telemetry.

**Must ship:**
- Marque Assistant (floating "Ask Marque" chatbot, 10 msg/day free / unlimited Pro, read-only in v1)
- Streaming responses (Anthropic streaming API — non-streaming is not acceptable)
- Conversation persistence in Firestore with 50-conversation retention + pin support
- `askMarque` Cloud Function on Sonnet 4.6, with server-side rate limit, prompt caching, and per-request telemetry
- Safety disclaimer chip on first use
- Assistant entry point on Car Detail (per-car scoping)
- Follower/following list screens (accessible from both own profile and public profiles)
- Remote Config flag (`marque_assistant_enabled`) for phased rollout
- Cloud Function budget alerts wired ($500 soft / $1,000 hard)

**Deferred to v1.2:**
- Write actions (assistant proposes → user confirms → assistant creates reminders/records)
- Multi-turn context summarization (v1.1 hard-caps at 30 turns)

### What is in v1.2

- Analytics instrumentation (FR-11) and crash reporting — prerequisites for evaluating v1.0, so these ship with or before launch rather than after
- Onboarding flow (FR-13)
- Accessibility baseline (FR-12)
- Pro tier repositioned onto metered AI (FR-08), with document-scan allowances enforced server-side (FR-14.4)
- Paywall copy reconciled against enforced gates (FR-08.7)
- Data export, free (FR-15)
- AI service suggestions, free behind a flat server-side abuse cap (FR-16)
- Smartcar integration deleted (Appendix A)

### Definition of Done for MVP

The MVP is complete when:
1. A new user can sign up, add a car by VIN, receive an expiry notification, and make their car public in under 5 minutes on a production build
2. A returning user can open the app offline and see their full garage
3. A user with 4 cars is prompted to upgrade and can complete a purchase
4. The app passes App Store review and is live in the App Store
5. Crash-free rate is above 99% on first 48 hours of production traffic

---

# Appendix A — Out-of-Scope Features (Parking Lot)

| Feature | Target Version | Notes |
|---|---|---|
| DM / Chat | v2.0 | Requires moderation; complex push infra |
| Fuel logbook | v2.0 | High-frequency use case; justified after retention proven |
| ~~Document storage~~ | — | **Shipped.** Document scanning went to production ahead of this parking-lot entry; see FR-14. Entry retained struck-through so the discrepancy isn't rediscovered as a new idea |
| Car valuation | v2.0 | Third-party data licensing cost |
| Android | v2.0 | After iOS PMF confirmed |
| Marketplace | v3.0 | Different product; different legal surface |
| Business / dealer accounts | v3.0 | B2B motion; different GTM |
| Apple Watch | v3.0 | Nice-to-have; low user value at this stage |
| Remote push (APNs) | v1.3 | **Gap identified in v1.2.** Every notification in the app today is local — scheduled on-device for expiry dates. Nothing can reach a user who hasn't opened the app, which means a new follower produces no re-engagement. The social layer's contribution to the D7/D30 targets in Section 9 is structurally capped without this. Deferred rather than specified because it needs a server-side push service, APNs certificates, and a notification-preference model that respects FR-04.1's permission discipline — a real project, not an addition |
| Smartcar / telematics | **Abandoned** | Built as a working prototype — `SmartcarStore`, three Cloud Functions (`smartcarExchangeCode`, `smartcarReadOdometer`, `smartcarDisconnect`), and Car Detail UI — then left disabled behind `isEnabled = false` and never documented in this PRD at all. Deleted in v1.2. The single feature it delivered (odometer auto-sync) did not justify the OAuth flow, per-read vendor cost, and ongoing integration maintenance. Recorded here so the idea is not re-proposed without remembering it was tried |
| Account linking UI | Post-launch | Managing multiple sign-in providers per account. The failure it prevents — losing access to your only provider — is real but rare, and manual support recovery is an adequate fallback at current scale. Distinct from FR-01.5, which handles the more common and more damaging case of a signup colliding with an existing email and is *not* deferred |

---

# Appendix B — Assumptions

1. Firebase free tier is sufficient for the first 1,000 active users without billing
2. NHTSA VPIC API remains free and publicly available without an API key
3. Apple's App Store review will not flag the social features if block/report is implemented
4. Users will accept a 3-car free limit without significant churn if the value per car is high enough
5. The target demographic (car owners in the US) is sufficiently iOS-dominant to justify iOS-first
6. **(v1.2)** Enough users will hit the free Assistant and document-scan allowances often enough to feel the limit, and will value crossing it at $2.99/month. This is the central monetization assumption after the FR-08 repositioning and it is unvalidated — the app has no real users yet. R-13 tracks it; `assistant_cap_reached`, `document_scan_cap_reached`, and `paywall_viewed.trigger` are the instruments that will confirm or refute it
7. **(v1.2)** PostHog's free tier remains sufficient at the scale described in Section 9, and first-party product analytics continue not to require an App Tracking Transparency prompt (which holds only as long as FR-11.7's no-IDFA, no-cross-app-tracking constraint is respected)

---

# Appendix C — Glossary

| Term | Definition |
|---|---|
| VIN | Vehicle Identification Number — 17-character unique vehicle code |
| NHTSA | National Highway Traffic Safety Administration — US agency providing the free VIN decode API |
| Firestore | Google Firebase's NoSQL cloud database |
| Firebase Storage | Google Firebase's file storage service |
| isPublic | Per-car boolean field controlling whether a car appears on the user's public profile and in Explore |
| isPro | Per-user boolean field in Firestore controlling Pro feature access |
| photoOffsetY | Stored vertical offset for the car photo crop position |
| Deep link | A URL or notification payload that opens the app to a specific screen |
| Expiry banner | The red/orange warning shown in Car Detail when insurance or registration is expired or expiring |
| Activation | A user has added at least one car to their account |
| Marque Assistant | The in-app conversational agent that answers car-related questions using the user's garage as context and Claude as the underlying model |
| askMarque | The Cloud Function that proxies assistant chat requests to the Anthropic API and enforces the daily message cap |
| Assistant message cap | The rolling 24-hour limit on assistant messages for free-tier users (10/day); Pro users are subject only to an abuse throttle (500/day) |
| Prompt caching | Anthropic-side feature that caches static context blocks (like the user's garage) across turns to reduce token cost |

---

*This document represents the complete product requirements for Marque v1.0. It supersedes all prior informal discussions, wireframes, and planning notes. Any scope changes require a documented revision with version bump.*

