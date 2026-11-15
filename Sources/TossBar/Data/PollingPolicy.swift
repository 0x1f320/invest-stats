import Foundation

/// When to refresh a connection. While every market its items follow is closed, prices
/// and holdings don't move, so the polling loop waits `idleInterval` between refreshes
/// instead of the refresh interval, and returns to it as soon as a market opens.
enum PollingPolicy {
    /// The wait between refreshes while every market is closed, unless the refresh
    /// interval is longer.
    static let idleInterval: TimeInterval = 300

    /// Whether every market the items follow is closed with a known next session.
    ///
    /// - Parameter itemRegions: the markets of each item, nil while an item's market
    ///   isn't known yet.
    /// - Parameter status: the current status of a market, nil without a calendar.
    ///
    /// Anything unknown counts as open: an item whose market isn't known yet, a market
    /// without a calendar, or one whose calendar doesn't reach the next session. So a
    /// missing or failing calendar never slows polling down.
    static func isIdle(itemRegions: [Set<MarketRegion>?], status: (MarketRegion) -> MarketStatus?) -> Bool {
        guard !itemRegions.isEmpty else { return false }
        var regions = Set<MarketRegion>()
        for item in itemRegions {
            guard let item else { return false }
            regions.formUnion(item)
        }
        return regions.allSatisfy { region in
            if case .closed(.some) = status(region) { return true }
            return false
        }
    }

    /// Whether a refresh is due, given when the last one started.
    static func isDue(lastRefresh: Date?, now: Date, interval: TimeInterval, idle: Bool) -> Bool {
        guard let lastRefresh else { return true }
        let wait = idle ? max(interval, idleInterval) : interval
        // A little slack, so a loop that ticks every `interval` doesn't miss a tick to
        // timer jitter.
        return now.timeIntervalSince(lastRefresh) >= wait - 0.5
    }
}
