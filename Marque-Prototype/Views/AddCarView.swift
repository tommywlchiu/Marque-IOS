import SwiftUI
import AVFoundation

private enum AddMode: String, CaseIterable {
    case vin = "Search by VIN"
    case manual = "Manual"
}

struct AddCarView: View {
    @EnvironmentObject var carStore: CarStore
    @Environment(\.dismiss) var dismiss

    /// FR-13.3 — when set, this view is being shown as the onboarding
    /// add-first-car step rather than the "+" tab sheet. There is no sheet to
    /// dismiss in that context, so completion is reported via these closures
    /// instead of `dismiss()`, and the toolbar's "Cancel" becomes "Skip"
    /// (FR-13.4 — a visually secondary skip affordance, not a destructive cancel).
    var onboarding: OnboardingContext? = nil

    struct OnboardingContext {
        let onSkip: () -> Void
        let onAdded: () -> Void
    }

    @State private var addMode: AddMode = .vin

    // FR-13's add-first-car step: shown in place of the Form the instant a
    // car is added while `onboarding != nil`. The normal "+" tab flow never
    // sets this — see the toolbar's "Add" button action.
    @State private var showCelebration = false

    // VIN search state
    @State private var vinInput = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var vinSearched = false

    // Car fields (shared between modes, pre-filled by VIN search)
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var trim = ""
    @State private var bodyStyle = ""
    @State private var driveType = ""
    @State private var engine = ""
    @State private var fuelType = ""
    @State private var transmission = ""

    var isFormValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        !year.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canAdd: Bool {
        isFormValid && (addMode == .manual || vinSearched)
    }

