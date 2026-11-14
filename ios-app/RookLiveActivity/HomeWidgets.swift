@preconcurrency import CoreMotion
import RookWidgetData
import SwiftUI
import WidgetKit

// Home-screen widgets. They read the dashboard snapshot the app writes to the App Group container
// (the extension has no session, so it never calls the API), and read today's steps from the pedometer
// themselves when Motion & Fitness access allows, falling back to the app's last count.

// MARK: - Timeline

struct DashboardEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
}

struct DashboardProvider: TimelineProvider {
    /// Steps change constantly; WidgetKit's budget allows roughly this cadence.
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: Date(), summary: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DashboardEntry) -> Void) {
        if context.isPreview {
            completion(DashboardEntry(date: Date(), summary: .sample()))
            return
        }
        Task { completion(await Self.currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DashboardEntry>) -> Void) {
        Task {
            let entry = await Self.currentEntry()
            // Refresh periodically for steps, and right after midnight so the week and steps roll over.
            let calendar = Calendar.current
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date)) ?? entry.date
            let next = min(entry.date.addingTimeInterval(Self.refreshInterval), midnight.addingTimeInterval(60))
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    static func currentEntry() async -> DashboardEntry {
        let now = Date()
        let steps = await PedometerReader.stepsToday(now: now)
        let summary = WidgetSummary(snapshot: DashboardSnapshotStore.shared.load(), now: now, liveSteps: steps)
        return DashboardEntry(date: now, summary: summary)
    }
}

/// Today's steps straight from CoreMotion, only when access was already granted in the app
/// (an extension can't show the permission prompt). nil means "use the app's last value".
enum PedometerReader {
    static func stepsToday(now: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized else { return nil }
        let pedometer = CMPedometer()
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: Calendar.current.startOfDay(for: now), to: now) { data, error in
                continuation.resume(returning: error == nil ? data?.numberOfSteps.intValue : nil)
            }
        }
    }
}

// MARK: - Widgets

/// 1. Large: workouts, saunas and steps, plus the week.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RookOverviewWidget", provider: DashboardProvider()) { entry in
            OverviewWidgetView(summary: entry.summary).widgetBackground()
        }
        .configurationDisplayName("Overview")
        .description("Workouts and sauna sessions in the last 30 days, today's steps, and your week.")
        .supportedFamilies([.systemLarge])
    }
}

/// 2. Small: today's steps.
struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RookStepsWidget", provider: DashboardProvider()) { entry in
            StepsWidgetView(summary: entry.summary).widgetBackground()
        }
        .configurationDisplayName("Steps")
        .description("Today's step count.")
        .supportedFamilies([.systemSmall])
    }
}

/// 3. Medium: this week.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RookWeekWidget", provider: DashboardProvider()) { entry in
            WeekWidgetView(summary: entry.summary).widgetBackground()
        }
        .configurationDisplayName("This Week")
        .description("Which days you trained or used the sauna this week.")
        .supportedFamilies([.systemMedium])
    }
}

/// 4. Medium: the three numbers in one row.
struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RookStatsWidget", provider: DashboardProvider()) { entry in
            StatsWidgetView(summary: entry.summary).widgetBackground()
        }
        .configurationDisplayName("Stats")
        .description("Workouts and sauna sessions in the last 30 days, and today's steps.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Views

private enum WidgetColors {
    static let background = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x18 / 255)
    static let surface = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2F / 255)
    static let primary = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFA / 255)
    static let primaryLight = Brand.accent
    static let orange = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x3D / 255)
    static let green = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
    static let secondaryText = Brand.secondaryText
}

private extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { WidgetColors.background }
    }
}

private enum Metric {
    case workouts, saunas, steps

    var icon: String {
        switch self {
        case .workouts: "dumbbell.fill"
        case .saunas: "flame.fill"
        case .steps: "figure.walk"
        }
    }

    var tint: Color {
        switch self {
        case .workouts: WidgetColors.primaryLight
        case .saunas: WidgetColors.orange
        case .steps: WidgetColors.green
        }
    }

    var label: String {
        switch self {
        case .workouts: "Workouts · 30d"
        case .saunas: "Saunas · 30d"
        case .steps: "Steps today"
        }
    }

    func value(in summary: WidgetSummary) -> String {
        let number: Int? = switch self {
        case .workouts: summary.workoutsLast30Days
        case .saunas: summary.saunaSessionsLast30Days
        case .steps: summary.steps
        }
        return number?.formatted() ?? "—"
    }

