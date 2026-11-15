import Foundation
import Testing
@testable import TossBar

@Suite("Market calendar")
struct MarketCalendarTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try TossAPIClient.makeDecoder().decode(type, from: Data(json.utf8))
    }

    private func kst(_ string: String) -> Date {
        DateParsing.parse(string + "+09:00")!
    }

    private static func krDay(_ date: String, pre: Bool = true) -> String {
        #"""
        {"date": "\#(date)", "integrated": {
          "preMarket": \#(pre ? #"{"startTime": "\#(date)T08:00:00+09:00", "singlePriceAuctionStartTime": "\#(date)T08:50:00+09:00", "endTime": "\#(date)T09:00:00+09:00"}"# : "null"),
          "regularMarket": {"startTime": "\#(date)T09:00:00+09:00", "singlePriceAuctionStartTime": "\#(date)T15:20:00+09:00", "endTime": "\#(date)T15:30:00+09:00"},
          "afterMarket": {"startTime": "\#(date)T15:30:00+09:00", "singlePriceAuctionEndTime": "\#(date)T15:40:00+09:00", "endTime": "\#(date)T20:00:00+09:00"}
        }}
        """#
    }

    private static func usDay(_ date: String, _ nextDate: String) -> String {
        #"""
        {"date": "\#(date)",
         "dayMarket": {"startTime": "\#(date)T09:00:00+09:00", "endTime": "\#(date)T16:50:00+09:00"},
         "preMarket": {"startTime": "\#(date)T17:00:00+09:00", "endTime": "\#(date)T22:30:00+09:00"},
         "regularMarket": {"startTime": "\#(date)T22:30:00+09:00", "endTime": "\#(nextDate)T05:00:00+09:00"},
         "afterMarket": {"startTime": "\#(nextDate)T05:00:00+09:00", "endTime": "\#(nextDate)T07:00:00+09:00"}}
        """#
    }

    /// The API's business day example: 2026-03-24 to 2026-03-26, both venues open.
    private func krBusinessDay(fetchedAt: Date? = nil) throws -> MarketCalendar {
        let json = #"{"result": {"previousBusinessDay": \#(Self.krDay("2026-03-24")), "today": \#(Self.krDay("2026-03-25")), "nextBusinessDay": \#(Self.krDay("2026-03-26"))}}"#
        let response = try decode(ApiEnvelope<MarketCalendarResponse<KrMarketDay>>.self, json).result
        return MarketCalendar(kr: response, fetchedAt: fetchedAt ?? kst("2026-03-25T07:00:00"))
    }

    private func usBusinessDay() throws -> MarketCalendar {
        let json = #"{"result": {"previousBusinessDay": \#(Self.usDay("2026-03-24", "2026-03-25")), "today": \#(Self.usDay("2026-03-25", "2026-03-26")), "nextBusinessDay": \#(Self.usDay("2026-03-26", "2026-03-27"))}}"#
        let response = try decode(ApiEnvelope<MarketCalendarResponse<UsMarketDay>>.self, json).result
        return MarketCalendar(us: response, fetchedAt: kst("2026-03-25T07:00:00"))
    }

    // MARK: Decoding

    @Test func decodesDomesticBusinessDays() throws {
        let calendar = try krBusinessDay()
        #expect(calendar.region == .kr)
        #expect(calendar.sessions.count == 9)
        #expect(calendar.sessions.first == MarketSession(kind: .pre, start: kst("2026-03-24T08:00:00"), end: kst("2026-03-24T09:00:00")))
        #expect(calendar.nextDayStart == kst("2026-03-26T08:00:00"))
    }

    @Test func domesticHolidayHasNoSessions() throws {
        let json = #"""
        {"previousBusinessDay": \#(Self.krDay("2026-05-04")),
         "today": {"date": "2026-05-05", "integrated": null},
         "nextBusinessDay": \#(Self.krDay("2026-05-06"))}
        """#
        let response = try decode(MarketCalendarResponse<KrMarketDay>.self, json)
        #expect(response.today.integrated == nil)
        let calendar = MarketCalendar(kr: response, fetchedAt: kst("2026-05-05T10:00:00"))
        #expect(calendar.sessions.count == 6)
        #expect(calendar.status(at: kst("2026-05-05T10:00:00")) == .closed(next: MarketSession(
            kind: .pre, start: kst("2026-05-06T08:00:00"), end: kst("2026-05-06T09:00:00"))))
    }

    @Test func missingPreMarketIsSkipped() throws {
        let json = #"""
        {"previousBusinessDay": \#(Self.krDay("2026-03-24")),
         "today": \#(Self.krDay("2026-03-25", pre: false)),
         "nextBusinessDay": \#(Self.krDay("2026-03-26"))}
        """#
        let calendar = MarketCalendar(kr: try decode(MarketCalendarResponse<KrMarketDay>.self, json), fetchedAt: Date())
        #expect(calendar.sessions.count == 8)
        // 08:30 that day is before the regular session, which opens next.
        #expect(calendar.status(at: kst("2026-03-25T08:30:00")) == .closed(next: MarketSession(
            kind: .regular, start: kst("2026-03-25T09:00:00"), end: kst("2026-03-25T15:30:00"))))
    }

    @Test func usHolidayHasNoSessions() throws {
        let json = #"""
        {"previousBusinessDay": \#(Self.usDay("2026-07-02", "2026-07-03")),
         "today": {"date": "2026-07-03", "dayMarket": null, "preMarket": null, "regularMarket": null, "afterMarket": null},
         "nextBusinessDay": \#(Self.usDay("2026-07-06", "2026-07-07"))}
        """#
        let calendar = MarketCalendar(us: try decode(MarketCalendarResponse<UsMarketDay>.self, json), fetchedAt: Date())
        #expect(calendar.sessions.count == 8)
        #expect(calendar.status(at: kst("2026-07-03T23:00:00")) == .closed(next: MarketSession(
            kind: .day, start: kst("2026-07-06T09:00:00"), end: kst("2026-07-06T16:50:00"))))
    }

    // MARK: Status

    @Test(arguments: [
        ("2026-03-25T08:00:00", MarketSessionKind.pre),
        ("2026-03-25T08:59:59", .pre),
        ("2026-03-25T09:00:00", .regular),
        ("2026-03-25T15:29:00", .regular),
        ("2026-03-25T15:30:00", .after),
        ("2026-03-25T19:59:00", .after),
    ])
    func domesticSessionAt(_ time: String, _ kind: MarketSessionKind) throws {
        guard case .open(let session) = try krBusinessDay().status(at: kst(time)) else {
            Issue.record("closed at \(time)")
            return
        }
        #expect(session.kind == kind)
    }

    @Test func domesticClosedOvernightPointsAtNextPreMarket() throws {
        let status = try krBusinessDay().status(at: kst("2026-03-25T20:00:00"))
        #expect(status == .closed(next: MarketSession(kind: .pre, start: kst("2026-03-26T08:00:00"), end: kst("2026-03-26T09:00:00"))))
        #expect(!status.isOpen)
    }

    @Test(arguments: [
        ("2026-03-25T06:30:00", MarketSessionKind.after), // The previous day's after market.
        ("2026-03-25T09:00:00", .day),
        ("2026-03-25T17:00:00", .pre),
        ("2026-03-25T23:00:00", .regular),
        ("2026-03-26T04:59:00", .regular),
        ("2026-03-26T05:00:00", .after),
    ])
    func usSessionAt(_ time: String, _ kind: MarketSessionKind) throws {
        guard case .open(let session) = try usBusinessDay().status(at: kst(time)) else {
            Issue.record("closed at \(time)")
            return
        }
        #expect(session.kind == kind)
    }

    @Test func usGapsAreClosed() throws {
        let calendar = try usBusinessDay()
        // Between the day market and the pre market.
        #expect(calendar.status(at: kst("2026-03-25T16:55:00")) == .closed(next: MarketSession(
            kind: .pre, start: kst("2026-03-25T17:00:00"), end: kst("2026-03-25T22:30:00"))))
        // Between the after market and the next day market.
        #expect(calendar.status(at: kst("2026-03-26T08:00:00")) == .closed(next: MarketSession(
            kind: .day, start: kst("2026-03-26T09:00:00"), end: kst("2026-03-26T16:50:00"))))
    }

    @Test func pastTheLastSessionHasNoNextSession() throws {
        #expect(try krBusinessDay().status(at: kst("2026-03-26T21:00:00")) == .closed(next: nil))
    }

    // MARK: Refresh

    @Test func refreshesWhenOldOrPastTheNextBusinessDay() throws {
        let calendar = try krBusinessDay(fetchedAt: kst("2026-03-25T07:00:00"))
        #expect(!calendar.needsRefresh(at: kst("2026-03-25T10:00:00")))
        // Six hours after fetching.
        #expect(calendar.needsRefresh(at: kst("2026-03-25T13:00:00")))

        let overnight = try krBusinessDay(fetchedAt: kst("2026-03-26T05:00:00"))
        #expect(!overnight.needsRefresh(at: kst("2026-03-26T07:59:00")))
        // The next business day has started, so the API has a later day to report.
        #expect(overnight.needsRefresh(at: kst("2026-03-26T08:00:00")))
    }

    @Test func emptyCalendarNeedsRefresh() {
        let calendar = MarketCalendar(region: .us, sessions: [], nextDayStart: nil, fetchedAt: Date())
        #expect(calendar.needsRefresh(at: Date()))
        #expect(calendar.status(at: Date()) == .closed(next: nil))
    }

    // MARK: Text

    @Test func describesOpenSession() throws {
        let status = try krBusinessDay().status(at: kst("2026-03-25T10:00:00"))
        #expect(MarketStatusText.describe(status, timeZone: seoul) == "정규장 · 15:30까지")
    }

    @Test func describesNextOpening() throws {
        let calendar = try krBusinessDay()
        #expect(MarketStatusText.describe(calendar.status(at: kst("2026-03-25T21:00:00")), timeZone: seoul)
            == "장 마감 · 다음 개장 3/26 08:00 프리마켓")
        let regular = MarketStatus.closed(next: MarketSession(kind: .regular, start: kst("2026-11-17T09:00:00"), end: kst("2026-11-17T15:30:00")))
        #expect(MarketStatusText.describe(regular, timeZone: seoul) == "장 마감 · 다음 개장 11/17 09:00")
        #expect(MarketStatusText.describe(.closed(next: nil), timeZone: seoul) == "장 마감")
    }

    @Test func usSessionNames() throws {
        let calendar = try usBusinessDay()
        #expect(MarketStatusText.describe(calendar.status(at: kst("2026-03-25T18:00:00")), timeZone: seoul) == "프리마켓 · 22:30까지")
        #expect(MarketStatusText.describe(calendar.status(at: kst("2026-03-25T23:00:00")), timeZone: seoul) == "정규장 · 05:00까지")
        #expect(MarketStatusText.describe(calendar.status(at: kst("2026-03-26T06:00:00")), timeZone: seoul) == "애프터마켓 · 07:00까지")
    }

    // MARK: Regions

    @Test func regionsFromCurrencyAndCountry() {
        #expect(MarketRegion(currency: .krw) == .kr)
        #expect(MarketRegion(currency: .usd) == .us)
        #expect(MarketRegion(currency: .unknown) == nil)
        #expect(MarketRegion(country: "US") == .us)
        #expect(MarketRegion(country: "kr") == .kr)
        #expect(MarketRegion(country: "JP") == nil)
    }

    @Test func holdingsRegions() throws {
        let overview = try decode(HoldingsOverview.self, Fixtures.holdingsJSON)
        #expect(overview.regions == [.kr, .us])

        let domestic = Fixtures.holdingsJSON.replacingOccurrences(of: #""marketCountry": "US""#, with: #""marketCountry": "KR""#)
        #expect(try decode(HoldingsOverview.self, domestic).regions == [.kr])
    }
}
