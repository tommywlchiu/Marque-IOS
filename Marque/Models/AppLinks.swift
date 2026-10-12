import Foundation

enum AppLinks {
    /// Public landing page; used in share text until the App Store listing is live.
    static let website        = URL(string: "https://marque-173c3.web.app")!
    static let privacyPolicy  = URL(string: "https://marque-173c3.web.app/privacy")!
    static let termsOfService = URL(string: "https://marque-173c3.web.app/terms")!
    /// Public web page for one shared car (served by the `carPage` Cloud
    /// Function). Only meaningful while that car is public; a private car's
    /// URL shows a "this car isn't shared" page.
    static func carPage(id: String) -> URL {
        website.appendingPathComponent("car").appendingPathComponent(id)
    }
    static let support        = URL(string: "mailto:marqueofficialhq@gmail.com")!
}