    func accessibilityLabel(in summary: WidgetSummary) -> String {
        "\(label.replacingOccurrences(of: " · 30d", with: ", last 30 days")): \(value(in: summary))"
    }
}

/// Icon, big number, caption.
private struct MetricView: View {
    let metric: Metric
    let summary: WidgetSummary
    var valueSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: metric.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(metric.tint)
            Text(metric.value(in: summary))
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(metric.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel(in: summary))
    }
}

private struct WeekStripView: View {
    let days: [WidgetSummary.Day]
    var circle: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(fill(day))
                        Circle().strokeBorder(
                            day.isToday && day.activity == .none ? WidgetColors.primary : .white.opacity(0.07),
                            lineWidth: day.isToday ? 1.5 : 1
                        )
                        if let icon = icon(day.activity) {
                            Image(systemName: icon)
                                .font(.system(size: circle * 0.38, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: circle, height: circle)
                    Text(day.letter)
                        .font(.caption2.weight(day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? WidgetColors.primaryLight : WidgetColors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(day))
            }
        }
    }

    private func icon(_ activity: DayActivity) -> String? {
        switch activity {
        case .none: nil
        case .workout: "dumbbell.fill"
        case .sauna: "flame.fill"
        case .multiple: "checkmark"
        }
    }

    private func fill(_ day: WidgetSummary.Day) -> Color {
        switch day.activity {
        case .sauna: WidgetColors.orange
        case .workout, .multiple: WidgetColors.primary
        case .none: day.isToday ? WidgetColors.primary.opacity(0.12) : WidgetColors.surface
        }
    }

    private func accessibilityLabel(_ day: WidgetSummary.Day) -> String {
        let status = switch day.activity {
        case .none: "no workout"
        case .workout: "workout"
        case .sauna: "sauna session"
        case .multiple: "multiple sessions"
        }
        return "\(day.letter)\(day.isToday ? ", today" : ""), \(status)"
    }
}

private struct SignInPrompt: View {
    var body: some View {
        Text("Open Rook to see your stats")
            .font(.caption)
            .foregroundStyle(WidgetColors.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

private struct WidgetTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
    }
}

struct OverviewWidgetView: View {
    let summary: WidgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WidgetTitle(text: "Rook")
                Spacer()
                Text("Last 30 days")
                    .font(.caption2)
                    .foregroundStyle(WidgetColors.secondaryText)
            }
            if summary.hasData {
                HStack(spacing: 8) {
                    ForEach([Metric.workouts, .saunas, .steps], id: \.self) { metric in
                        MetricView(metric: metric, summary: summary, valueSize: 30)
                            .padding(12)
                            .background(WidgetColors.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Spacer(minLength: 0)
                WidgetTitle(text: "This Week")
                WeekStripView(days: summary.week, circle: 34)
            } else {
                SignInPrompt()
            }
        }
    }
}

struct StepsWidgetView: View {
    let summary: WidgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WidgetColors.green)
            Spacer(minLength: 0)
            Text(summary.steps?.formatted() ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text("Steps today")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Metric.steps.accessibilityLabel(in: summary))
    }
}

struct WeekWidgetView: View {
    let summary: WidgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetTitle(text: "This Week")
            Spacer(minLength: 0)
            WeekStripView(days: summary.week, circle: 36)
            Spacer(minLength: 0)
        }
    }
}

struct StatsWidgetView: View {
    let summary: WidgetSummary

    var body: some View {
        if summary.hasData {
            HStack(spacing: 12) {
                ForEach([Metric.workouts, .saunas, .steps], id: \.self) { metric in
                    MetricView(metric: metric, summary: summary, valueSize: 30)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            SignInPrompt()
        }
    }
}

#Preview("Overview", as: .systemLarge) {
    OverviewWidget()
} timeline: {
    DashboardEntry(date: .now, summary: .sample())
}

#Preview("Steps", as: .systemSmall) {
    StepsWidget()
} timeline: {
    DashboardEntry(date: .now, summary: .sample())
}

#Preview("Week", as: .systemMedium) {
    WeekWidget()
} timeline: {
    DashboardEntry(date: .now, summary: .sample())
}

#Preview("Stats", as: .systemMedium) {
    StatsWidget()
} timeline: {
    DashboardEntry(date: .now, summary: .sample())
}