    var body: some View {
        // The NavigationStack stays mounted across the showCelebration swap —
        // only the Group's content inside it changes — matching
        // ProUpgradeView's showCelebration pattern. Swapping the
        // NavigationStack itself in/out (the previous structure here) tore
        // down its UINavigationController along with the Form whose toolbar
        // button had just been tapped, and GarageReadyCelebrationView came in
        // as bare content with no container: it never actually appeared on
        // screen even though onAppear (and its chime) still fired. Only the
        // onboarding add-first-car path ever sets showCelebration true — the
        // "+" tab flow (onboarding == nil) never reaches it, so it keeps its
        // existing immediate-dismiss behavior.
        NavigationStack {
            Group {
                if showCelebration {
                    GarageReadyCelebrationView {
                        onboarding?.onAdded()
                    }
                } else {
                    Form {
                        Section {
                            Picker("Add Method", selection: $addMode.animation()) {
                                ForEach(AddMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                        .onChange(of: addMode) { _, _ in resetFields() }

                        if addMode == .vin {
                            vinInputSection
                        }

                        if addMode == .manual {
                            manualSection
                        } else if vinSearched {
                            searchResultSection
                        }
                    }
                    .navigationTitle(onboarding != nil ? "Add Your First Car" : "Add a Car")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            if let onboarding {
                                Button("Skip") { onboarding.onSkip() }
                            } else {
                                Button("Cancel") { dismiss() }
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                let car = Car(
                                    make: make.trimmingCharacters(in: .whitespaces),
                                    model: model.trimmingCharacters(in: .whitespaces),
                                    year: year.trimmingCharacters(in: .whitespaces),
                                    vinNumber: addMode == .vin ? vinInput.uppercased().trimmingCharacters(in: .whitespaces) : "",
                                    trim: trim,
                                    bodyStyle: bodyStyle,
                                    driveType: driveType,
                                    engine: engine,
                                    fuelType: fuelType,
                                    transmission: transmission
                                )
                                // FR-11.4 `car_added.entry_method`. `addMode` is the only
                                // place this is known; without it CarStore skips the event.
                                carStore.addCar(car, entryMethod: addMode == .vin ? .vin : .manual)
                                if onboarding != nil {
                                    // FR-13's first-car milestone: show the celebration and
                                    // defer onAdded() until the user dismisses it (see
                                    // GarageReadyCelebrationView's continue button). The
                                    // non-onboarding path below is unchanged.
                                    showCelebration = true
                                } else {
                                    dismiss()
                                }
                            }
                            .disabled(!canAdd)
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .onAppear {
            if onboarding != nil {
                AnalyticsService.onboardingStepViewed(step: .addFirstCar)
            }
        }
    }

    private var vinInputSection: some View {
        Section(header: Text("Search by VIN")) {
            HStack(spacing: 12) {
                TextField("17-character VIN", text: $vinInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: vinInput) { _, _ in
                        searchError = nil
                        if vinSearched { resetSearchedFields() }
                    }

                if isSearching {
                    ProgressView()
                } else {
                    Button("Search") {
                        Task { await searchVIN() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vinInput.trimmingCharacters(in: .whitespaces).count != 17)
                }
            }

            if let error = searchError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var searchResultSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Vehicle found — review and edit if needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("Make", text: $make)
                .autocorrectionDisabled()

            TextField("Model", text: $model)
                .autocorrectionDisabled()

            TextField("Year", text: $year)
                .keyboardType(.numberPad)

            TextField("Trim (e.g. EX-L, Sport, XLE)", text: $trim)
                .autocorrectionDisabled()

            Picker("Body Style", selection: $bodyStyle) {
                Text("Select").tag("")
                Text("Sedan").tag("Sedan")
                Text("Coupe").tag("Coupe")
                Text("Hatchback").tag("Hatchback")
                Text("SUV").tag("SUV")
                Text("Crossover").tag("Crossover")
                Text("Pickup").tag("Pickup")
                Text("Van").tag("Van")
                Text("Minivan").tag("Minivan")
                Text("Wagon").tag("Wagon")
                Text("Convertible").tag("Convertible")
            }

            Picker("Drive Type", selection: $driveType) {
                Text("Select").tag("")
                Text("FWD").tag("FWD")
                Text("RWD").tag("RWD")
                Text("AWD").tag("AWD")
                Text("4WD").tag("4WD")
            }

            TextField("Engine (e.g. 2.5L 4-Cylinder)", text: $engine)
                .autocorrectionDisabled()

            Picker("Fuel Type", selection: $fuelType) {
                Text("Select").tag("")
                Text("Gasoline").tag("Gasoline")
                Text("Diesel").tag("Diesel")
                Text("Electric").tag("Electric")
                Text("Hybrid").tag("Hybrid")
                Text("Plug-in Hybrid").tag("Plug-in Hybrid")
                Text("Flex Fuel").tag("Flex Fuel")
            }

            Picker("Transmission", selection: $transmission) {
                Text("Select").tag("")
                Text("Automatic").tag("Automatic")
                Text("Manual").tag("Manual")
                Text("CVT").tag("CVT")
                Text("Dual-Clutch").tag("Dual-Clutch")
            }
        } header: {
            Text("Search Results")
        } footer: {
            Text("You can add color, mileage, insurance, and other details after adding the car.")
        }
    }

    private var manualSection: some View {
        Group {
            Section(header: Text("Car Information")) {
                Picker("Make", selection: $make) {
                    Text("Select a make").tag("")
                    ForEach(CarData.makes, id: \.self) { brand in
                        Text(brand).tag(brand)
                    }
                }

                TextField("Model (e.g. Camry, 3 Series)", text: $model)
                    .autocorrectionDisabled()

                TextField("Year (e.g. 2024)", text: $year)
                    .keyboardType(.numberPad)
            }

            Section {
                Text("You can add license plate, VIN, and other details after adding the car.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func searchVIN() async {
        isSearching = true
        searchError = nil
        do {
            let result = try await VINDecodeService.decode(vin: vinInput)
            make = result.make
            model = result.model
            year = result.year
            trim = result.trim
            bodyStyle = result.bodyStyle
            driveType = result.driveType
            engine = result.engine
            fuelType = result.fuelType
            transmission = result.transmission
            vinSearched = true
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    private func resetSearchedFields() {
        vinSearched = false
        make = ""
        model = ""
        year = ""
        trim = ""
        bodyStyle = ""
        driveType = ""
        engine = ""
        fuelType = ""
        transmission = ""
    }

    private func resetFields() {
        vinInput = ""
        searchError = nil
        resetSearchedFields()
    }
}

// MARK: - Onboarding first-car celebration

// FR-13.3's "you're all set" moment, shown once in place of the Form when a
// car is added during onboarding specifically (never for the "+" tab flow,
// and never on Skip — see AddCarView.body). Same confetti/chime language as
// ProUpgradeView's ProCelebrationView (Components/CelebrationEffects.swift),
// but a simpler icon entrance since there's no Pro badge here.
private struct GarageReadyCelebrationView: View {
    let onContinue: () -> Void

    @State private var iconVisible = false
    // Held so ARC keeps it alive through playback (assigned in onAppear,
    // never read otherwise) — same reasoning as ProCelebrationView.
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            // Behind the text/button rather than above it — a one-shot burst
            // that settles in ~2s, not a loop.
            ConfettiView()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "car.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.accentColor)
                }
                .scaleEffect(iconVisible ? 1 : 0.7)
                .opacity(iconVisible ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Your Garage is Ready!")
                        .font(.title2).fontWeight(.bold)
                    Text("Your first car is in. Track service history, document expirations, and expenses right from your Garage.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Spacer()

                MarquePrimaryButton("Let's Go!") {
                    onContinue()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                iconVisible = true
            }
            audioPlayer = CelebrationChime.play()
        }
    }
}
