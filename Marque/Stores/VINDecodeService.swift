import Foundation

struct VINDecodeResult {
    var make: String
    var model: String
    var year: String
    var trim: String
    var bodyStyle: String
    var driveType: String
    var engine: String
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
            trim: dict["Trim"] ?? "",
            bodyStyle: normalizedBodyStyle(dict["Body Class"] ?? ""),
            driveType: normalizedDriveType(dict["Drive Type"] ?? ""),
            engine: buildEngineString(
                displacement: dict["Displacement (L)"] ?? "",
                cylinders: dict["Engine Number of Cylinders"] ?? "",
                configuration: dict["Engine Configuration"] ?? "",
                turbo: dict["Turbo"] ?? ""
            ),
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

    private static func normalizedBodyStyle(_ raw: String) -> String {
        let lower = raw.lowercased()
        // NHTSA "Body Class" values. Order matters: "Sport Utility Truck (SUT)"
        // (Avalanche, Santa Cruz) is a pickup, not an SUV.
        if lower.contains("sport utility truck") || lower.contains("sut") { return "Pickup" }
        if lower.contains("sport utility") || lower.contains("suv") { return "SUV" }
        if lower.contains("crossover") || lower.contains("cuv") { return "Crossover" }
        if lower.contains("pickup") { return "Pickup" }
        if lower.contains("sedan") { return "Sedan" }
        if lower.contains("hatchback") || lower.contains("liftback") { return "Hatchback" }
        if lower.contains("coupe") { return "Coupe" }
        if lower.contains("convertible") || lower.contains("cabriolet") || lower.contains("roadster") { return "Convertible" }
        if lower.contains("minivan") { return "Minivan" }
        if lower.contains("van") { return "Van" }
        if lower.contains("wagon") { return "Wagon" }
        if lower.contains("truck") { return "Pickup" }
        if lower.contains("limousine") { return "Sedan" }
        return ""
    }

    private static func normalizedDriveType(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("all-wheel") || lower.contains("awd") { return "AWD" }
        if lower.contains("4-wheel") || lower.contains("4wd") || lower.contains("4x4") { return "4WD" }
        if lower.contains("front-wheel") || lower.contains("fwd") { return "FWD" }
        if lower.contains("rear-wheel") || lower.contains("rwd") { return "RWD" }
        return ""
    }

    private static func buildEngineString(displacement: String, cylinders: String, configuration: String, turbo: String) -> String {
        guard !displacement.isEmpty || !cylinders.isEmpty else { return "" }
        var parts: [String] = []

        if !displacement.isEmpty, let d = Double(displacement) {
            parts.append(String(format: "%.1fL", d))
        }

        if !cylinders.isEmpty {
            let config = configuration.lowercased()
            if config == "v" {
                parts.append("V\(cylinders)")
            } else if config.contains("flat") || config.contains("opposed") {
                parts.append("Flat-\(cylinders)")
            } else {
                parts.append("\(cylinders)-Cylinder")
            }
        }

        if turbo.lowercased() == "yes" {
            parts.append("Turbo")
        }

        return parts.joined(separator: " ")
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
