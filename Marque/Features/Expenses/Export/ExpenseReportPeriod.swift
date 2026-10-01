import Foundation

/// Period selector for FR-15 data export — a superset of the existing
/// `ExpensePeriod` (Car.swift) used by the in-app expense charts. Tax and
/// business expense reporting (FR-15.2) is inherently organized by calendar
/// year, so export needs a "2025", "2024", … option that the rolling
/// 30-day/6-month/1-year/all-time periods don't cover. Kept in its own type
/// (rather than widening `ExpensePeriod`, which is Models-owned and used
/// elsewhere for rolling-window UI) so this frontend feature doesn't require
/// a backend change.
enum ExpenseReportPeriod: Hashable {
    case rolling(ExpensePeriod)
    case calendarYear(Int)
}

extension ExpenseReportPeriod: Identifiable {
    var id: String {
        switch self {
        case .rolling(let period): return "rolling-\(period.rawValue)"
        case .calendarYear(let year): return "year-\(year)"
        }
    }
}

extension ExpenseReportPeriod {
    var displayName: String {
        switch self {
        case .rolling(let period): return period.rawValue
        case .calendarYear(let year): return String(year)
        }
    }

    /// Jan 1 00:00 (local) inclusive to next Jan 1 00:00 (local) exclusive,
    /// per the orchestrator's explicit bounds. Uses the given `calendar`
    /// (default `.current`, i.e. local time) — never UTC, per the project's
    /// date-handling convention (see CLAUDE.md's date-off-by-one pitfall).
    static func calendarYearBounds(_ year: Int, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    /// Whether `date` falls within this period. `now`/`calendar` are
    /// parameterized (defaulting to the real clock/local calendar) so this
    /// is exercisable deterministically from the self-check below.
    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .rolling(let period):
            switch period {
            case .month:
                let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return date >= start
            case .sixMonths:
                let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
                return date >= start
            case .year:
                let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                return date >= start
            case .allTime:
                return true
            }
        case .calendarYear(let year):
            guard let bounds = Self.calendarYearBounds(year, calendar: calendar) else { return false }
            return date >= bounds.start && date < bounds.end
        }
    }

    /// Every selectable calendar year, most recent first: from the current
    /// year back through the earliest year that has at least one maintenance
    /// record across `cars` (a continuous range — intervening years with no
    /// records still appear, e.g. so a user can confirm a lean year had
    /// nothing to report). Falls back to just the current year when there
    /// are no records at all.
    static func calendarYearOptions(cars: [Car], now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        let currentYear = calendar.component(.year, from: now)
        let recordYears = cars.flatMap { $0.maintenanceRecords }
            .map { calendar.component(.year, from: $0.date) }
        let earliest = min(recordYears.min() ?? currentYear, currentYear)
        return Array(stride(from: currentYear, through: earliest, by: -1))
    }

    /// All picker options: the four rolling periods, plus every calendar
    /// year option, most recent year first.
    static func allOptions(cars: [Car], now: Date = Date(), calendar: Calendar = .current) -> [ExpenseReportPeriod] {
        ExpensePeriod.allCases.map { ExpenseReportPeriod.rolling($0) } +
            calendarYearOptions(cars: cars, now: now, calendar: calendar).map { ExpenseReportPeriod.calendarYear($0) }
    }

    /// Default selection (orchestrator decision): the previous calendar year
    /// if it has at least one record across `cars`, else the rolling "1 Year"
    /// option.
    static func defaultSelection(cars: [Car], now: Date = Date(), calendar: Calendar = .current) -> ExpenseReportPeriod {
        let previousYear = calendar.component(.year, from: now) - 1
        let candidate = ExpenseReportPeriod.calendarYear(previousYear)
        let hasRecords = cars.contains { car in
            car.maintenanceRecords.contains { candidate.contains($0.date, now: now, calendar: calendar) }
        }
        return hasRecords ? candidate : .rolling(.year)
    }
}

// MARK: - Self-check

#if DEBUG
extension ExpenseReportPeriod {
    /// No XCTest target exists in this project (see CLAUDE.md); this is the
    /// documented substitute. Call manually from a debug entry point —
    /// nothing in the app invokes this automatically.
    static func _selfCheck() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.timeZone = calendar.timeZone

        func localDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
            var c = comps
            c.year = year; c.month = month; c.day = day
            return calendar.date(from: c)!
        }

        // Calendar-year bounds: Jan 1 00:00 inclusive to next Jan 1 exclusive.
        let bounds2025 = calendarYearBounds(2025, calendar: calendar)!
        assert(bounds2025.start == localDate(2025, 1, 1))
        assert(bounds2025.end == localDate(2026, 1, 1))

        let period2025 = ExpenseReportPeriod.calendarYear(2025)
        assert(period2025.contains(localDate(2025, 1, 1), calendar: calendar))       // inclusive lower bound
        assert(period2025.contains(localDate(2025, 12, 31), calendar: calendar))
        assert(!period2025.contains(localDate(2026, 1, 1), calendar: calendar))      // exclusive upper bound
        assert(!period2025.contains(localDate(2024, 12, 31), calendar: calendar))

        // Rolling periods still behave like Car.expenses(in:)'s own logic.
        let now = localDate(2026, 6, 15)
        let rollingMonth = ExpenseReportPeriod.rolling(.month)
        assert(rollingMonth.contains(localDate(2026, 6, 1), now: now, calendar: calendar))
        assert(!rollingMonth.contains(localDate(2026, 4, 1), now: now, calendar: calendar))
        assert(ExpenseReportPeriod.rolling(.allTime).contains(localDate(1990, 1, 1), now: now, calendar: calendar))

        // Calendar year options: continuous range from current year back to
        // the earliest year with a record, not just years that literally
        // have data.
        let cars = [
            Car(maintenanceRecords: [
                MaintenanceRecord(serviceType: "Oil Change", date: localDate(2023, 3, 1)),
            ])
        ]
        let options = ExpenseReportPeriod.calendarYearOptions(cars: cars, now: now, calendar: calendar)
        assert(options == [2026, 2025, 2024, 2023])

        // No records at all: falls back to just the current year.
        let noRecordsOptions = ExpenseReportPeriod.calendarYearOptions(cars: [Car()], now: now, calendar: calendar)
        assert(noRecordsOptions == [2026])

        // Default selection: previous year if it has records, else rolling 1 Year.
        let carsWithPriorYear = [
            Car(maintenanceRecords: [
                MaintenanceRecord(serviceType: "Oil Change", date: localDate(2025, 5, 1)),
            ])
        ]
        assert(ExpenseReportPeriod.defaultSelection(cars: carsWithPriorYear, now: now, calendar: calendar) == .calendarYear(2025))
        assert(ExpenseReportPeriod.defaultSelection(cars: [Car()], now: now, calendar: calendar) == .rolling(.year))
    }
}
#endif
