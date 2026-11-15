import SwiftUI

/// Popover for an indicator item: the current value, its change and the day's candle, or for
/// the exchange rate, the rates the API reports.
struct IndicatorPopoverView: View {
    let itemID: UUID
    let env: AppEnvironment
    @ObservedObject private var data: MarketDataService
    @ObservedObject private var store: ItemStore

    init(itemID: UUID, env: AppEnvironment, data: MarketDataService) {
        self.itemID = itemID
        self.env = env
        self.data = data
        self.store = env.store
    }

    private var config: IndicatorItemConfig? { store.indicatorConfig(itemID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config, let indicator = config.indicator {
                header(indicator)
                if indicator.category == .exchangeRate {
                    exchangeRateStats()
                } else {
                    dailyStats(indicator)
                }
            } else if let config {
                Text("지원하지 않는 지표입니다: \(config.symbol)").foregroundStyle(.secondary)
            } else {
                Text("삭제된 항목입니다.").foregroundStyle(.secondary)
            }
            Divider()
            PopoverFooter(itemID: itemID, env: env, data: data)
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ indicator: MarketIndicator) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(indicator.category == .exchangeRate ? "\(indicator.name) 환율" : indicator.name)
                    .font(.headline).lineLimit(1)
                Spacer()
                Text("\(indicator.category.title) · \(indicator.displaySymbol)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if indicator.category != .exchangeRate {
                MarketStatusLine(region: .kr, calendar: data.calendars[.kr])
            }
            if let reading = data.indicatorReading(indicator) {
                Text(reading.formattedValue + (indicator.category == .exchangeRate ? "원" : ""))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                changeLine(reading)
                    .font(.callout.monospacedDigit())
            } else {
                Text(data.indicatorErrors[indicator.symbol] ?? data.errorMessage ?? "불러오는 중…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func changeLine(_ reading: IndicatorReading) -> some View {
        if reading.hasChange {
            if let change = reading.formattedChange, let trend = reading.trend {
                HStack(spacing: 6) {
                    Text("\(trend.arrow) \(change)" + (reading.formattedChangeRate.map { " (\($0))" } ?? ""))
                        .foregroundStyle(trend.color)
                    Text("전일 대비").foregroundStyle(.secondary)
                }
            }
        } else if let trend = reading.trend {
            // The exchange rate API reports a direction but no previous value.
            HStack(spacing: 6) {
                Text(trend.arrow).foregroundStyle(trend.color)
                Text(trend == .up ? "상승" : trend == .down ? "하락" : "보합").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Stats

    @ViewBuilder
    private func dailyStats(_ indicator: MarketIndicator) -> some View {
        let candles = data.indicatorDaily[indicator.symbol]?.candles ?? []
        if let latest = candles.first {
            let previousClose = data.indicatorReading(indicator)?.previousClose
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    StatCell(title: "시가", value: indicator.format(latest.openPrice.value))
                    StatCell(title: "고가", value: indicator.format(latest.highPrice.value), valueColor: Trend.up.color)
                    StatCell(title: "저가", value: indicator.format(latest.lowPrice.value), valueColor: Trend.down.color)
                }
                GridRow {
                    StatCell(title: "전일 종가", value: previousClose.map(indicator.format) ?? "–")
                    if indicator.category == .index, let volume = latest.volume?.value {
                        StatCell(title: "거래량", value: Fmt.compact(volume))
                    } else {
                        StatCell(title: " ", value: " ")
                    }
                    StatCell(title: "기준일", value: latest.timestamp.formatted(.dateTime.month(.defaultDigits).day()))
                }
            }
        }
    }

    @ViewBuilder
    private func exchangeRateStats() -> some View {
        if let rate = data.usdKrw {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    StatCell(title: "매수 환율", value: Fmt.number(rate.rate.value, fraction: 2))
                    StatCell(title: "매매기준율 대비", value: rate.basisPoint.map { Fmt.number($0.value, fraction: 1, signed: true) + "bp" } ?? "–")
                    StatCell(title: "기준 시각", value: rate.validFrom.map { Fmt.hourMinute.string(from: $0) } ?? "–")
                }
            }
            Text("해외 주식의 원화 환산에도 이 매매기준율을 씁니다. 환율은 1분마다 갱신되며, API 가 이전 값을 제공하지 않아 등락폭 대신 등락 방향만 표시합니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
