import SwiftUI
import FirebaseAuth
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showingProUpgrade = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingSignOutAlert = false
    @State private var notificationsEnabled = true
    @State private var useMiles = true
    @State private var showingDeleteAccountSheet = false
    @State private var showingChangePassword = false

    private var user: AppUser { authService.currentUser ?? .preview }

    /// Foreground scene lookup shared by the StoreKit review/manage-subscription flows.
    private var foregroundScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }

    /// Opens Mail pre-addressed to support, with app/OS version and a truncated
    /// uid pre-filled so a reply-less bug report still carries useful debugging
    /// context. uid is truncated (not omitted) so it's still useful for looking
    /// up the account without reading like a full identifier in an email body.
    private func sendFeedback() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let uidSuffix = String(user.id.suffix(6))
        let body = """


        ---
        App version: \(appVersion) (\(buildNumber))
        iOS version: \(UIDevice.current.systemVersion)
        Account: …\(uidSuffix)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "marqueofficialhq@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Marque Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        List {
            accountSection
            subscriptionSection
            preferencesSection
            supportSection
            legalSection
            dangerSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView()
        }
        .sheet(isPresented: $showingDeleteAccountSheet) {
            DeleteAccountView()
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Sign Out", role: .destructive) { authService.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Delete Account", role: .destructive) {
                showingDeleteAccountSheet = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all your data. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section(header: Text("Account")) {
            HStack(spacing: 12) {
                UserAvatar(user: user, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName).font(.headline)
                    Text("@\(user.username)").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            NavigationLink(destination: EditProfileView()) {
                Label("Edit Profile", systemImage: "person.crop.circle")
            }

            // Password-based accounts only — Apple/Google sign-in has no Marque password to change.
            if authService.signInProvider == "password" {
                Button {
                    showingChangePassword = true
                } label: {
                    Label("Change Password", systemImage: "key.fill")
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var subscriptionSection: some View {
        Section(header: Text("Subscription")) {
            if user.isProMember {
                HStack {
                    Label("Marque Pro", systemImage: "star.fill")
                        .foregroundColor(.accentColor)
                    Spacer()
                    ProBadge()
                }
                Button {
                    guard let scene = foregroundScene else { return }
                    Task { try? await AppStore.showManageSubscriptions(in: scene) }
                } label: {
                    Label("Manage Subscription", systemImage: "creditcard")
                        .foregroundColor(.primary)
                }
            } else {
                Button {
                    showingProUpgrade = true
                } label: {
                    HStack {
                        Label("Upgrade to Pro", systemImage: "star.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.accentColor)
            }
        }
    }

    private var preferencesSection: some View {
        Section(header: Text("Preferences")) {
            Toggle(isOn: $notificationsEnabled) {
                Label("Expiry Notifications", systemImage: "bell.fill")
            }

            Picker(selection: $useMiles) {
                Text("Miles").tag(true)
                Text("Kilometers").tag(false)
            } label: {
                Label("Distance Unit", systemImage: "gauge.medium")
            }

            NavigationLink(destination: NotificationsSettingsView()) {
                Label("Notification Settings", systemImage: "bell.badge")
            }
        }
    }

    private var supportSection: some View {
        Section(header: Text("Support")) {
            Link(destination: AppLinks.support) {
                Label("Help & FAQ", systemImage: "questionmark.circle")
                    .foregroundColor(.primary)
            }

            Button {
                sendFeedback()
            } label: {
                Label("Send Feedback", systemImage: "envelope")
                    .foregroundColor(.primary)
            }

            Button {
                if let scene = foregroundScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            } label: {
                Label("Rate Marque", systemImage: "star")
                    .foregroundColor(.primary)
            }

            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("1.0.0 (1)")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private var legalSection: some View {
        Section(header: Text("Legal")) {
            Link(destination: AppLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundColor(.primary)
            }
            Link(destination: AppLinks.termsOfService) {
                Label("Terms of Service", systemImage: "doc.text")
                    .foregroundColor(.primary)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button {
                showingSignOutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.red)
            }

            Button {
                showingDeleteAccountAlert = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Notifications Settings (stub)

private struct NotificationsSettingsView: View {
    @State private var insuranceAlerts = true
    @State private var registrationAlerts = true
    @State private var maintenanceReminders = false
    @State private var socialActivity = true

    var body: some View {
        Form {
            Section(header: Text("Vehicle Alerts")) {
                Toggle("Insurance Expiry", isOn: $insuranceAlerts)
                Toggle("Registration Expiry", isOn: $registrationAlerts)
                Toggle("Maintenance Reminders", isOn: $maintenanceReminders)
            }
            Section(header: Text("Social")) {
                Toggle("Likes & Comments", isOn: $socialActivity)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
