import Foundation

/// Where an alert stands between two observations. Saved across launches, so quitting the
/// app neither fires an alert again nor forgets that it is waiting to re-arm.
struct AlertState: Codable, Hashable {
    enum Phase: String, Codable {
        /// The value is outside the condition; crossing into it fires.
        case armed
        /// The condition was met; the value has to clear it before the alert re-arms.
        case triggered
    }

    /// What the alert compared when this state was made: the item's subject (stock or
    /// account) and the alert's condition. A different signature starts over.
    var signature: String
    var phase: Phase
    var lastFiredAt: Date?
}

/// Decides when an alert fires. Free of UI, network and storage, so it can be tested alone.
///
/// An alert fires when the value crosses into its condition, not while it stays there:
/// - The first observation only sets a baseline. A condition already met when the alert is
///   set up (or after its threshold changes) doesn't fire; the value has to leave it first.
/// - After firing, the alert waits until the value clears the threshold by
///   `PriceAlert.rearmMargin`, then fires again on the next crossing.
/// - `AlertRepeat.oncePerDay` lets at most one crossing per day notify.
enum AlertEvaluator {
    struct Step: Equatable {
        let state: AlertState
        let fires: Bool
    }

    /// The signature for an alert on a subject, such as `stock:005930`.
    static func signature(for alert: PriceAlert, subject: String) -> String {
        let threshold = alert.threshold.map { "\($0)" } ?? "-"
        return "\(subject)|\(alert.metric.rawValue)|\(alert.direction.rawValue)|\(threshold)"
    }

    /// Advances an alert by one observation of its value.
    /// - Parameters:
    ///   - previous: The saved state, or nil for an alert never observed.
    ///   - calendar: Its time zone sets the day boundary of `oncePerDay`.
    static func step(
        _ alert: PriceAlert,
        signature: String,
        value: Decimal,
        previous: AlertState?,
        now: Date,
        calendar: Calendar
    ) -> Step {
        let met = alert.isMet(by: value)
        guard var state = previous, state.signature == signature else {
            return Step(state: AlertState(signature: signature, phase: met ? .triggered : .armed), fires: false)
        }
        switch state.phase {
        case .armed:
            guard met else { return Step(state: state, fires: false) }
            state.phase = .triggered
            if alert.repeatMode == .oncePerDay, let last = state.lastFiredAt,
               calendar.isDate(last, inSameDayAs: now) {
                return Step(state: state, fires: false)
            }
            state.lastFiredAt = now
            return Step(state: state, fires: true)
        case .triggered:
            if alert.hasCleared(value) { state.phase = .armed }
            return Step(state: state, fires: false)
        }
    }
}
