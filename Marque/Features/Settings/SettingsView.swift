import SwiftUI
import FirebaseAuth
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showingProUpgrade = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountSheet = false
    @State private var showingChangePassword = false

    private var user: AppUser { authService.currentUser ?? .preview }

    /// Foreground scene lookup shared by the StoreKit review/manage-subscription flows.
    private var foregroundScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }

    // CFBundleShortVersionString (CFBundleVersion) — shared by the Support
    // section's Version row and sendFeedback()'s debugging context below.
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    /// Opens Mail pre-addressed to support, with app/OS version and a truncated
    /// uid pre-filled so a reply-less bug report still carries useful debugging
    /// context. uid is truncated (not omitted) so it's still useful for looking
    /// up the account without reading like a full identifier in an email body.
    private func sendFeedback() {
        let uidSuffix = String(user.id.suffix(6))
        let body = """


        ---
        App version: \(appVersionString)
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
            dataSection
            supportSection
            legalSection
            dangerSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView(trigger: .settings)
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

    /// Profile editing lives at the top of Wallet; Settings only keeps
    /// what Wallet doesn't (the password, for email accounts).
    @ViewBuilder
    private var accountSection: some View {
        // Password-based accounts only — Apple/Google sign-in has no Marque password to change.
        if authService.signInProvider == "password" {
            Section(header: Text("Account")) {
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
            NavigationLink(destination: NotificationsSettingsView()) {
                Label("Notification Settings", systemImage: "bell.badge")
            }
        }
    }

    // FR-15: free service & expense export (PDF/CSV), plus a marked spot for
    // the GDPR account-data (JSON) export row a backend agent is building in
    // parallel (AccountExportService) — not wired here.
    private var dataSection: some View {
        Section(header: Text("Data")) {
            NavigationLink(destination: DataExportView()) {
                Label("Export Service & Expenses", systemImage: "square.and.arrow.up")
            }
            NavigationLink(destination: AccountDataExportView()) {
                Label("Download My Account Data", systemImage: "arrow.down.doc")
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
                Text(appVersionString)
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
            NavigationLink(destination: AcknowledgementsView()) {
                Label("Acknowledgements", systemImage: "heart.text.square")
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
    @EnvironmentObject var carStore: CarStore
    @EnvironmentObject var authService: AuthService
    @AppStorage(NotificationManager.insuranceAlertsKey) private var insuranceAlerts = true
    @AppStorage(NotificationManager.registrationAlertsKey) private var registrationAlerts = true
    // NotificationManager treats an absent key as "on" (see its gates in
    // scheduleAll), so the UI default here must match that, not read as off
    // until the user has ever touched the toggle.
    @AppStorage(NotificationManager.maintenanceRemindersKey) private var maintenanceReminders = true

    var body: some View {
        Form {
            PushPreferencesSection()

            Section(header: Text("Vehicle Alerts")) {
                Toggle("Insurance Expiry", isOn: $insuranceAlerts)
                    .onChange(of: insuranceAlerts) { _, _ in
                        NotificationManager.scheduleAll(
                            for: carStore.cars,
                            licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                        )
                    }
                Toggle("Registration Expiry", isOn: $registrationAlerts)
                    .onChange(of: registrationAlerts) { _, _ in
                        NotificationManager.scheduleAll(
                            for: carStore.cars,
                            licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                        )
                    }
                Toggle("Maintenance Reminders", isOn: $maintenanceReminders)
                    .onChange(of: maintenanceReminders) { _, _ in
                        NotificationManager.scheduleAll(
                            for: carStore.cars,
                            licenseExpiry: authService.currentUser?.driverLicenseExpiryDate
                        )
                    }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
