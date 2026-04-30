# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Marque is an iOS app (SwiftUI, iOS 17.6+, Swift 5, bundle ID `com.marque.app`) for car owners to manage, track, and share vehicle information. It combines a private garage tool (service history, document expiry alerts, expense tracking) with a social layer (public profiles, posts, follows, comments).

## Build & Run

Build and run exclusively through **Xcode** — open `Marque-Prototype.xcodeproj`. There is no `Makefile`, CLI build script, or test suite. The Firebase iOS SDK is the sole SPM dependency (added via `https://github.com/firebase/firebase-ios-sdk`).

To build from the command line:
```bash
xcodebuild -project Marque-Prototype.xcodeproj -scheme Marque-Prototype -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture

### Navigation & Root State

`Marque_PrototypeApp.swift` bootstraps three global `ObservableObject` stores as SwiftUI environment objects: `CarStore`, `AuthService`, `SocialStore`. `RootView` drives top-level navigation based on `AuthService` state:

```
Onboarding (once) → LoginView → MainTabView (5 tabs: Garage, Explore, Notifications, Profile, Settings)
```

### Stores

| Store | Responsibility | Persistence |
|---|---|---|
| `CarStore` | Owns the user's cars array. Propagates changes to `NotificationManager`. | UserDefaults (`marque_saved_cars`, JSON) |
| `AuthService` | Firebase Auth (email/password + Apple Sign In). Manages onboarding flag. | UserDefaults for `LocalProfile` extras (username, bio, location) |
| `SocialStore` | Posts, comments, notifications, unread badge count. | In-memory only — seeded with mock data, no backend yet |

### Firebase Conditional Compilation

The entire Firebase integration is guarded with `#if canImport(FirebaseCore)` / `#if canImport(FirebaseAuth)`. Every Firebase-dependent file has a `#else` block with a working mock implementation, so the app builds and runs without the SDK installed. When editing `AuthService.swift` or `AppUser.swift`, both branches must stay consistent.

### Data Model Relationships

- `Car` embeds `[MaintenanceRecord]` and `[ServiceReminder]` directly (not normalized).
- `Car.photoFileNames: [String]` — filenames stored in `Documents/CarPhotos/`, managed by `ImageManager`. The first entry is the cover photo. Custom `Codable` handles migration from the legacy single-photo `photoFileName` key.
- `Post` references `AppUser` and `Car` by value (structs), not by ID.
- `AppUser` fields beyond Firebase Auth (username, bio, location) live in `LocalProfile` (UserDefaults). These need Firestore in production.

### Service Layer

- **`VINDecodeService`** — calls the NHTSA VPIC public API to auto-fill car fields from a 17-character VIN.
- **`NotificationManager`** — pure static functions that reschedule all local push notifications from the cars array. Called on launch and on every `carStore.cars` change. Schedules alerts at 30 days, 7 days, and on-day for registration/insurance expiry and service reminders.
- **`ServiceReminderEngine`** — pure static functions that suggest `ServiceReminder` objects based on maintenance history and hardcoded service intervals. No state.

### Shared UI Components (`Components/MarqueComponents.swift`)

Reusable components used across views: `MarquePrimaryButton`, `MarqueEmptyState`, `MarqueErrorBanner`, `MarqueSectionHeader`, `UserAvatar`, `FollowButton`, `ProBadge`, `StatChip`, `LabeledDivider`.

### Directory Layout

```
Marque-Prototype/
  Models/          — Car, AppUser, Post, Comment, AppNotification, ServiceReminder, MaintenanceRecord, CarData
  Stores/          — CarStore, AuthService, SocialStore, ImageManager, NotificationManager, VINDecodeService, ServiceReminderEngine
  Components/      — MarqueComponents.swift (shared UI)
  Views/           — Legacy flat views (CarListView, CarDetailView, AddCarView, EditCarDetailView, AddMaintenanceView, ExpenseSummaryView)
  Features/        — Feature-grouped views (Auth, Explore, Expenses, Garage, Onboarding, Profile, Settings, Social)
```

New feature views should go under `Features/<FeatureName>/`.

## Key Conventions

- All stores are `@MainActor` classes. Avoid dispatching off the main actor inside stores.
- `CarStore` does not know about `SocialStore` or `AuthService` — keep stores decoupled.
- `SocialStore` is currently backed by seed data only. Social mutations (likes, comments) are local and reset on launch — this is intentional for the prototype.
- `AppUser.preview` and `CarStore.previewCars` are the canonical mock data for SwiftUI `#Preview` blocks.
- `Car.displayName` (`"<year> <make> <model>"`) is the canonical display string — don't reconstruct it inline.
- `ExpensePeriod` is the source of truth for expense filter options; `Car.expenses(in:)` and `Car.expensesByCategory(in:)` use it.
