import Foundation
import Testing
@testable import TossBar

@Suite("Polling policy")
struct PollingPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var regular: MarketSession {
        MarketSession(kind: .regular, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600))
    }

    private var nextOpening: MarketSession {
        MarketSession(kind: .pre, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
    }

    @Test func idleWhenEveryMarketIsClosed() {
        let idle = PollingPolicy.isIdle(itemRegions: [[.kr], [.kr, .us]]) { _ in .closed(next: nextOpening) }
        #expect(idle)
    }

    @Test func notIdleWhileAnyMarketIsOpen() {
        let idle = PollingPolicy.isIdle(itemRegions: [[.kr], [.us]]) { region in
            region == .us ? .open(regular) : .closed(next: nextOpening)
        }
        #expect(!idle)
    }

    @Test func unknownCountsAsOpen() {
        // An item whose market isn't known yet.
        #expect(!PollingPolicy.isIdle(itemRegions: [[.kr], nil]) { _ in .closed(next: nextOpening) })
        // A market without a calendar.
        #expect(!PollingPolicy.isIdle(itemRegions: [[.kr, .us]]) { $0 == .kr ? .closed(next: nextOpening) : nil })
        // A calendar that doesn't reach the next session.
        #expect(!PollingPolicy.isIdle(itemRegions: [[.kr]]) { _ in .closed(next: nil) })
        // No items at all.
        #expect(!PollingPolicy.isIdle(itemRegions: []) { _ in .closed(next: nextOpening) })
    }

    @Test func dueAtTheRefreshIntervalWhileOpen() {
        #expect(PollingPolicy.isDue(lastRefresh: nil, now: now, interval: 10, idle: false))
        #expect(!PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-5), now: now, interval: 10, idle: false))
        // Timer jitter doesn't skip a tick.
        #expect(PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-9.8), now: now, interval: 10, idle: false))
    }

    @Test func dueAtTheIdleIntervalWhileClosed() {
        #expect(PollingPolicy.isDue(lastRefresh: nil, now: now, interval: 10, idle: true))
        #expect(!PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-60), now: now, interval: 10, idle: true))
        #expect(PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-300), now: now, interval: 10, idle: true))
    }

    @Test func longerRefreshIntervalWins() {
        #expect(!PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-400), now: now, interval: 600, idle: true))
        #expect(PollingPolicy.isDue(lastRefresh: now.addingTimeInterval(-600), now: now, interval: 600, idle: true))
    }
}
