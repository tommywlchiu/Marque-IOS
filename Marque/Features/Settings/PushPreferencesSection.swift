import SwiftUI
import UserNotifications
#if DEBUG
import FirebaseMessaging
#endif

/// "Push Notifications" section of Settings > Notifications: per-type
/// switches the server's `sendPush` honors (`PushStore.setPreference`), plus
/// the device's system permission, since these switches do nothing while
/// iOS notifications are off for Marque.
struct PushPreferencesSection: View {
    @EnvironmentObject private var pushStore: PushStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var saveError: String?
    @State private var debugTokenStatus: String?

    var body: some View {
        Section(
            header: Text("Push Notifications"),
            footer: Text("Choose what Marque sends to this device when you're not in the app.")
        ) {
            permissionRow

            if pushStore.preferencesLoaded {
                ForEach(NotificationPreferences.Kind.allCases) { kind in
                    Toggle(kind.displayName, isOn: binding(for: kind))
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading preferences…")
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            #if DEBUG
            // For sending a test push from the Firebase console
            // (Messaging → "Send test message"). Debug builds only.
            Button {
                Messaging.messaging().token { token, error in
                    let value = token ?? "No token: \(error?.localizedDescription ?? "unknown error")"
                    UIPasteboard.general.string = value
                    debugTokenStatus = token == nil ? value : "Copied (\(token!.prefix(12))…)"
                }
            } label: {
                Label("Copy Push Token (debug)", systemImage: "doc.on.doc")
            }
            if let debugTokenStatus {
                Text(debugTokenStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            #endif
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system prompt or the Settings app.
            if phase == .active { Task { await refreshStatus() } }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch authorizationStatus {
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Notifications are off for Marque", systemImage: "bell.slash")
                    .foregroundColor(.orange)
                Text("Turn them on in the Settings app to get these alerts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 2)
        case .notDetermined:
            Button {
                NotificationManager.requestPermission()
            } label: {
                Label("Turn On Notifications", systemImage: "bell.badge")
            }
        default:
            EmptyView()
        }
    }

    private func binding(for kind: NotificationPreferences.Kind) -> Binding<Bool> {
        Binding(
            get: { pushStore.preferences[kind] },
            set: { enabled in
                Task {
                    do {
                        try await pushStore.setPreference(kind, enabled: enabled)
                    } catch {
                        saveError = "Couldn't update \(kind.displayName.lowercased()). Check your connection and try again."
                    }
                }
            }
        )
    }

    private func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
