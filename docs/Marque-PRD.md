# Marque — Product Requirements Document

**Version:** 1.0
**Status:** Ready for Development
**Author:** Product
**Last Updated:** April 2026
**Audience:** Engineering, Design, Investors

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
| Document storage (PDFs, receipts) | Storage costs, camera UX complexity; v2 |
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
| **Local Data Import** | Migrate existing prototype data to cloud on first login | P1 |
| **Pro Tier** | Unlimited cars, PDF export, Pro badge via monthly/annual subscription | P1 |

## Tier 3 — Social Layer (v1.0 New)

| Feature | Description | Priority |
|---|---|---|
| **Public/Private Toggle** | Per-car visibility control, default private | P0 |
| **Public Profile** | Read-only view of another user's public garage | P1 |
| **Follow / Unfollow** | Follow other users; see their new cars in a following feed | P1 |
| **Explore** | Browse public garages, search by make/model/username | P1 |
| **Following Feed** | Chronological list of new cars from followed users | P1 |

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

- **FR-08.1** Free tier is capped at 3 cars; the 4th add attempt surfaces the upgrade sheet
- **FR-08.2** The upgrade sheet must offer both monthly ($2.99) and annual ($24.99) plans; annual shown first as recommended
- **FR-08.3** Pro must be verified via Firestore (`user.isPro = true`), not StoreKit alone, to support cross-device unlock
- **FR-08.4** When a subscription lapses, existing cars must remain readable; only new car additions are blocked
- **FR-08.5** "Restore purchase" must be visible on the upgrade screen without scrolling
- **FR-08.6** The app must handle App Store server-to-server notifications for subscription events (renewal, cancellation, billing failure) via Firebase Cloud Functions

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

---

# Section 9 — Success Metrics

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
| R-01 | Low activation — users sign up but don't add a car | High | High | Empty state with clear CTA; onboarding ends at Add Car, not at Garage |
| R-02 | Social layer feels empty at launch (no one to follow) | High | Medium | Pre-seed with founder accounts and curated public garages |
| R-03 | Firebase costs spike unexpectedly | Medium | High | Set Firebase budget alerts at $50/month; enforce photo compression; cache aggressively |
| R-04 | App Store rejection for Sign in with Apple parity | Medium | High | Apple requires Apple login to be equal prominence; design per HIG |
| R-05 | NHTSA API downtime breaks Add Car flow | Low | High | Fallback message with manual entry path always available |
| R-06 | StoreKit purchase loop or double-charge | Low | High | Test all StoreKit edge cases with Sandbox; idempotent purchase handling |
| R-07 | User data loss on UserDefaults → Firestore migration | Low | Very High | Import is additive only; never delete UserDefaults until Firestore write confirmed |
| R-08 | Content moderation exposure (public profiles) | Medium | Medium | Block and report flows from day one; Firebase App Check; ToS prohibiting illegal content |
| R-09 | Negative reviews from confusing UX for non-enthusiasts | Medium | Medium | Normal users should never see social features until they choose to |
| R-10 | GDPR / CCPA compliance gap | Low | High | Privacy policy on file before launch; "Delete Account" must actually delete all data |

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

**Cut from v1.0, ship in v1.1:**
- Comments on public cars
- PDF export (teased as Pro feature, delivered in v1.1)
- Likes / reactions
- Following feed notifications
- Follower/following list screens

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
| Document storage | v2.0 | Storage costs; camera UX complexity |
| Car valuation | v2.0 | Third-party data licensing cost |
| Android | v2.0 | After iOS PMF confirmed |
| Marketplace | v3.0 | Different product; different legal surface |
| Business / dealer accounts | v3.0 | B2B motion; different GTM |
| Apple Watch | v3.0 | Nice-to-have; low user value at this stage |

---

# Appendix B — Assumptions

1. Firebase free tier is sufficient for the first 1,000 active users without billing
2. NHTSA VPIC API remains free and publicly available without an API key
3. Apple's App Store review will not flag the social features if block/report is implemented
4. Users will accept a 3-car free limit without significant churn if the value per car is high enough
5. The target demographic (car owners in the US) is sufficiently iOS-dominant to justify iOS-first

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

---

*This document represents the complete product requirements for Marque v1.0. It supersedes all prior informal discussions, wireframes, and planning notes. Any scope changes require a documented revision with version bump.*

