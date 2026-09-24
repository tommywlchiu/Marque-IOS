# Marque

Marque is an iOS app for car owners to manage, track, and share vehicle information. It combines a private garage tool with a social layer and an AI assistant:

- **Garage** — service history, maintenance logs, document expiry alerts (registration, insurance, license), and expense tracking per vehicle.
- **Social** — public car profiles, follow other owners, an Explore feed of public cars, block/report.
- **Marque Assistant** — an AI assistant (Claude) that answers questions about your own cars using their make/model/service history as context, plus AI-powered document scanning (VIN decode, insurance cards, driver's licenses, maintenance receipts) and service-reminder suggestions.
- **Marque Pro** — a subscription tier (StoreKit 2) that raises daily Assistant/scan limits and removes the free-tier car limit.

Currently in TestFlight beta.

## Tech Stack

- **Client**: SwiftUI, iOS 17.6+, Swift 5
- **Backend**: Firebase — Auth, Firestore, Storage, Cloud Functions, Remote Config, Crashlytics, App Check
- **Cloud Functions**: TypeScript (`firebase-functions` v6)
- **AI**: Anthropic Claude (Sonnet), called server-side from Cloud Functions
- **Payments**: StoreKit 2
- **Analytics**: PostHog
- **Dependencies**: `firebase-ios-sdk`, `GoogleSignIn-iOS`, `posthog-ios` (Swift Package Manager)

## Project Structure

```
Marque/            — App source (SwiftUI views, stores, models)
  Models/          — Data models (Car, AppUser, ServiceReminder, ...)
  Stores/          — @MainActor ObservableObject stores (CarStore, AuthService, ...)
  Components/      — Shared SwiftUI components
  Views/           — Legacy flat views (being migrated into Features/)
  Features/        — Feature-organized views (Auth, Garage, Explore, Social, Settings, ...)
functions/         — TypeScript Cloud Functions (Assistant, document scanning, entitlements, account deletion)
firestore.rules    — Firestore security rules
docs/              — Product documentation
```

## Building

Open `Marque.xcodeproj` in Xcode and run. One native target, iOS 17.6+ deployment target.

Requires a `GoogleService-Info.plist` (Firebase config) in the `Marque/` directory to build against Firebase.

Command-line build:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+' | tail -1)
xcodebuild -project Marque.xcodeproj -scheme Marque \
  -destination "platform=iOS Simulator,name=$SIM"
```

Cloud Functions live in `functions/`:

```bash
cd functions && npm install && npm run build
```

## License

All rights reserved.
