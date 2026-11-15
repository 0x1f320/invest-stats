import SwiftUI

/// A market's current session, such as `● 정규장 · 15:30까지`, redrawn as time passes.
/// Shows nothing until the market's calendar has loaded.
struct MarketStatusLine: View {
    let region: MarketRegion
    let calendar: MarketCalendar?
    /// Prefixes the market's name, for popovers that cover more than one market.
    var showsRegion = false

    var body: some View {
        if let calendar {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let status = calendar.status(at: context.date)
                HStack(spacing: 5) {
                    Circle().fill(Self.color(status)).frame(width: 6, height: 6)
                    if showsRegion {
                        Text(region.title).foregroundStyle(.secondary)
                    }
                    Text(MarketStatusText.describe(status))
                        .foregroundStyle(status.isOpen ? .primary : .secondary)
                }
                .font(.caption.monospacedDigit())
                .lineLimit(1)
            }
        }
    }

    /// Green in the regular session, orange in the extended ones, gray when closed.
    private static func color(_ status: MarketStatus) -> Color {
        switch status {
        case .open(let session): return session.kind == .regular ? .green : .orange
        case .closed: return .secondary.opacity(0.6)
        }
    }
}
