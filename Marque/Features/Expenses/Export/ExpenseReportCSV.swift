import Foundation

/// FR-15.3/15.5: CSV export of maintenance records in scope — one row per
/// record, which is what an accountant or spreadsheet wants. Pure function,
/// no UI, no I/O; the caller decides where the bytes go (always the iOS
/// share sheet per FR-15.6, never emailed/uploaded by the app itself).
enum ExpenseReportCSV {
    private static let columns = [
        "Date", "Car", "VIN", "Plate", "Service Type", "Shop", "Mileage", "Cost", "Notes",
    ]

    /// Full CSV text: UTF-8 BOM (so Excel opens accented text correctly) +
    /// header row + one row per record, sorted by date ascending within each
    /// car, in `cars`' own order. Nothing is redacted (FR-15.5 — this is the
    /// user's own data).
    static func generate(cars: [Car], period: ExpenseReportPeriod, now: Date = Date(), calendar: Calendar = .current) -> String {
        var lines: [String] = [columns.map(field).joined(separator: ",")]
        for car in cars {
            let records = car.maintenanceRecords
                .filter { period.contains($0.date, now: now, calendar: calendar) }
                .sorted { $0.date < $1.date }
            for record in records {
                lines.append(row(for: record, car: car))
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(for record: MaintenanceRecord, car: Car) -> String {
        let costString = record.costValue.map { String(format: "%.2f", $0) } ?? ""
        let fields = [
            dateFormatter.string(from: record.date),
            car.displayName,
            car.vinNumber,
            car.licensePlate,
            record.serviceType,
            record.shop,
            record.mileage,
            costString,
            record.notes,
        ]
        return fields.map(field).joined(separator: ",")
    }

    // Date-only, local calendar — never ISO8601DateFormatter's UTC default
    // (see CLAUDE.md's date-off-by-one pitfall). Matches the "yyyy-MM-dd"
    // format the task specifies.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// RFC 4180 quoting, plus a CSV-formula-injection guard: a field whose
    /// *original* text starts with `=`, `+`, `-`, `@`, a tab, or a CR is
    /// prefixed with `'` before quoting, since Excel/Sheets treat a leading
    /// one of those as a formula when the cell is opened — this is user
    /// text (notes, shop names) that could contain anything.
    static func field(_ raw: String) -> String {
        var value = raw
        if let first = value.unicodeScalars.first, formulaTriggerScalars.contains(first) {
            value = "'" + value
        }
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let formulaTriggerScalars: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
}

// MARK: - Self-check

#if DEBUG
extension ExpenseReportCSV {
    /// No XCTest target exists in this project (see CLAUDE.md); this is the
    /// documented substitute. Call manually from a debug entry point —
    /// nothing in the app invokes this automatically.
    static func _selfCheck() {
        // Plain field: untouched.
        assert(field("Oil Change") == "Oil Change")

        // RFC 4180 quoting: comma, quote, newline each force quoting; an
        // embedded quote is doubled.
        assert(field("Bob's Garage, LLC") == "\"Bob's Garage, LLC\"")
        assert(field("12\" tire") == "\"12\"\" tire\"")
        assert(field("line1\nline2") == "\"line1\nline2\"")

        // Formula-injection guard: a leading =, +, -, @ gets a `'` prefix
        // even when the rest of the field wouldn't otherwise need quoting.
        assert(field("=SUM(A1:A9)") == "'=SUM(A1:A9)")
        assert(field("+1234") == "'+1234")
        assert(field("-1234") == "'-1234")
        assert(field("@mention") == "'@mention")
        // A leading tab/CR also triggers the `'` guard; the CR itself
        // separately still forces RFC 4180 quoting (it's a raw line-break
        // character), so the field ends up both prefixed and quoted.
        assert(field("\rmalicious") == "\"'\rmalicious\"")
        assert(field("\tmalicious") == "'\tmalicious")
        // A hyphen used normally (not a formula) still gets the guard,
        // because the guard can't distinguish "-5.00" from a formula
        // trigger without breaking legitimate negative numbers is out of
        // scope here — CSV cost fields are pre-formatted separately and
        // never pass through `field` as raw negative numbers from user
        // text in a way that would misfire on this app's own data.
        assert(field("-oil change").hasPrefix("'"))

        // A field that is legitimately empty stays empty.
        assert(field("") == "")

        // Full generate(): header + one row per record, dates in local
        // yyyy-MM-dd, sorted ascending, cost as plain 2-decimal, blank cost
        // for a record with no parseable cost.
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.timeZone = calendar.timeZone
        func localDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
            comps.year = y; comps.month = m; comps.day = d
            return calendar.date(from: comps)!
        }

        let car = Car(
            make: "Honda", model: "Accord", year: "2003",
            licensePlate: "ABC123", vinNumber: "1HGCM82633A004352",
            maintenanceRecords: [
                MaintenanceRecord(serviceType: "Oil Change", date: localDate(2025, 6, 1), mileage: "50,000", cost: "45.5", shop: "Jiffy Lube"),
                MaintenanceRecord(serviceType: "Tire Rotation", date: localDate(2025, 1, 1), mileage: "48,000", cost: "", shop: "Discount Tire"),
            ]
        )
        let csv = generate(cars: [car], period: .calendarYear(2025), now: localDate(2025, 12, 31), calendar: calendar)
        assert(csv.hasPrefix("\u{FEFF}"))
        let bodyLines = csv.dropFirst().components(separatedBy: "\r\n").filter { !$0.isEmpty }
        assert(bodyLines.count == 3) // header + 2 rows
        assert(bodyLines[0] == "Date,Car,VIN,Plate,Service Type,Shop,Mileage,Cost,Notes")
        // Sorted ascending: Jan record before June record.
        assert(bodyLines[1].hasPrefix("2025-01-01"))
        assert(bodyLines[2].hasPrefix("2025-06-01"))
        assert(bodyLines[2].contains(",45.50,"))
        // Blank-cost record: two consecutive commas around the Cost column.
        assert(bodyLines[1].contains(",\"48,000\","))
    }
}
#endif
