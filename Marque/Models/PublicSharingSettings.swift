import Foundation

/// Per-car toggles for what a PUBLIC car exposes in Explore. Year/make/model,
/// owner identity (@username + avatar) and likes/comments are always shared
/// and have no toggle here. Estimated value is NOT in this struct — it's the
/// pre-existing `Car.showValuePublicly`, left alone to avoid a duplicate flag.
///
/// `PublicCar(from:)` is the ONLY place that must honor these settings — every
/// write to `publicCars` goes through it (see CarStore's "Public copy"
/// section). A switched-off group must produce an empty projection (""/[]/nil
/// as appropriate), never a non-empty value, so a group that's off can never
/// leak into Explore through any write path.
struct PublicSharingSettings: Codable, Equatable {
    var photos: Bool
    var specs: Bool
    var mileage: Bool
    var notes: Bool
    var serviceHistory: Bool
    var mods: Bool
    var engineSound: Bool

    /// The owner has confirmed these settings at least once, via the "Make
    /// Public" / "Save" sharing sheet. Drives the one-time review prompt for
    /// cars that predate this feature (see `legacyAllOn`).
    var hasReviewed: Bool

    /// Defaults for a car made public for the FIRST time under this feature
    /// (owner decision, privacy-first): photos/specs/mods on; mileage, notes,
    /// serviceHistory, engineSound off. `Car.showValuePublicly` is untouched
    /// by this struct and defaults off on its own.
    static let privacyFirst = PublicSharingSettings(
        photos: true,
        specs: true,
        mileage: false,
        notes: false,
        serviceHistory: false,
        mods: true,
        engineSound: false,
        hasReviewed: false
    )

    /// What an already-public car effectively shared before this feature
    /// existed — everything. Used so existing public cars show no change in
    /// Explore until the owner reviews and saves new settings (at which point
    /// `hasReviewed` flips true and the groups reflect their explicit choice).
    static let legacyAllOn = PublicSharingSettings(
        photos: true,
        specs: true,
        mileage: true,
        notes: true,
        serviceHistory: true,
        mods: true,
        engineSound: true,
        hasReviewed: false
    )
}

#if DEBUG
extension PublicSharingSettings {
    /// No XCTest target exists in this project (see CLAUDE.md); this is the
    /// documented substitute. Call manually from a debug entry point.
    static func _selfCheck() {
        assert(privacyFirst.photos && privacyFirst.specs && privacyFirst.mods)
        assert(!privacyFirst.mileage && !privacyFirst.notes && !privacyFirst.serviceHistory && !privacyFirst.engineSound)
        assert(!privacyFirst.hasReviewed)

        assert(legacyAllOn.photos && legacyAllOn.specs && legacyAllOn.mileage
            && legacyAllOn.notes && legacyAllOn.serviceHistory && legacyAllOn.mods && legacyAllOn.engineSound)
        assert(!legacyAllOn.hasReviewed)
    }
}
#endif
