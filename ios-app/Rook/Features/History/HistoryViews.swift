import RookFeatures
import RookFormatting
import RookModels
import SwiftUI

/// Paginated list of completed workouts. In picker mode, tapping a row calls `onPick` instead of
/// opening the detail screen (used by "Choose from past workout").
struct HistoryView: View {
    @State private var model: HistoryModel
    let unit: WeightUnit
    var onPick: ((WorkoutInstance) -> Void)?

    init(model: HistoryModel, unit: WeightUnit, onPick: ((WorkoutInstance) -> Void)? = nil) {
        _model = State(initialValue: model)
        self.unit = unit
        self.onPick = onPick
    }

    var body: some View {
        Group {
            if !model.hasLoaded && model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.workouts.isEmpty {
                ErrorStateView(message: error) { Task { await model.retry() } }
            } else if model.hasLoaded && model.workouts.isEmpty {
                EmptyStateView(systemImage: "clock", title: "No completed workouts", message: "Workouts you finish will show up here.")
            } else {
                list
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(onPick == nil ? "History" : "Choose a workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadFirstPage() }
    }

    private var list: some View {
        List {
            ForEach(model.workouts) { workout in
                row(for: workout)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .task { await model.loadMoreIfNeeded(currentId: workout.id) }
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = model.errorMessage {
                Button("Couldn't load more. Tap to retry.") { Task { await model.retry() } }
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .listRowBackground(Color.clear)
                    .accessibilityHint(error)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("history.list")
    }

    @ViewBuilder
    private func row(for workout: WorkoutInstance) -> some View {
        if let onPick {
            Button { onPick(workout) } label: { WorkoutRow(workout: workout, unit: unit) }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: AppRoute.workoutDetail(workout)) { WorkoutRow(workout: workout, unit: unit) }
        }
    }
}

/// A completed workout's details.
struct WorkoutDetailView: View {
    let workout: WorkoutInstance
    let unit: WeightUnit
    var onRedo: ((WorkoutInstance) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((workout.completedAt ?? workout.startedAt).formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let gym = workout.gymName {
                        Label(gym, systemImage: "mappin.and.ellipse").font(.subheadline)
                    }
                }
                HStack(spacing: Theme.Spacing.s) {
                    metric("\(WorkoutPresentation.minutes(for: workout))", "minutes")
                    metric("\(workout.exercises.filter { !$0.skipped }.count)", "exercises")
                    metric(RookFormat.compactVolume(WorkoutPresentation.volume(for: workout)), "\(unit.label) volume")
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workout.orderedExercises.enumerated()), id: \.offset) { index, exercise in
                        HStack {
                            Text(exercise.exerciseName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(exercise.skipped ? .secondary : .primary)
                                .strikethrough(exercise.skipped)
                            Spacer()
                            Text(WorkoutPresentation.detail(for: exercise, fallbackUnit: unit))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        if index < workout.exercises.count - 1 { Divider() }
                    }
                }
                .rookCard()
                if let notes = workout.notes, !notes.isEmpty {
                    Text(notes).rookCard()
                }
                if let onRedo {
                    Button("Do this workout again") { onRedo(workout) }
                        .buttonStyle(.rookSecondary)
                        .padding(.top, Theme.Spacing.s)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(WorkoutPresentation.title(for: workout))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rookNumber(22))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Month calendar of workout days.
struct CalendarSheet: View {
    @State private var model: CalendarModel
    let unit: WeightUnit
    @Environment(\.dismiss) private var dismiss

    init(model: CalendarModel, unit: WeightUnit) {
        _model = State(initialValue: model)
        self.unit = unit
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    HStack {
                        Button { Task { await model.showPreviousMonth() } } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous month")
                        Spacer()
                        Text(model.title).font(.headline)
                        Spacer()
                        Button { model.showNextMonth() } label: { Image(systemName: "chevron.right") }
                            .disabled(!model.canGoForward)
                            .accessibilityLabel("Next month")
                    }
                    .padding(.horizontal, Theme.Spacing.s)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                            Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(model.grid.enumerated()), id: \.offset) { _, day in
                            if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                        }
                    }

                    if model.isLoading { ProgressView() }
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger)
                    }

                    if model.selectedDay != nil {
                        if model.workoutsOnSelectedDay.isEmpty {
                            Text("No workouts this day.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(model.workoutsOnSelectedDay) { workout in
                                NavigationLink(value: workout) { WorkoutRow(workout: workout, unit: unit) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: WorkoutInstance.self) { WorkoutDetailView(workout: $0, unit: unit) }
        }
        .task { await model.loadWorkoutsForVisibleMonth() }
    }

    private func dayCell(_ day: CalendarModel.Day) -> some View {
        let selected = model.selectedDay == day.key
        return Button { model.selectedDay = day.key } label: {
            Text("\(day.dayNumber)")
                .font(.subheadline.weight(day.isToday ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(day.hasWorkout ? .white : (day.isFuture ? .secondary : .primary))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(day.hasWorkout ? Theme.primary : (day.isToday ? Theme.primary.opacity(0.15) : .clear))
                )
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accentOrange : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))\(day.hasWorkout ? ", workout completed" : "")")
    }
}
