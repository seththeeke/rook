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
        .rookListStyle()
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
                        .foregroundStyle(Theme.textSecondary)
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
                                .foregroundStyle(exercise.skipped ? Theme.textTertiary : Theme.textPrimary)
                                .strikethrough(exercise.skipped)
                            Spacer()
                            Text(WorkoutPresentation.detail(for: exercise, fallbackUnit: unit))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
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
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
    }
}
