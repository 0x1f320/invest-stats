import Foundation

/// A market whose trading hours the API reports: `/api/v1/market-calendar/{KR,US}`.
enum MarketRegion: String, CaseIterable, Hashable, Sendable {
    case kr = "KR"
    case us = "US"

    /// Shown in the UI, so the names are Korean.
    var title: String {
        switch self {
        case .kr: return "국내"
        case .us: return "미국"
        }
    }

    /// The market a stock trades on, from its trading currency.
    init?(currency: Currency) {
        switch currency {
        case .krw: self = .kr
        case .usd: self = .us
        case .unknown: return nil
        }
    }

    /// The market of a holding, from its `marketCountry`.
    init?(country: String) {
        self.init(rawValue: country.uppercased())
    }
}

// MARK: - API models

struct SessionHours: Decodable, Hashable, Sendable {
    let startTime: Date
    let endTime: Date
}

/// One business day of the domestic market. Hours are the integrated KRX + NXT hours,
/// without the off-hours closing price sessions. `integrated` is nil when both are closed.
struct KrMarketDay: Decodable, Hashable, Sendable {
    struct Integrated: Decodable, Hashable, Sendable {
        let preMarket: SessionHours?
        let regularMarket: SessionHours?
        let afterMarket: SessionHours?
    }

    let date: String
    let integrated: Integrated?
}

/// One business day of the US market, in US local dates. Every session is nil on a holiday.
struct UsMarketDay: Decodable, Hashable, Sendable {
    let date: String
    let dayMarket: SessionHours?
    let preMarket: SessionHours?
    let regularMarket: SessionHours?
    let afterMarket: SessionHours?
}

/// The previous, current and next business day, as the calendar endpoints return them.
struct MarketCalendarResponse<Day: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    let today: Day
    let previousBusinessDay: Day
    let nextBusinessDay: Day
}

// MARK: - Sessions

enum MarketSessionKind: Hashable, Sendable {
    /// Toss Securities' US day market, during Korean daytime.
    case day
    case pre
    case regular
    case after

    var title: String {
        switch self {
        case .day: return "데이마켓"
        case .pre: return "프리마켓"
        case .regular: return "정규장"
        case .after: return "애프터마켓"
        }
    }
}

struct MarketSession: Hashable, Sendable {
    let kind: MarketSessionKind
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

/// Whether a market is trading at a given moment.
enum MarketStatus: Hashable, Sendable {
    /// In a trading session.
    case open(MarketSession)
    /// Between sessions. `next` is nil when the calendar doesn't reach the next session.
    case closed(next: MarketSession?)

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}

/// The trading sessions of one market across the three business days the API returns.
/// All the session logic is here, apart from the network, so it can be tested.
struct MarketCalendar: Hashable, Sendable {
    let region: MarketRegion
    /// Sorted by start time.
    let sessions: [MarketSession]
    /// The first session of the next business day. Once it starts, the API's "today" has
    /// moved on and the calendar should be fetched again.
    let nextDayStart: Date?
    let fetchedAt: Date

    /// Fetched again after this long even when nothing else calls for it, so a schedule
    /// change (a holiday announced late, a shortened day) is picked up within the day.
    static let maxAge: TimeInterval = 6 * 3600

    init(region: MarketRegion, sessions: [MarketSession], nextDayStart: Date?, fetchedAt: Date) {
        self.region = region
        self.sessions = sessions.sorted { $0.start < $1.start }
        self.nextDayStart = nextDayStart
        self.fetchedAt = fetchedAt
    }

    init(kr response: MarketCalendarResponse<KrMarketDay>, fetchedAt: Date) {
        let days = [response.previousBusinessDay, response.today, response.nextBusinessDay]
        self.init(
            region: .kr,
            sessions: days.flatMap(Self.sessions(of:)),
            nextDayStart: Self.sessions(of: response.nextBusinessDay).map(\.start).min(),
            fetchedAt: fetchedAt
        )
    }

    init(us response: MarketCalendarResponse<UsMarketDay>, fetchedAt: Date) {
        let days = [response.previousBusinessDay, response.today, response.nextBusinessDay]
        self.init(
            region: .us,
            sessions: days.flatMap(Self.sessions(of:)),
            nextDayStart: Self.sessions(of: response.nextBusinessDay).map(\.start).min(),
            fetchedAt: fetchedAt
        )
    }

    private static func sessions(of day: KrMarketDay) -> [MarketSession] {
        guard let hours = day.integrated else { return [] }
        return [
            hours.preMarket.map { MarketSession(kind: .pre, start: $0.startTime, end: $0.endTime) },
            hours.regularMarket.map { MarketSession(kind: .regular, start: $0.startTime, end: $0.endTime) },
            hours.afterMarket.map { MarketSession(kind: .after, start: $0.startTime, end: $0.endTime) },
        ].compactMap { $0 }
    }

    private static func sessions(of day: UsMarketDay) -> [MarketSession] {
        [
            day.dayMarket.map { MarketSession(kind: .day, start: $0.startTime, end: $0.endTime) },
            day.preMarket.map { MarketSession(kind: .pre, start: $0.startTime, end: $0.endTime) },
            day.regularMarket.map { MarketSession(kind: .regular, start: $0.startTime, end: $0.endTime) },
            day.afterMarket.map { MarketSession(kind: .after, start: $0.startTime, end: $0.endTime) },
        ].compactMap { $0 }
    }

    /// The session trading at `date`, or the next one to open.
    func status(at date: Date) -> MarketStatus {
        if let current = sessions.first(where: { $0.contains(date) }) {
            return .open(current)
        }
        return .closed(next: sessions.first { $0.start > date })
    }

    /// Whether the calendar should be fetched again: it is old, or the next business day
    /// has started, so the API now has a later day to report.
    func needsRefresh(at date: Date) -> Bool {
        if date.timeIntervalSince(fetchedAt) >= Self.maxAge { return true }
        if let nextDayStart, date >= nextDayStart { return true }
        // Every session is behind: nothing tells when the market opens next.
        if let last = sessions.last, date >= last.end { return true }
        return sessions.isEmpty
    }
}

// MARK: - Text

/// The one-line status shown in popovers, e.g. `정규장 · 15:30까지` or
/// `장 마감 · 다음 개장 11/17 09:00`. Times are in `timeZone`, the Mac's by default.
enum MarketStatusText {
    static func describe(_ status: MarketStatus, timeZone: TimeZone = .current) -> String {
        switch status {
        case .open(let session):
            return "\(session.kind.title) · \(format(session.end, "HH:mm", timeZone))까지"
        case .closed(let next?):
            // The regular session is what "opening" means by default; name the others.
            let suffix = next.kind == .regular ? "" : " \(next.kind.title)"
            return "장 마감 · 다음 개장 \(format(next.start, "M/d HH:mm", timeZone))\(suffix)"
        case .closed(nil):
            return "장 마감"
        }
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension HoldingsOverview {
    /// The markets of the holdings. An account with no holdings could buy on either
    /// market, so it counts as both.
    var regions: Set<MarketRegion> {
        let regions = Set(items.compactMap { MarketRegion(country: $0.marketCountry) })
        return regions.isEmpty ? Set(MarketRegion.allCases) : regions
    }
}
