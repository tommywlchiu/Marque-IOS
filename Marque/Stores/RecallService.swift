import Foundation

/// One open NHTSA recall campaign for a vehicle.
struct Recall: Codable, Identifiable, Equatable {
    let campaignNumber: String
    let component: String
    let summary: String
    let consequence: String
    let remedy: String
    let reportDate: Date?
    /// NHTSA's own "do not drive" flag for this campaign.
    let parkIt: Bool
    /// NHTSA's own "fire risk — park away from structures" flag.
    let parkOutside: Bool

    var id: String { campaignNumber }

    /// NHTSA's `Component` is an ALL-CAPS colon-joined taxonomy path (e.g.
    /// "AIR BAGS:FRONTAL:DRIVER SIDE:INFLATOR MODULE") — readable as data,
    /// not as a sentence shown to an owner. Title-cased and dash-joined for
    /// display; `component` itself is left untouched for anything that
    /// wants the raw value.
    var displayComponent: String {
        component.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces).capitalized }.joined(separator: " – ")
    }
}

enum RecallServiceError: Error {
    case invalidQuery
    case networkError(Error)
    case decodeError
}

/// Free, keyless lookup against NHTSA's public recalls API — the same
/// agency (and the same trust level) as `VINDecodeService`'s VIN decode.
/// Recalls are a property of the make/model/year, not of one owner's car,
/// so results are never written to a `Car` document; `RecallStore` caches
/// them in memory only, per make+model+year, for the running session.
struct RecallService {
    struct Response: Decodable {
        struct Item: Decodable {
            let NHTSACampaignNumber: String
            let Component: String
            let Summary: String
            let Consequence: String
            let Remedy: String
            let ReportReceivedDate: String
            // Optional: NHTSA sends `null` for these on plenty of real
            // campaigns (confirmed against live data, not a hypothetical) —
            // declaring them as a plain Bool made JSONDecoder fail the
            // *entire* array the moment one entry hit this, which a bare
            // `try?` at the call site then swallowed into "no recalls".
            let parkIt: Bool?
            let parkOutSide: Bool?
        }
        let results: [Item]
    }

    /// Pulled out of `fetchRecalls` so the null-`parkIt`/`parkOutSide`
    /// handling (and anything like it found later) is unit-testable without
    /// a live network call — see `RecallServiceTests`.
    static func decode(_ data: Data) throws -> [Recall] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw RecallServiceError.decodeError
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        return response.results.map { item in
            Recall(
                campaignNumber: item.NHTSACampaignNumber,
                component: item.Component,
                summary: item.Summary,
                consequence: item.Consequence,
                remedy: item.Remedy,
                reportDate: dateFormatter.date(from: item.ReportReceivedDate),
                parkIt: item.parkIt ?? false,
                parkOutside: item.parkOutSide ?? false
            )
        }
    }

    static func fetchRecalls(make: String, model: String, year: String) async throws -> [Recall] {
        var components = URLComponents(string: "https://api.nhtsa.gov/recalls/recallsByVehicle")
        components?.queryItems = [
            URLQueryItem(name: "make", value: make),
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "modelYear", value: year),
        ]
        guard let url = components?.url else { throw RecallServiceError.invalidQuery }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw RecallServiceError.networkError(error)
        }

        return try decode(data)
    }
}
