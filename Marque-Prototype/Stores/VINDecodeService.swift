import Foundation

struct VINDecodeResult {
    var make: String
    var model: String
    var year: String
    var fuelType: String
    var transmission: String
}

enum VINDecodeError: LocalizedError {
    case invalidLength
    case networkError(Error)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidLength: return "VIN must be exactly 17 characters."
        case .networkError(let e): return e.localizedDescription
        case .noResults: return "No vehicle found for this VIN. Please check and try again."
        }
    }
}

struct VINDecodeService {
    static func decode(vin: String) async throws -> VINDecodeResult {
        let trimmed = vin.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 17 else { throw VINDecodeError.invalidLength }

        guard let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/\(trimmed)?format=json") else {
            throw VINDecodeError.noResults
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw VINDecodeError.networkError(error)
        }

        struct Response: Decodable {
            let Results: [VINVariable]
        }
        struct VINVariable: Decodable {
            let Variable: String
            let Value: String?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)

        var dict: [String: String] = [:]
        for variable in response.Results {
            if let val = variable.Value, !val.isEmpty, val != "Not Applicable", val != "0" {
                dict[variable.Variable] = val
            }
        }

        guard dict["Make"] != nil || dict["Model"] != nil else {
            throw VINDecodeError.noResults
        }

        return VINDecodeResult(
            make: normalizedMake(dict["Make"] ?? ""),
            model: dict["Model"] ?? "",
            year: dict["Model Year"] ?? "",
            fuelType: normalizedFuelType(dict["Fuel Type - Primary"] ?? ""),
            transmission: normalizedTransmission(dict["Transmission Style"] ?? "")
        )
    }

    private static func normalizedMake(_ raw: String) -> String {
        let lower = raw.lowercased()
        for make in CarData.makes where make.lowercased() == lower {
            return make
        }
        return raw.capitalized
    }

    private static func normalizedFuelType(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("plug-in") || lower.contains("phev") { return "Plug-in Hybrid" }
        if lower.contains("hybrid") { return "Hybrid" }
        if lower.contains("gasoline") || lower.contains("petrol") { return "Gasoline" }
        if lower.contains("diesel") { return "Diesel" }
        if lower.contains("electric") { return "Electric" }
        if lower.contains("flex") || lower.contains("ethanol") { return "Flex Fuel" }
        return ""
    }

    private static func normalizedTransmission(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("continuously") || lower.contains("cvt") { return "CVT" }
        if lower.contains("dual") || lower.contains("dct") || lower.contains("dsg") { return "Dual-Clutch" }
        if lower.contains("automatic") { return "Automatic" }
        if lower.contains("manual") { return "Manual" }
        return ""
    }
}
