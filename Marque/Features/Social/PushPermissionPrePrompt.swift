import SwiftUI
import UserNotifications

/// One-time soft ask before the system notification prompt, offered at a
/// high-intent moment: right after the user's first like, first comment, or
/// first time making a car public. "Allow" hands off to
/// `NotificationManager.requestPermission()` (the system prompt); "Not Now"
/// leaves the system prompt unused so a later expiry toggle can still ask.
///
/// Shown at most once per device (the OS permission is per device too), and
/// only while the system permission is still undetermined, since there's
/// nothing to ask for once the user has answered the system prompt.
enum PushPrePrompt {
    static let shownKey = "marque_push_preprompt_shown"

    /// Calls `present` (after a short beat, so it doesn't collide with the
    /// action's own feedback) if the pre-prompt hasn't been shown yet and the
    /// system permission is undetermined. Marks it shown when it presents.
    @MainActor
    static func offer(present: @escaping @MainActor () -> Void) {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
            UserDefaults.standard.set(true, forKey: shownKey)
            present()
        }
    }
}

struct PushPrePromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
            .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Stay in the Loop")
                    .font(.title2.weight(.bold))
                Text("Get notified when people like or comment on your cars, or start following you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                MarquePrimaryButton("Allow Notifications") {
                    NotificationManager.requestPermission()
                    dismiss()
                }
                Button("Not Now") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Presents `PushPrePromptSheet`. Pair with `PushPrePrompt.offer`.
    func pushPrePrompt(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { PushPrePromptSheet() }
    }
}
