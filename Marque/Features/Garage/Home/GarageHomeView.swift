import SwiftUI

/// The Garage tab root: one car at a time, Tesla-app style. Always dark —
/// applied locally with `.environment(\.colorScheme, .dark)` on this subtree,
/// never `.preferredColorScheme` (which would flip the whole window).
///
/// Layout, top to bottom: car name + switcher chevron with chat / share
/// icons, a two-line status block, the hero car (pinned behind the list as it
/// scrolls, fading to a ghost), the "attention" card, the plain list of
/// focused screens, and a model wordmark footer. No standalone quick-action
/// row — every action it would have duplicated (log service, scan a
/// receipt, add a photo) already has exactly one home elsewhere (Service
/// History, the Photos tab), so this screen stays a status display, Tesla's
/// widget style, rather than a second place to trigger them.
struct GarageHomeView: View {
    @EnvironmentObject private var carStore: CarStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var exploreStore: ExploreStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var featureFlagsStore: FeatureFlagsStore
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.selectMainTab) private var selectMainTab

    @AppStorage("garage.selectedCarID") private var selectedCarIDString = ""

    @State private var path: [GarageRoute] = []

    @State private var showingSwitcher = false
    @State private var showingChat = false
    @State private var showingAddCar = false
    @State private var showingPaywall = false
    @State private var showingShareCard = false
    @State private var editDraft: Car?

    /// Hero height; the hero is pinned at its resting position as the list scrolls.
    private let heroHeight: CGFloat = 260

    /// The persisted selection, falling back to the first car if it's gone.
    private var selectedCar: Car? {
        carStore.cars.first(where: { $0.id.uuidString == selectedCarIDString }) ?? carStore.cars.first
    }

    private var atCarLimit: Bool {
        carStore.cars.count >= CarStore.freeCarLimit && !subscriptionStore.isPro
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let car = selectedCar {
                    home(for: car)
                } else {
                    emptyGarage
                }
            }
            .background(GarageTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GarageRoute.self) { route in
                destination(for: route)
            }
        }
        .toolbarBackground(GarageTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .environment(\.isGarageChrome, true)
        .environment(\.colorScheme, .dark)
        // Attached outside the dark override on purpose: these sheets are
        // general app flows and follow the system appearance.
        .modifier(GarageHomePresenters(
            car: selectedCar,
            showingChat: $showingChat,
            showingAddCar: $showingAddCar,
            showingPaywall: $showingPaywall,
            showingShareCard: $showingShareCard,
            editDraft: $editDraft
        ))
        .onAppear(perform: tryDeepLinkNavigation)
        .onChange(of: appDelegate.pendingCarID) { _, _ in tryDeepLinkNavigation() }
        .onChange(of: carStore.cars) { _, _ in tryDeepLinkNavigation() }
        .modifier(FollowPushRouter())
    }

    // MARK: - Deep link (notification tap)

    /// Selects the pending car once it's in the local store. Called on both
    /// `pendingCarID` and `cars` changes so a late Firestore snapshot still
    /// resolves when the app was cold-launched from a notification. A comment
    /// push also opens that car's page with its comments; a like push just
    /// selects the car.
    private func tryDeepLinkNavigation() {
        guard let carID = appDelegate.pendingCarID,
              carStore.cars.contains(where: { $0.id == carID }) else { return }
        var openComments = false
        if let push = appDelegate.pendingPush, push.kind != .follow {
            openComments = push.kind == .comment
            appDelegate.pendingPush = nil
        }
        selectedCarIDString = carID.uuidString
        // The owner's likes and comments live on the car's Public Sharing screen.
        let isPublic = carStore.cars.first(where: { $0.id == carID })?.isPublic ?? false
        path = openComments && isPublic ? [.carComments(carID)] : []
        appDelegate.pendingCarID = nil
    }

    // MARK: - Home

    private func home(for car: Car) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(for: car)
                statusBlock(for: car)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                PinnedHero(car: car, height: heroHeight)
                    .padding(.top, 8)
                    .zIndex(-1)

                attentionCard(for: car)

                GarageMileageCheckIn(car: car)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                rows(for: car)
                    .padding(.top, 16)

                footer(for: car)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .coordinateSpace(.named(PinnedHero.contentSpace))
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { statusBarFade }
    }

    /// Keeps rows that scroll up from colliding with the status bar text.
    private var statusBarFade: some View {
        // The overlay's top is the safe-area edge; the solid block reaches up
        // behind the status bar (anything past the screen edge is offscreen).
        VStack(spacing: 0) {
            GarageTheme.background.frame(height: 120)
            LinearGradient(
                colors: [GarageTheme.background, GarageTheme.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 16)
        }
        .offset(y: -120)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Header

    private func header(for car: Car) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { showingSwitcher = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(car.displayName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(GarageTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(GarageTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GaragePressStyle())
            .accessibilityLabel(car.displayName)
            .accessibilityHint("Double-tap to switch cars")
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                headerIcons
                headerIcon("square.and.arrow.up", label: "Share car") { showingShareCard = true }
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .sheet(isPresented: $showingSwitcher) {
            GarageCarSwitcherSheet(selectedCarID: selectedCar?.id) { id in
                selectedCarIDString = id.uuidString
                path = []
            }
        }
    }

    /// Settings lives on the Wallet tab; shared with the (car-less) empty
    /// Garage state, so this is only the Assistant. `header(for:)` adds
    /// Share alongside it when there's an actual car.
    @ViewBuilder
    private var headerIcons: some View {
        if featureFlagsStore.assistantEnabled {
            headerIcon("text.bubble", label: "Ask Marque about this car") { showingChat = true }
        }
    }

    private func headerIcon(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.regular))
                .foregroundColor(GarageTheme.primaryText)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(GaragePressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Status

    private func statusBlock(for car: Car) -> some View {
        let status = GarageSummary.statusLine(for: car)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(GarageTheme.secondaryText)
                Text(GarageSummary.mileageText(car) ?? "Mileage not set")
                    .font(.headline)
                    .foregroundColor(GarageTheme.primaryText)
            }
            HStack(spacing: 6) {
                if status.needsAttention {
                    Circle()
                        .fill(GarageTheme.accentDot)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(status.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(GarageTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Attention card

    @ViewBuilder
    private func attentionCard(for car: Car) -> some View {
        let items = GarageSummary.attentionItems(for: car)
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(GarageTheme.hairline)
                            .frame(height: 1)
                            .padding(.leading, 64)
                    }
                    Button { open(item.target, carID: car.id) } label: {
                        GarageAttentionRow(item: item)
                    }
                    .buttonStyle(GaragePressStyle())
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GarageTheme.card))
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    private func open(_ target: GarageSummary.AttentionTarget, carID: UUID) {
        switch target {
        case .documents: selectMainTab(.wallet)  // documents are edited in Wallet
        case .reminders: path.append(.reminders(carID))
        case .publicSharing: path.append(.publicSharing(carID))
        }
    }

    // MARK: Rows

    private func rows(for car: Car) -> some View {
        VStack(spacing: 4) {
            row(.serviceHistory(car.id), "wrench.and.screwdriver", "Service History",
                GarageSummary.serviceHistorySubtitle(car))
            row(.reminders(car.id), "bell", "Reminders",
                GarageSummary.remindersSubtitle(car),
                dot: GarageSummary.remindersNeedAttention(car))
            row(.mods(car.id), "slider.horizontal.3", "Mods",
                GarageSummary.modsSubtitle(car))
            row(.expenses(car.id), "creditcard", "Expenses",
                GarageSummary.expensesSubtitle(car))
            row(.value(car.id), "dollarsign.circle", "Estimated Value",
                GarageSummary.valueSubtitle(car))
            row(.engineSound(car.id), "waveform", "Engine Sound",
                GarageSummary.engineSoundSubtitle(car))
            row(.publicSharing(car.id), car.isPublic ? "globe" : "lock", "Public Sharing",
                GarageSummary.sharingSubtitle(car),
                dot: CarSharingSummary.needsReview(car))
            row(.details(car.id), "info.circle", "Details",
                GarageSummary.detailsSubtitle(car))
        }
    }

    private func row(_ route: GarageRoute, _ icon: String, _ title: String, _ subtitle: String, dot: Bool = false) -> some View {
        NavigationLink(value: route) {
            GarageListRow(systemImage: icon, title: title, subtitle: subtitle, showsDot: dot)
        }
        .buttonStyle(GaragePressStyle())
    }

    // MARK: Footer

    private func footer(for car: Car) -> some View {
        let wordmark = (car.model.isEmpty ? car.make : car.model).uppercased()
        let lineage = [car.year, car.make, car.trim].filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(GarageTheme.hairline)
                .frame(height: 1)
                .padding(.bottom, 28)

            if !wordmark.isEmpty {
                Text(wordmark)
                    .font(.title2.weight(.regular))
                    .fontWidth(.expanded)
                    .tracking(3)
                    .foregroundColor(GarageTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(car.model.isEmpty ? car.make : car.model)
            }
            if !lineage.isEmpty {
                Text(lineage)
                    .font(.headline.weight(.medium))
                    .foregroundColor(GarageTheme.secondaryText)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let mileage = GarageSummary.mileageText(car) {
                    Text(mileage)
                }
                if !car.vinNumber.isEmpty {
                    Text("VIN \(car.vinNumber)")
                        .textSelection(.enabled)
                }
                if !car.licensePlate.isEmpty {
                    Text("Plate \(car.licensePlate)")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(GarageTheme.tertiaryText)
            .padding(.top, 22)

            Button {
                editDraft = car
            } label: {
                Text("Edit Car")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(GarageTheme.secondaryText)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(GaragePressStyle())
            .padding(.top, 24)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Empty garage

    private var emptyGarage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text("Garage")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(GarageTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                headerIcons
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 0) {
                    GarageHeroView(car: Car(), height: 220)
                        .accessibilityHidden(true)
                        .padding(.top, 40)

                    Text("Add your first car")
                        .font(.title.weight(.bold))
                        .foregroundColor(GarageTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                    Text("Track service, documents and spending, and share your build.")
                        .font(.body)
                        .foregroundColor(GarageTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 40)

                    Button {
                        if atCarLimit { showingPaywall = true } else { showingAddCar = true }
                    } label: {
                        Text("Add a Car")
                            .font(.headline)
                            .foregroundColor(GarageTheme.background)
                            .padding(.horizontal, 36)
                            .frame(minHeight: 50)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(GaragePressStyle())
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: GarageRoute) -> some View {
        switch route {
        case .serviceHistory(let id): GarageServiceHistoryScreen(carID: id)
        case .reminders(let id): ServiceRemindersView(carID: id)
        case .mods(let id): GarageModsScreen(carID: id)
        case .expenses(let id): GarageExpensesScreen(carID: id)
        case .value(let id): GarageValueScreen(carID: id)
        case .engineSound(let id): GarageEngineSoundScreen(carID: id)
        case .publicSharing(let id): GaragePublicSharingScreen(carID: id)
        case .details(let id): GarageDetailsScreen(carID: id)
        case .carComments(let id): GaragePublicSharingScreen(carID: id, openCommentsOnAppear: true)
        }
    }

}

// MARK: - Pinned hero

/// The hero, pinned at its resting position while the list scrolls over it
/// and fading to a ~15% ghost (ref: Tesla). Without Reduce Motion it also
/// drifts up a little and shrinks slightly; with it, it only fades.
///
/// Driven by `visualEffect`, which reads the scroll geometry each frame
/// without any state, so scrolling never re-renders the rest of the screen.
/// Distance scrolled = the hero's y in the scroll content minus its y in the
/// scroll view's visible bounds.
private struct PinnedHero: View {
    static let contentSpace = "garageHomeContent"

    let car: Car
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = height
        let reduceMotion = reduceMotion
        GarageHeroView(car: car, height: height)
            .visualEffect { content, proxy in
                let scrolled = proxy.frame(in: .named(Self.contentSpace)).minY
                    - proxy.frame(in: .scrollView(axis: .vertical)).minY
                let progress = min(max(scrolled / (height * 0.9), 0), 1)
                let pinned = max(scrolled, 0)
                let drift = reduceMotion ? 0 : min(pinned, height * 1.2) * 0.12
                return content
                    .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * progress)
                    .opacity(1 - 0.85 * progress)
                    .offset(y: pinned - drift)
            }
    }
}

// MARK: - Presenters

/// The Garage home's sheets, grouped for the type checker.
private struct GarageHomePresenters: ViewModifier {
    let car: Car?
    @Binding var showingChat: Bool
    @Binding var showingAddCar: Bool
    @Binding var showingPaywall: Bool
    @Binding var showingShareCard: Bool
    @Binding var editDraft: Car?

    @EnvironmentObject private var carStore: CarStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var exploreStore: ExploreStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingChat) {
                MarqueChatView(scopedCarId: car?.id.uuidString)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
            .sheet(isPresented: $showingPaywall) {
                ProUpgradeView(trigger: .carLimit)
            }
            .sheet(isPresented: $showingShareCard) {
                if let car, let projection = OwnCarPublicProjection.shareCard(
                    for: car, exploreStore: exploreStore, authService: authService
                ) {
                    ShareCardSheet(car: projection, localCoverPhotoFileName: car.primaryPhotoFileName, isOwnCar: true)
                }
            }
            // `item:`, not `isPresented:` + a separate draft: with two
            // states the sheet's content could read the draft before it was
            // set and present an empty (blank white) sheet.
            .sheet(item: $editDraft) { draft in
                EditCarDetailView(
                    car: Binding(get: { editDraft ?? draft }, set: { editDraft = $0 }),
                    onSave: { carStore.updateCar($0) }
                )
            }
    }
}

#Preview {
    let carStore = CarStore()
    carStore.cars = CarStore.previewCars
    return GarageHomeView()
        .environmentObject(carStore)
        .environmentObject(AuthService())
        .environmentObject(ExploreStore())
        .environmentObject(SubscriptionStore())
        .environmentObject(FeatureFlagsStore())
        .environmentObject(AppDelegate())
        .environmentObject(NotificationStore())
        .environmentObject(ChatStore())
}
