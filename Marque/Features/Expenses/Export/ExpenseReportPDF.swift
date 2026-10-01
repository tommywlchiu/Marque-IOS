import UIKit

/// FR-15.3/15.5: US-Letter, human-readable PDF service & expense report.
/// Pure generator — takes a snapshot of cars + a period, returns PDF `Data`.
/// No UI, no I/O beyond producing bytes; the caller decides where they go
/// (the iOS share sheet, per FR-15.6 — never emailed/uploaded by the app).
///
/// Renders in two passes over the identical layout logic: the first pass has
/// no drawing context (`Cursor.context == nil`) and only counts pages, so the
/// second (real) pass can print "Page X of Y" footers while it draws, rather
/// than needing a separate post-processing step.
enum ExpenseReportPDF {

    // MARK: - Page geometry (US Letter @ 72dpi)

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }
    // Leaves room for the footer below the main content area.
    private static var contentBottom: CGFloat { pageHeight - margin - 18 }

    // MARK: - Fonts

    private static let titleFont = UIFont.boldSystemFont(ofSize: 20)
    private static let metaFont = UIFont.systemFont(ofSize: 10)
    private static let carTitleFont = UIFont.boldSystemFont(ofSize: 15)
    private static let identityFont = UIFont.systemFont(ofSize: 10)
    private static let sectionFont = UIFont.boldSystemFont(ofSize: 13)
    private static let tableHeaderFont = UIFont.boldSystemFont(ofSize: 9)
    private static let tableBodyFont = UIFont.systemFont(ofSize: 9)
    private static let subtotalFont = UIFont.systemFont(ofSize: 10)
    private static let totalFont = UIFont.boldSystemFont(ofSize: 11)
    private static let footerFont = UIFont.systemFont(ofSize: 8)

    // Table columns (Date, Service, Shop, Mileage, Cost, Notes) as fractions
    // of contentWidth. Notes gets the most room since it's free text.
    private static let columnTitles = ["Date", "Service", "Shop", "Mileage", "Cost", "Notes"]
    private static let columnFractions: [CGFloat] = [0.14, 0.17, 0.15, 0.10, 0.09, 0.35]

    private static var columnX: [CGFloat] {
        var x = margin
        return columnFractions.map { frac in
            defer { x += contentWidth * frac }
            return x
        }
    }

    private static let tableDateFormatter: DateFormatter = {
        let f = DateFormatter()
        // Numeric (09/18/2026 in the US) so the date never wraps in its column.
        f.setLocalizedDateFormatFromTemplate("MMddyyyy")
        f.timeZone = .current
        return f
    }()

    /// "1 Year (Sep 30, 2025 – Sep 30, 2026)": a tax document has to say
    /// which dates it covers, not just a relative label. Bounds match
    /// `ExpenseReportPeriod.contains`.
    private static func periodDescription(_ period: ExpenseReportPeriod, now: Date, calendar: Calendar) -> String {
        let start: Date
        let end: Date
        switch period {
        case .rolling(.allTime):
            return period.displayName
        case .rolling(let rolling):
            let back: DateComponents
            switch rolling {
            case .month: back = DateComponents(month: -1)
            case .sixMonths: back = DateComponents(month: -6)
            default: back = DateComponents(year: -1)
            }
            start = calendar.date(byAdding: back, to: now) ?? now
            end = now
        case .calendarYear(let year):
            guard let bounds = ExpenseReportPeriod.calendarYearBounds(year, calendar: calendar),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: bounds.end) else {
                return period.displayName
            }
            start = bounds.start
            end = lastDay
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeZone = calendar.timeZone
        return "\(period.displayName) (\(f.string(from: start)) – \(f.string(from: end)))"
    }

    private static let generatedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.timeZone = .current
        return f
    }()

    // MARK: - Public API

    static func generate(
        cars: [Car],
        period: ExpenseReportPeriod,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> Data {
        // Pass 1: measure — no drawing context, just walk the layout to
        // count pages.
        let measuring = Cursor(context: nil)
        layout(cars: cars, period: period, now: now, calendar: calendar, locale: locale, cursor: measuring)
        let totalPages = measuring.pageCount

        // Pass 2: draw for real, now that totalPages is known up front.
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { rendererContext in
            let cursor = Cursor(context: rendererContext)
            cursor.totalPages = totalPages
            layout(cars: cars, period: period, now: now, calendar: calendar, locale: locale, cursor: cursor)
        }
    }

    // MARK: - Cursor

    /// Owns page/position state for one pass over the layout. `context` is
    /// nil during the measuring pass (nothing is actually drawn, but every
    /// height computation still runs, so page breaks land in the same place
    /// on both passes).
    private final class Cursor {
        let context: UIGraphicsPDFRendererContext?
        private(set) var pageCount = 0
        var y: CGFloat = margin
        var totalPages = 0
        private var headerRepeat: (() -> Void)?

        init(context: UIGraphicsPDFRendererContext?) {
            self.context = context
        }

        func setHeaderRepeat(_ block: (() -> Void)?) {
            headerRepeat = block
        }

        /// Starts a new page if there's no current page yet, or if `height`
        /// wouldn't fit in what's left of this one.
        func ensureSpace(_ height: CGFloat) {
            if pageCount == 0 || y + height > contentBottom {
                beginPage()
            }
        }

        func beginPage() {
            pageCount += 1
            context?.beginPage()
            y = margin
            if context != nil, totalPages > 0 {
                drawFooter(pageNumber: pageCount, totalPages: totalPages)
            }
            headerRepeat?()
        }
    }

    // MARK: - Layout

    private static func layout(
        cars: [Car],
        period: ExpenseReportPeriod,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        cursor: Cursor
    ) {
        line("Vehicle Service & Expense Report", font: titleFont, spacingAfter: 6, cursor: cursor)
        line(
            "Period: \(periodDescription(period, now: now, calendar: calendar))    ·    Generated: \(generatedDateFormatter.string(from: now))",
            font: metaFont, color: .darkGray, spacingAfter: 18, cursor: cursor
        )

        var garageCategoryTotals: [String: Double] = [:]
        var garageGrandTotal: Double = 0
        let isMultiCar = cars.count > 1

        for car in cars {
            let (categoryTotals, carTotal) = drawCarSection(
                car: car, period: period, now: now, calendar: calendar, locale: locale, cursor: cursor
            )
            for (category, amount) in categoryTotals {
                garageCategoryTotals[category, default: 0] += amount
            }
            garageGrandTotal += carTotal
        }

        if isMultiCar {
            drawGarageSummary(categoryTotals: garageCategoryTotals, grandTotal: garageGrandTotal, locale: locale, cursor: cursor)
        }
    }

    /// Draws one car's identity block + service log table + subtotals.
    /// Returns its category totals and grand total so the caller can roll
    /// them into a garage-wide summary.
    @discardableResult
    private static func drawCarSection(
        car: Car,
        period: ExpenseReportPeriod,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        cursor: Cursor
    ) -> (categoryTotals: [String: Double], carTotal: Double) {
        line(car.displayName, font: carTitleFont, spacingAfter: 3, cursor: cursor)

        var identityParts: [String] = []
        if !car.trim.isEmpty { identityParts.append("Trim: \(car.trim)") }
        if !car.vinNumber.isEmpty { identityParts.append("VIN: \(car.vinNumber)") }
        if !car.licensePlate.isEmpty { identityParts.append("Plate: \(car.licensePlate)") }
        if !car.mileage.isEmpty { identityParts.append("Mileage: \(car.mileage) mi") }
        if !identityParts.isEmpty {
            line(identityParts.joined(separator: "   ·   "), font: identityFont, color: .darkGray, spacingAfter: 12, cursor: cursor)
        } else {
            cursor.y += 6
        }

        let records = car.maintenanceRecords
            .filter { period.contains($0.date, now: now, calendar: calendar) }
            .sorted { $0.date < $1.date }

        guard !records.isEmpty else {
            line("No service records in this period.", font: identityFont, color: .gray, spacingAfter: 22, cursor: cursor)
            return ([:], 0)
        }

        cursor.setHeaderRepeat { drawTableHeader(cursor: cursor) }
        drawTableHeader(cursor: cursor)

        var categoryTotals: [String: Double] = [:]
        var carTotal: Double = 0
        for record in records {
            processRow(record, cursor: cursor, locale: locale)
            if let cost = record.costValue, cost > 0 {
                categoryTotals[record.serviceType, default: 0] += cost
                carTotal += cost
            }
        }
        cursor.setHeaderRepeat(nil)
        cursor.y += 8

        let subtotalLines = categoryTotals.count + 1
        cursor.ensureSpace(CGFloat(subtotalLines) * 15 + 10)
        for (category, amount) in categoryTotals.sorted(by: { $0.value > $1.value }) {
            line("\(category): \(currency(amount, locale: locale))", font: subtotalFont, spacingAfter: 3, cursor: cursor)
        }
        line("Car Total: \(currency(carTotal, locale: locale))", font: totalFont, spacingAfter: 22, cursor: cursor)

        return (categoryTotals, carTotal)
    }

    private static func drawGarageSummary(categoryTotals: [String: Double], grandTotal: Double, locale: Locale, cursor: Cursor) {
        line("Garage Summary", font: sectionFont, spacingAfter: 10, cursor: cursor)
        for (category, amount) in categoryTotals.sorted(by: { $0.value > $1.value }) {
            line("\(category): \(currency(amount, locale: locale))", font: subtotalFont, spacingAfter: 3, cursor: cursor)
        }
        line("Grand Total: \(currency(grandTotal, locale: locale))", font: totalFont, spacingAfter: 4, cursor: cursor)
    }

    // MARK: - Table drawing

    private static func drawTableHeader(cursor: Cursor) {
        let xs = columnX
        cursor.ensureSpace(20)
        let rowTop = cursor.y
        var maxHeight: CGFloat = 0
        for (i, title) in columnTitles.enumerated() {
            let width = contentWidth * columnFractions[i] - 4
            let height = drawCell(title, font: tableHeaderFont, at: CGPoint(x: xs[i], y: rowTop), width: width, cursor: cursor)
            maxHeight = max(maxHeight, height)
        }
        cursor.y = rowTop + maxHeight + 3
        if cursor.context != nil {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: cursor.y))
            path.addLine(to: CGPoint(x: margin + contentWidth, y: cursor.y))
            path.lineWidth = 0.75
            UIColor.black.setStroke()
            path.stroke()
        }
        cursor.y += 5
    }

    /// Measures + (on the draw pass) renders one full table row, wrapping
    /// each column independently and sizing the row to the tallest column —
    /// notes/shop text never clips, it wraps.
    private static func processRow(_ record: MaintenanceRecord, cursor: Cursor, locale: Locale) {
        let xs = columnX
        let fields = [
            tableDateFormatter.string(from: record.date),
            record.serviceType,
            record.shop,
            record.mileage.isEmpty ? "—" : record.mileage,
            record.costValue.map { currency($0, locale: locale) } ?? "—",
            record.notes,
        ]

        var heights: [CGFloat] = []
        for (i, fieldText) in fields.enumerated() {
            let width = contentWidth * columnFractions[i] - 4
            heights.append(measuredHeight(fieldText, font: tableBodyFont, width: width))
        }
        let rowHeight = (heights.max() ?? 12) + 8

        cursor.ensureSpace(rowHeight)
        let rowTop = cursor.y
        if cursor.context != nil {
            for (i, fieldText) in fields.enumerated() {
                let width = contentWidth * columnFractions[i] - 4
                drawCell(fieldText, font: tableBodyFont, at: CGPoint(x: xs[i], y: rowTop), width: width, cursor: cursor, explicitHeight: heights[i])
            }
        }
        cursor.y = rowTop + rowHeight

        if cursor.context != nil {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: cursor.y))
            path.addLine(to: CGPoint(x: margin + contentWidth, y: cursor.y))
            path.lineWidth = 0.25
            UIColor(white: 0.85, alpha: 1).setStroke()
            path.stroke()
        }
    }

    // MARK: - Low-level drawing helpers

    /// Draws one left-aligned, word-wrapped block of text spanning the full
    /// content width, always via `ensureSpace` first so it can never be
    /// split across a page break — used for everything outside the table.
    @discardableResult
    private static func line(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat, cursor: Cursor) -> CGFloat {
        let height = measuredHeight(text, font: font, width: contentWidth)
        cursor.ensureSpace(height + spacingAfter)
        if cursor.context != nil {
            drawString(text, font: font, color: color, rect: CGRect(x: margin, y: cursor.y, width: contentWidth, height: height))
        }
        cursor.y += height + spacingAfter
        return height
    }

    /// Draws one table cell at a fixed origin without touching the cursor
    /// (row layout is coordinated by the caller, which draws every column at
    /// the same top and advances the cursor once for the whole row).
    @discardableResult
    private static func drawCell(_ text: String, font: UIFont, at origin: CGPoint, width: CGFloat, cursor: Cursor, explicitHeight: CGFloat? = nil) -> CGFloat {
        let height = explicitHeight ?? measuredHeight(text, font: font, width: width)
        if cursor.context != nil {
            drawString(text, font: font, color: .black, rect: CGRect(x: origin.x, y: origin.y, width: width, height: height))
        }
        return height
    }

    private static func measuredHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 12 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bound = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        return max(ceil(bound.height), font.lineHeight)
    }

    private static func drawString(_ text: String, font: UIFont, color: UIColor, rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    }

    private static func drawFooter(pageNumber: Int, totalPages: Int) {
        let text = "Page \(pageNumber) of \(totalPages)"
        let attrs: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: UIColor.gray]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: (pageWidth - size.width) / 2, y: pageHeight - margin + 4, width: size.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    // MARK: - Currency

    private static func currency(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
