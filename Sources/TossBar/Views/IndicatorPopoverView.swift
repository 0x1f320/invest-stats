import Charts
import SwiftUI

/// Popover for an indicator item: the current value, its change, a chart and the day's candle,
/// or for the exchange rate, which has no candles, the rates the API reports.
struct IndicatorPopoverView: View {
    let itemID: UUID
    let env: AppEnvironment
    @ObservedObject private var data: MarketDataService
    @ObservedObject private var store: ItemStore

    /// The chosen range is remembered per item, like a stock item's.
    @AppStorage private var rangeRaw: String
    @State private var candles: [MarketIndicatorCandle] = []
    @State private var isLoading = false
    @State private var chartError: String?
    @State private var selectedDate: Date?

    init(itemID: UUID, env: AppEnvironment, data: MarketDataService) {
        self.itemID = itemID
        self.env = env
        self.data = data
        self.store = env.store
        _rangeRaw = AppStorage(wrappedValue: ChartRange.day.rawValue, "chartRange.\(itemID.uuidString)")
    }

    private var config: IndicatorItemConfig? { store.indicatorConfig(itemID) }

    private var indicator: MarketIndicator? { config?.indicator }

    /// The saved range, or the indicator's first range when it can't chart the saved one.
    private var range: ChartRange {
        let saved = ChartRange(rawValue: rangeRaw) ?? .day
        return indicator.map { IndicatorChart.range(saved, for: $0) } ?? saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config, let indicator = config.indicator {
                header(indicator)
                if indicator.hasCandles {
                    Picker("", selection: Binding(get: { range.rawValue }, set: { rangeRaw = $0 })) {
                        ForEach(IndicatorChart.ranges(for: indicator)) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    chartSection(indicator)
                    dailyStats(indicator)
                } else {
                    exchangeRateStats()
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
        .task(id: "\(indicator?.symbol ?? "")|\(range.rawValue)") {
            guard let indicator, indicator.hasCandles else { return }
            selectedDate = nil
            // Keep the chart fresh while the popover is open.
            while !Task.isCancelled {
                await loadChart(indicator)
                let wait: Double = range == .day ? 30 : 300
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
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
            if let selected = selectedPoint {
                // Hovering the chart: the value at that point.
                Text(indicator.format(Decimal(selected.value)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                Text(selected.date, format: range == .day
                     ? .dateTime.hour().minute()
                     : .dateTime.year().month().day())
                    .font(.callout).foregroundStyle(.secondary)
            } else if let reading = data.indicatorReading(indicator) {
                Text(reading.formattedValue + (indicator.category == .exchangeRate ? "원" : ""))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                HStack(spacing: 6) {
                    changeLine(reading)
                    if range != .day, indicator.hasCandles, let periodChange {
                        // A yield's change is in percentage points, like its daily change.
                        let text = indicator.category == .bond
                            ? indicator.formatChange(periodChange.amount)
                            : Fmt.percent(ratio: periodChange.rate)
                        Text("·").foregroundStyle(.secondary)
                        Text("\(range.title) \(text)")
                            .foregroundStyle(Trend(periodChange.amount).color)
                    }
                }
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

    // MARK: Chart

    private var points: [ChartPoint] {
        candles.map { ChartPoint(date: $0.timestamp, value: $0.closePrice.double) }
    }

    /// Dashed reference line: the previous close on 1D, the first close otherwise.
    private var baseline: Double? {
        guard let indicator else { return nil }
        if range == .day {
            return data.indicatorReading(indicator)?.previousClose?.double ?? candles.first?.openPrice.double
        }
        return candles.first?.closePrice.double
    }

    /// The change over the charted range, and as a ratio of its first close.
    private var periodChange: (amount: Decimal, rate: Decimal)? {
        guard let first = candles.first?.closePrice.value, first != 0,
              let last = candles.last?.closePrice.value else { return nil }
        return (last - first, (last - first) / first)
    }

    private var selectedPoint: ChartPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    @ViewBuilder
    private func chartSection(_ indicator: MarketIndicator) -> some View {
        let pts = points
        ZStack {
            if pts.count >= 2 {
                let values = pts.map(\.value) + (baseline.map { [$0] } ?? [])
                let lo = values.min()!, hi = values.max()!
                let pad = max((hi - lo) * 0.08, abs(hi) * 0.001)
                let lower = lo - pad, upper = hi + pad
                let color = Trend(Decimal(pts.last!.value - (baseline ?? pts.first!.value))).color

                Chart {
                    ForEach(pts) { point in
                        AreaMark(
                            x: .value("시간", point.date),
                            yStart: .value("하한", lower),
                            yEnd: .value("값", point.value)
                        )
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)

                        LineMark(x: .value("시간", point.date), y: .value("값", point.value))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                    if let baseline {
                        RuleMark(y: .value("기준", baseline))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }
                    if let selected = selectedPoint {
                        RuleMark(x: .value("선택", selected.date))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(x: .value("선택", selected.date), y: .value("값", selected.value))
                            .foregroundStyle(color)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: lower...upper)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(range == .day ? Fmt.hourMinute.string(from: date) : Fmt.monthDay.string(from: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(indicator.format(Decimal(v)))
                            }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text(chartError ?? "차트 데이터가 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if isLoading && pts.count >= 2 {
                VStack { HStack { Spacer(); ProgressView().controlSize(.small) }; Spacer() }
            }
        }
        .frame(height: 180)
    }

    private func loadChart(_ indicator: MarketIndicator) async {
        isLoading = true
        defer { isLoading = false }
        do {
            candles = try await data.indicatorChartCandles(indicator, range: range)
            chartError = nil
        } catch {
            // Keep showing the last chart if a refresh fails.
            if candles.isEmpty { chartError = error.localizedDescription }
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
