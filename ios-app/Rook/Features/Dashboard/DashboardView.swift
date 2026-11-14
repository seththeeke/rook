import RookFeatures
import RookFormatting
import RookModels
import SwiftUI

/// Home screen: streak, stats, PRs, this week, recent workouts.
struct DashboardView: View {
    let model: DashboardModel
    let profile: UserProfile
    /// Slot above the cards (the "workout in progress" banner).
    var activeWorkoutBanner: AnyView?
    /// nil hides the "New workout" button and empty-state action.
    var onNewWorkout: (() -> Void)?
    @State private var showingCalendar = false
    @Environment(\.scenePhase) private var scenePhase
    let makeCalendar: () -> CalendarModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    content
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.top, -Theme.Spacing.m)
                        .padding(.bottom, 100)
                }
            }
            .refreshable { await model.load() }
            .background(Theme.background)
            .ignoresSafeArea(edges: .top)

            if let onNewWorkout {
            Button(action: onNewWorkout) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.primary, in: Circle())
                    .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
            }
            .padding(Theme.Spacing.l)
            .accessibilityLabel("New workout")
            .accessibilityIdentifier("dashboard.newWorkout")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if model.state != .loaded { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarSheet(model: makeCalendar(), unit: profile.preferredUnit)
        }
    }

    // MARK: - Header

    private var header: some View {
        let summary = ProfileSummary(profile: profile)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(summary.displayName)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                NavigationLink(value: AppRoute.profile) {
                    AvatarView(initials: summary.initials, photoURL: profile.profilePhoto, size: 48)
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2))
                }
                .accessibilityLabel("Profile")
                .accessibilityIdentifier("dashboard.profile")
            }
            if model.state == .loaded {
                StreakCard(current: model.global.currentStreak, best: model.global.longestStreak)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, 64)
        .padding(.bottom, Theme.Spacing.xl)
        .background(Theme.headerGradient)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            DashboardSkeleton()
        case .failed(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
                .rookCard()
        case .loaded:
            VStack(spacing: Theme.Spacing.m) {
                if let banner = activeWorkoutBanner { banner }
                if let error = model.refreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                StatsRow(stats: model.stats, unit: profile.preferredUnit)
                if !model.personalRecords.isEmpty {
                    PersonalRecordsCard(records: model.personalRecords)
                }
                Button { showingCalendar = true } label: {
                    WeekStrip(days: model.currentWeek)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your workout calendar")
                .accessibilityIdentifier("dashboard.week")
                RecentWorkoutsCard(workouts: model.recentWorkouts, unit: profile.preferredUnit, onStart: onNewWorkout)
            }
        }
    }
}

// MARK: - Cards

private struct StreakCard: View {
    let current: Int
    let best: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.accentOrange, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current streak")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text(days(current))
                    .font(.rookNumber(30))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Best").font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(days(best)).font(.headline).foregroundStyle(.white)
            }
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.streak")
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}

private struct StatsRow: View {
    let stats: DashboardModel.Stats
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            tile(icon: "dumbbell.fill", tint: Theme.primary, value: "\(stats.totalWorkouts)", label: "Workouts")
            tile(icon: "bolt.fill", tint: Theme.accentOrange, value: "\(stats.workoutsLast30Days)", label: "Last 30 days")
            tile(
                icon: "chart.bar.fill", tint: Theme.accentGreen,
                value: RookFormat.compactVolume(stats.volumeLast30Days),
                label: "\(unit.label) · \(stats.minutesLast30Days) min"
            )
        }
        .accessibilityIdentifier("dashboard.stats")
    }

    private func tile(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            Text(value)
                .font(.rookNumber(22))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalRecordsCard: View {
    let records: [DashboardModel.PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Personal Records", systemImage: "trophy.fill")
                .font(.headline)
                .labelStyle(TintedIconLabelStyle(tint: .yellow))
            ForEach(records) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.exerciseName).font(.subheadline.weight(.semibold))
                        Text(record.sessions == 1 ? "1 session" : "\(record.sessions) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(RookFormat.weight(record.weight, unit: record.unit))
                        .font(.rookNumber(17))
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                if record.id != records.last?.id { Divider() }
            }
        }
        .rookCard()
        .accessibilityIdentifier("dashboard.records")
    }
}

private struct WeekStrip: View {
    let days: [DashboardModel.WeekDay]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("This Week").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(fill(for: day))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if day.hasWorkout {
                                    Image(systemName: "dumbbell.fill").font(.caption).foregroundStyle(.white)
                                }
                            }
                        Text(day.letter)
                            .font(.caption.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? Theme.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: day))
                }
            }
        }
        .rookCard()
    }

    private func fill(for day: DashboardModel.WeekDay) -> Color {
        if day.hasWorkout { return Theme.primary }
        if day.isToday { return Theme.primary.opacity(0.15) }
        return Color.secondary.opacity(0.12)
    }

    private func accessibilityLabel(for day: DashboardModel.WeekDay) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide))
        return "\(name)\(day.isToday ? ", today" : ""), \(day.hasWorkout ? "workout completed" : "no workout")"
    }
}

private struct RecentWorkoutsCard: View {
    let workouts: [WorkoutInstance]
    let unit: WeightUnit
    let onStart: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label("Recent Workouts", systemImage: "clock")
                    .font(.headline)
                    .labelStyle(TintedIconLabelStyle(tint: .secondary))
                Spacer()
                if !workouts.isEmpty {
                    NavigationLink(value: AppRoute.history) {
                        HStack(spacing: 2) {
                            Text("See All")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("dashboard.seeAll")
                }
            }
            if workouts.isEmpty {
                EmptyStateView(
                    systemImage: "dumbbell",
                    title: "No workouts yet",
                    message: "Build your first workout to start tracking progress.",
                    actionTitle: onStart == nil ? nil : "Start a workout",
                    action: onStart
                )
            } else {
                ForEach(workouts) { workout in
                    NavigationLink(value: AppRoute.workoutDetail(workout)) {
                        WorkoutRow(workout: workout, unit: unit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .rookCard()
        .accessibilityIdentifier("dashboard.recent")
    }
}

/// One completed workout in a list.
struct WorkoutRow: View {
    let workout: WorkoutInstance
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40)
                .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutPresentation.title(for: workout))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(workout.exercises.count) exercises · \(WorkoutPresentation.minutes(for: workout)) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(RookFormat.relativeDay(workout.completedAt ?? workout.startedAt))
                    .font(.subheadline.weight(.medium))
                Text("\(RookFormat.compactVolume(WorkoutPresentation.volume(for: workout))) \(unit.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Label whose icon is tinted independently of its title.
struct TintedIconLabelStyle: LabelStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

private struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(0..<3, id: \.self) { _ in placeholder(height: 104) }
            }
            placeholder(height: 160)
            placeholder(height: 110)
            placeholder(height: 220)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading")
    }

    private func placeholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Color.secondary.opacity(0.15))
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}
