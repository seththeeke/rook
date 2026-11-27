import Charts
import RookFeatures
import RookFormatting
import RookModels
import SwiftUI

/// One exercise's progression over time, with 30 Days / 90 Days / YTD / All Time filters.
///
/// The chart always plots every session and animates its X and Y domains when the filter changes, so
/// switching ranges zooms the line rather than redrawing it. The Y axis fits the sessions in view.
struct ExerciseTrendView: View {
    @State private var model: ExerciseTrendModel
    @State private var selectedDate: Date?

    init(model: ExerciseTrendModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                content
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 320)
                .rookCard()
        case .failed(let message):
            ErrorStateView(message: message) { Task { await model.retry() } }
                .rookCard()
        case .loaded where model.sessions.isEmpty:
            EmptyStateView(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "No history yet",
                message: "Complete a workout with this exercise to start its trend."
            )
            .rookCard()
        case .loaded:
            chartCard
            statsRow
            historyCard
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            headline
            Picker("Range", selection: $model.range.animation(.smooth(duration: 0.55))) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("trend.range")
            .onChange(of: model.range) { selectedDate = nil }
            chart
        }
        .rookCard()
    }

    private var selectedPoint: TrendPoint? {
        guard let selectedDate else { return nil }
        return model.visiblePoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var headline: some View {
        let metric = model.metric
        let shown = selectedPoint ?? model.latest
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedPoint == nil ? "Latest" : (selectedPoint?.date.formatted(.dateTime.month(.abbreviated).day().year()) ?? ""))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(shown.map { metric.format($0.value) } ?? "—")
                    .font(.rookNumber(30))
                    .contentTransition(.numericText())
            }
            Spacer()
            changeBadge
        }
        .animation(.smooth, value: shown?.value)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var changeBadge: some View {
        if let change = model.change {
            let tint: Color = switch change.direction {
            case .up: Theme.accentGreen
            case .down: Theme.danger
            case .flat: Theme.textSecondary
            }
            let icon = switch change.direction {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .flat: "arrow.right"
            }
            Label(change.label(metric: model.metric), systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.14), in: Capsule())
                .contentTransition(.numericText())
                .accessibilityLabel("Change \(model.range.phrase): \(change.label(metric: model.metric))")
        }
    }

    private var chart: some View {
        let points = model.allPoints
        let yDomain = model.yDomain
        let dense = model.visiblePoints.count > 30
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", yDomain.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary.opacity(0.35), Theme.primary.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.primaryLight)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbolSize(dense ? 0 : 30)
                    .foregroundStyle(Theme.primaryLight)
            }
            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .symbolSize(90)
                    .foregroundStyle(.white)
            }
        }
        .chartXScale(domain: model.xDomain)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(RookFormat.weight((number * 10).rounded() / 10))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .overlay {
            if model.visiblePoints.isEmpty {
                Text("No sessions \(model.range.phrase)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(10)
                    .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
            }
        }
        .frame(height: 230)
        .accessibilityIdentifier("trend.chart")
    }

    // MARK: - Stats and history

    private var statsRow: some View {
        let metric = model.metric
        return HStack(spacing: Theme.Spacing.s) {
            stat(model.best.map(metric.format) ?? "—", "Best")
            stat("\(model.visiblePoints.count)", model.visiblePoints.count == 1 ? "Session" : "Sessions")
            stat(model.visiblePoints.first.map { metric.format($0.value) } ?? "—", "Start")
        }
        .animation(.smooth, value: model.range)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.rookNumber(18))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var historyCard: some View {
        let sessions = model.visibleSessions
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sessions").font(.headline).padding(.bottom, Theme.Spacing.s)
                LazyVStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        HStack {
                            Text(session.completedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.subheadline)
                            Spacer()
                            Text(detail(session))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        if index < sessions.count - 1 { Divider() }
                    }
                }
            }
            .rookCard()
        }
    }

    private func detail(_ session: ExerciseSession) -> String {
        let exercise = WorkoutExercise(
            exerciseId: model.exerciseId, exerciseName: model.exerciseName, modality: session.modality ?? .setsReps,
            sets: session.sets, reps: session.reps, durationSeconds: session.durationSeconds,
            weight: session.weight, weightUnit: session.weightUnit
        )
        return WorkoutPresentation.detail(for: exercise, fallbackUnit: model.unit)
    }
}
