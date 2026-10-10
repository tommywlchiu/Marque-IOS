//
//  ScanAllowanceStore.swift
//  Marque
//
//  FR-14.4: read-only view of today's document-scan usage, so the remaining
//  allowance is visible *before* a scan is attempted. The server is the only
//  enforcement point (FR-08.8) — the parse* Cloud Functions reserve a slot in
//  users/{uid}/usage/scans_{yyyy-MM-dd} — and this store just listens to that
//  counter. The caps below are display copies of FREE_SCAN_DAILY_CAP /
//  PRO_SCAN_DAILY_CAP in functions/src/index.ts; change them together.
//
//  Which cap applies follows the SERVER's plan (users/{uid}.isPro, the value
//  getIsPro reads in the parse* functions), not StoreKit. A Family Sharing member
//  has local StoreKit Pro but the server deliberately withholds the flag from
//  them, so it enforces the free cap — this store must show the same number.
//

import Foundation
import UIKit
import FirebaseFirestore

@MainActor
final class ScanAllowanceStore: ObservableObject {

    @Published private(set) var todayCount: Int = 0

    /// Server-side plan (`users/{uid}.isPro`). `nil` means "not yet known" — before
    /// the first snapshot, after a listener error, and after `stopListening()`.
    /// Never read StoreKit here; see the file header.
    @Published private(set) var serverIsPro: Bool?

    static let freeDailyCap = 5
    static let proDailyCap = 50

    private let db = Firestore.firestore()
    // Two independent listeners. The usage listener is date-scoped (re-attached on
    // day rollover); the plan listener is not, and is only re-attached if it died.
    private var listener: ListenerRegistration?
    private var planListener: ListenerRegistration?
    private var currentUID: String?
    private var listeningDate: String?
    private var planListenerFailed = false
    private var planGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        // The counter document is keyed by local date, so a session that crosses
        // midnight must re-attach — otherwise a stale count would block a scan
        // the server would happily allow.
        let names: [Notification.Name] = [.NSCalendarDayChanged, UIApplication.didBecomeActiveNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIfNeeded() }
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        listener?.remove()
        planListener?.remove()
    }

    // MARK: - Lifecycle

    func startListening(uid: String) {
        // A different account must never inherit the previous account's plan.
        if currentUID != uid { serverIsPro = nil }
        currentUID = uid
        attachUsageListener(uid: uid)
        attachPlanListener(uid: uid)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        planListener?.remove()
        planListener = nil
        planGeneration += 1
        planListenerFailed = false
        currentUID = nil
        listeningDate = nil
        todayCount = 0
        serverIsPro = nil
    }

    /// Runs on day rollover and on foreground. Each listener is checked on its own
    /// condition so re-attaching one never disturbs the other: the usage listener
    /// re-attaches when its date is stale (or an error cleared it), the plan
    /// listener only when an error killed it.
    private func refreshIfNeeded() {
        guard let uid = currentUID else { return }
        if listeningDate != Self.localDateString() { attachUsageListener(uid: uid) }
        if planListenerFailed { attachPlanListener(uid: uid) }
    }

    private func attachUsageListener(uid: String) {
        listener?.remove()
        let date = Self.localDateString()
        listeningDate = date
        todayCount = 0
        let ref = db.collection("users").document(uid)
            .collection("usage").document("scans_\(date)")
        listener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, self.currentUID == uid, self.listeningDate == date else { return }
            if let error {
                // Firestore ends a listener after an error, so this count would go
                // stale. Keep the fail-open 0 (display only — the server enforces
                // the cap) and clear listeningDate so the next foreground
                // re-attaches instead of leaving the listener dead all day.
                print("[ScanAllowanceStore] Listener error: \(error.localizedDescription)")
                self.listeningDate = nil
                return
            }
            self.todayCount = max((snap?.data()?["count"] as? Int) ?? 0, 0)
        }
    }

    /// Follows `users/{uid}.isPro` (server-written only, so the client cannot forge
    /// it — see firestore.rules). Because this is a live listener, the caption
    /// updates by itself when the server flag flips after a purchase.
    private func attachPlanListener(uid: String) {
        planListener?.remove()
        planGeneration += 1
        let generation = planGeneration
        planListenerFailed = false
        planListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self, self.currentUID == uid, self.planGeneration == generation else { return }
                if let error {
                    // Firestore ends a listener after an error. Fall back to
                    // "unknown" (caption hidden, client gate open — the server
                    // still enforces) rather than keep a plan that can no longer
                    // update, and let the next foreground re-attach.
                    print("[ScanAllowanceStore] Plan listener error: \(error.localizedDescription)")
                    self.serverIsPro = nil
                    self.planListenerFailed = true
                    return
                }
                guard let snap else { return }
                // A missing profile doc means free to the server (getIsPro), but a
                // *cache-only* miss just means we haven't heard from the server
                // yet — asserting "free" then would mislabel a Pro user offline.
                if !snap.exists && snap.metadata.isFromCache { return }
                self.serverIsPro = snap.data()?["isPro"] as? Bool == true
            }
    }

    // MARK: - Allowance

    /// Today's cap for the server-side plan, or `nil` while the plan is unknown.
    var limit: Int? {
        guard let serverIsPro else { return nil }
        return serverIsPro ? Self.proDailyCap : Self.freeDailyCap
    }

    /// Scans left today, or `nil` while the plan is unknown (so a caption can hide
    /// itself instead of presenting a guessed number as fact).
    var remaining: Int? {
        guard let limit else { return nil }
        return max(limit - todayCount, 0)
    }

    /// Call at the top of every scan entry point. Returns false when the day's
    /// allowance is spent, and records the `document_scan_cap_reached` demand
    /// signal — the caller should then present the paywall instead of the camera.
    /// Fails open (returns true, no event) while the plan is unknown: the server is
    /// the enforcer, and a snapshot that's a moment late must not block a Pro user.
    /// Known smell: emits telemetry from a predicate-shaped method.
    func canStartScan() -> Bool {
        guard remaining == 0 else { return true }
        AnalyticsService.documentScanCapReached()
        return false
    }

    // MARK: - Date

    /// The `clientDate` the parse* functions key the counter by. `nonisolated`
    /// so DocumentScanService (not main-actor) can share the exact same format.
    nonisolated static func localDateString(_ date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df.string(from: date)
    }
}
