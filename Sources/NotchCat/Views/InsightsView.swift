import SwiftUI

/// "Momentum is building" summary on the left, a 7-day stacked bar chart on the right.
struct InsightsView: View {
    @ObservedObject var store: TaskStore
    @StateObject private var model = InsightsModel()
    @StateObject private var history = HistoryModel()

    enum Metric: String, CaseIterable, Identifiable {
        case tasks = "Tasks", focus = "Focus", history = "History"
        var id: String { rawValue }
    }

    // NOTCHCAT_METRIC is a test-only way to open on a segment without clicking.
    @State private var metric: Metric = Metric(rawValue: ProcessInfo.processInfo.environment["NOTCHCAT_METRIC"] ?? "") ?? .tasks
    @State private var selected: Date?

    var body: some View {
        HStack(spacing: 10) {
            summaryCard
                .frame(width: 270)
            chartCard
        }
        .onAppear { model.reload(); history.reload() }
        .onReceive(store.$tasks) { _ in model.reload(); history.reload() }
    }

    // MARK: - Left: summary

    private var summaryCard: some View {
        let s = model.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                Text("This week").font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .opacity(0.75)

            Text(model.headline)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.sentence)
                .font(.system(size: 12.5, weight: .medium))
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(s.completed)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tasks completed").font(.system(size: 12, weight: .semibold))
                    Text("of \(s.planned) planned").font(.system(size: 11.5, weight: .medium)).opacity(0.6)
                }
            }

            HStack(spacing: 8) {
                statChip("Focus time", InsightsModel.duration(s.focusSeconds))
                statChip("Active days", "\(s.activeDays)/7")
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card(Theme.mint)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10.5, weight: .medium)).opacity(0.6)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.35)))
    }

    // MARK: - Right: chart

    private var chartCard: some View {
        let days = model.summary.days
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(Metric.allCases) { m in
                        Button { metric = m } label: {
                            Text(m.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 11).padding(.vertical, 4)
                                .background(Capsule().fill(metric == m ? Theme.ink : .clear))
                                .foregroundStyle(metric == m ? Color.white : Theme.ink.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Capsule().fill(Theme.ink.opacity(0.08)))

                Spacer()

                if metric == .history {
                    HistorySearchField(text: $history.search)
                } else {
                    HStack(spacing: 6) {
                        weekButton("chevron.left") { model.weekOffset -= 1; selected = nil }
                        Text(rangeLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        weekButton("chevron.right", disabled: model.weekOffset == 0) { model.weekOffset += 1; selected = nil }
                    }
                }
            }

            if metric == .history {
                HistoryList(model: history, store: store)
                    .frame(maxHeight: .infinity)
            } else {
                InsightsChart(days: days, metric: metric, selected: $selected)
                    .frame(maxHeight: .infinity)

                Text(detailText)
                    .font(.system(size: 11.5, weight: .medium))
                    .opacity(selected == nil ? 0.5 : 0.85)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(Theme.lavender)
    }

    private func weekButton(_ symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.ink.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.3 : 1)
        .disabled(disabled)
    }

    private var rangeLabel: String {
        guard let a = model.summary.rangeStart, let b = model.summary.rangeEnd else { return "" }
        let f = Date.FormatStyle().day().month(.abbreviated)
        return "\(a.formatted(f)) – \(b.formatted(f))"
    }

    private var detailText: String {
        guard let sel = selected, let d = model.summary.days.first(where: { $0.date == sel }) else { return "Select a day" }
        let day = d.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        switch metric {
        case .tasks: return "\(day): \(d.completed) done of \(d.planned) planned"
        case .focus: return "\(day): \(InsightsModel.duration(d.focusSeconds)) focused"
        case .history: return ""
        }
    }
}

// MARK: - Chart

private struct InsightsChart: View {
    let days: [InsightsModel.Day]
    let metric: InsightsView.Metric
    @Binding var selected: Date?

    private let axisWidth: CGFloat = 34
    private let labelHeight: CGFloat = 30

    /// Values per day: (completed/active, planned/active-extra) in the chart's unit.
    private func values(_ d: InsightsModel.Day) -> (dark: Double, total: Double) {
        switch metric {
        case .tasks: return (Double(d.completed), Double(max(d.planned, d.completed)))
        case .focus, .history:
            let m = Double(d.focusSeconds) / 60
            return (m, m)
        }
    }

    private var axisMax: Double {
        let peak = days.map { values($0).total }.max() ?? 0
        switch metric {
        case .tasks:
            return peak <= 4 ? 4 : (ceil(peak / 4) * 4)
        case .focus, .history:
            return peak <= 60 ? 60 : (ceil(peak / 60) * 60)
        }
    }

    private func axisLabel(_ v: Double) -> String {
        switch metric {
        case .tasks: return "\(Int(v))"
        case .focus, .history:
            if v == 0 { return "0" }
            let m = Int(v)
            return m % 60 == 0 ? "\(m / 60)h" : "\(m)m"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let plotH = max(geo.size.height - labelHeight, 10)
            let max = axisMax
            HStack(alignment: .top, spacing: 6) {
                // Y axis
                ZStack(alignment: .topTrailing) {
                    ForEach(0...4, id: \.self) { i in
                        let v = max * Double(4 - i) / 4
                        Text(axisLabel(v))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .opacity(0.5)
                            .position(x: axisWidth - 12, y: plotH * CGFloat(i) / 4)
                    }
                }
                .frame(width: axisWidth, height: plotH)

                // Plot
                ZStack(alignment: .topLeading) {
                    ForEach(0...4, id: \.self) { i in
                        Rectangle().fill(Theme.ink.opacity(i == 4 ? 0.2 : 0.07))
                            .frame(height: 1)
                            .offset(y: plotH * CGFloat(i) / 4)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(days) { d in column(d, plotH: plotH, max: max) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func column(_ d: InsightsModel.Day, plotH: CGFloat, max: Double) -> some View {
        let v = values(d)
        let darkH = plotH * CGFloat(v.dark / max)
        let totalH = plotH * CGFloat(v.total / max)
        let isSelected = selected == d.date
        let isToday = Calendar.current.isDateInToday(d.date)

        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Color.clear
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if totalH - darkH > 0.5 {
                        Rectangle().fill(Theme.ink.opacity(0.22)).frame(height: totalH - darkH)
                    }
                    if darkH > 0.5 {
                        Rectangle().fill(Theme.ink.opacity(isSelected ? 1 : 0.82)).frame(height: darkH)
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
                .animation(.spring(duration: 0.35, bounce: 0.1), value: totalH)
            }
            .frame(height: plotH)

            VStack(spacing: 0) {
                Text(d.date.formatted(.dateTime.weekday(.abbreviated)))
                Text(d.date.formatted(.dateTime.day()))
            }
            .font(.system(size: 10, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
            .opacity(isSelected || isToday ? 1 : 0.55)
            .frame(height: labelHeight - 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selected = (selected == d.date) ? nil : d.date }
    }
}
