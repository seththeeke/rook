import RookFeatures
import RookModels
import SwiftUI

enum BuilderStep: Hashable {
    case ai, manual, pastWorkout, review
}

/// Full-screen flow: New workout → AI / Manual / Past workout → Review → Start.
struct BuilderFlowView: View {
    @State private var model: BuilderModel
    @State private var path: [BuilderStep] = []
    let makeHistory: () -> HistoryModel
    let onStarted: (WorkoutInstance) async -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: BuilderModel, makeHistory: @escaping () -> HistoryModel, onStarted: @escaping (WorkoutInstance) async -> Void) {
        _model = State(initialValue: model)
        self.makeHistory = makeHistory
        self.onStarted = onStarted
    }

    var body: some View {
        NavigationStack(path: $path) {
            NewWorkoutView(model: model) { path.append($0) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.accessibilityIdentifier("builder.close")
                    }
                }
                .navigationDestination(for: BuilderStep.self) { step in
                    switch step {
                    case .ai:
                        AIWorkoutView(model: model) { path.append(.review) }
                    case .manual:
                        SelectExercisesView(model: model) { path.append(.review) }
                    case .pastWorkout:
                        HistoryView(model: makeHistory(), unit: model.unit) { workout in
                            model.loadPastWorkout(workout)
                            path.append(.review)
                        }
                    case .review:
                        ReviewWorkoutView(model: model, onEditManually: {
                            model.convertToManual()
                            path.append(.manual)
                        }, onStart: start)
                    }
                }
        }
        .task { await model.loadGyms() }
        .interactiveDismissDisabled(model.isStarting || model.isGenerating)
    }

    private func start() {
        Task {
            if let workout = await model.startWorkout() {
                await onStarted(workout)
            }
        }
    }
}

// MARK: - New workout

private struct NewWorkoutView: View {
    let model: BuilderModel
    let go: (BuilderStep) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                GymPicker(model: model)
                Text("How do you want to build it?")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.s)
                OptionCard(
                    icon: "wand.and.stars", title: "Generate with AI",
                    subtitle: "Describe the workout you want", prominent: true
                ) { go(.ai) }
                .accessibilityIdentifier("builder.ai")
                OptionCard(icon: "plus", title: "Build it yourself", subtitle: "Pick exercises from the catalog") {
                    if model.source == .aiGenerated { model.clear() }
                    go(.manual)
                }
                .accessibilityIdentifier("builder.manual")
                OptionCard(icon: "clock.arrow.circlepath", title: "Repeat a past workout", subtitle: "Start from something you've done") {
                    go(.pastWorkout)
                }
                .accessibilityIdentifier("builder.past")
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("New Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(prominent ? .white : Theme.primary)
                    .frame(width: 52, height: 52)
                    .background(prominent ? .white.opacity(0.2) : Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right").opacity(0.6)
            }
            .foregroundStyle(prominent ? .white : .primary)
            .padding(Theme.Spacing.m)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.headerGradient)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surface)
                }
            }
            .shadow(color: (prominent ? Theme.primary : .black).opacity(prominent ? 0.3 : 0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// Gym selector (hidden when the user has no gyms).
private struct GymPicker: View {
    @Bindable var model: BuilderModel

    var body: some View {
        if !model.gyms.isEmpty {
            Menu {
                Picker("Gym", selection: $model.selectedGymId) {
                    ForEach(model.gyms) { gym in Text(gym.name).tag(Optional(gym.gymId)) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(model.selectedGym?.name ?? "Choose gym")
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Gym: \(model.selectedGym?.name ?? "none")")
        }
    }
}

// MARK: - AI

private struct AIWorkoutView: View {
    @Bindable var model: BuilderModel
    let onGenerated: () -> Void
    @FocusState private var promptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                GymPicker(model: model)
                Text("Describe your workout")
                    .font(.title2.bold())
                TextField("e.g. Upper body, 45 minutes, focus on chest", text: $model.prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(Theme.Spacing.m)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .focused($promptFocused)
                    .disabled(model.isGenerating)
                    .accessibilityIdentifier("ai.prompt")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(BuilderModel.quickPrompts, id: \.self) { chip in
                            Button(chip) { model.appendQuickPrompt(chip) }
                                .buttonStyle(ChipStyle(isSelected: false))
                        }
                    }
                }
                .disabled(model.isGenerating)

                if model.isGenerating {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(Array(model.aiProgress.enumerated()), id: \.offset) { index, message in
                            HStack(spacing: Theme.Spacing.s) {
                                if index == model.aiProgress.count - 1 {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentGreen)
                                }
                                Text(message).font(.subheadline)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if model.aiProgress.isEmpty {
                            HStack { ProgressView().controlSize(.small); Text("Starting…").font(.subheadline) }
                        }
                    }
                    .rookCard()
                    .animation(.easeOut, value: model.aiProgress)
                    .accessibilityIdentifier("ai.progress")
                }

                if let error = model.aiError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if model.isGenerating {
                    Button("Cancel") { model.cancelGeneration() }
                        .buttonStyle(.rookSecondary)
                } else {
                    Button {
                        promptFocused = false
                        Task { if await model.generate() { onGenerated() } }
                    } label: {
                        Label("Generate Workout", systemImage: "sparkles")
                    }
                    .buttonStyle(.rookPrimary)
                    .disabled(!model.canGenerate)
                    .accessibilityIdentifier("ai.generate")
                }
            }
            .padding(Theme.Spacing.m)
            .background(.bar)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("AI Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !model.isGenerating { promptFocused = true } }
    }
}

// MARK: - Manual

private struct SelectExercisesView: View {
    @Bindable var model: BuilderModel
    let onReview: () -> Void

    var body: some View {
        @Bindable var search = model.search
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        Button("All") { search.muscleGroup = nil }
                            .buttonStyle(ChipStyle(isSelected: search.muscleGroup == nil))
                        ForEach(ExerciseSearchModel.muscleGroups, id: \.self) { group in
                            Button(group.capitalized) { search.muscleGroup = group }
                                .buttonStyle(ChipStyle(isSelected: search.muscleGroup == group))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
            if let error = search.errorMessage {
                ErrorStateView(message: error) { search.retry() }
                    .listRowBackground(Color.clear)
            } else if search.results.isEmpty && !search.isLoading {
                EmptyStateView(systemImage: "magnifyingglass", title: "No exercises found", message: "Try a different search or muscle group.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(search.results) { item in
                    let added = model.contains(item.exerciseId)
                    Button { model.toggle(item) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.semibold))
                                Text(subtitle(for: item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(added ? Theme.accentGreen : Theme.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(added ? .isSelected : [])
                    .sensoryFeedback(.selection, trigger: added)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay { if search.isLoading && search.results.isEmpty { ProgressView() } }
        .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .navigationTitle("Choose Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Review \(model.exercises.count) exercise\(model.exercises.count == 1 ? "" : "s")", action: onReview)
                .buttonStyle(.rookPrimary)
                .disabled(model.exercises.isEmpty)
                .padding(Theme.Spacing.m)
                .background(.bar)
                .accessibilityIdentifier("manual.review")
        }
        .task { await search.loadIfNeeded() }
    }

    private func subtitle(for item: ExerciseCatalogItem) -> String {
        let muscle = (item.muscleGroup ?? item.muscleGroups?.first ?? "").capitalized
        let kind = item.modality.isTimed ? "Timed" : "Sets & reps"
        return [muscle, kind].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Review

private struct ReviewWorkoutView: View {
    @Bindable var model: BuilderModel
    let onEditManually: () -> Void
    let onStart: () -> Void
    @State private var swapIndex: Int?

    var body: some View {
        List {
            Section {
                GymPicker(model: model)
                if model.source == .aiGenerated, let prompt = model.aiPrompt {
                    Label(prompt, systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(Array(model.exercises.enumerated()), id: \.element.exerciseId) { index, exercise in
                    ReviewRow(
                        exercise: exercise,
                        isAI: model.source == .aiGenerated,
                        isSelected: model.selectedForRegenerate.contains(index),
                        onToggleSelect: { model.toggleRegenerateSelection(index) },
                        onSets: { model.setSets($0, at: index) },
                        onReps: { model.setReps($0, at: index) },
                        onDuration: { model.setDuration($0, at: index) }
                    )
                    .swipeActions(edge: .leading) {
                        Button("Swap") { swapIndex = index }.tint(Theme.primary)
                    }
                }
                .onMove { model.move(from: $0, to: $1) }
                .onDelete { model.remove(at: $0) }
            } header: {
                Text("\(model.exercises.count) exercises")
            } footer: {
                Text("Hold and drag to reorder. Swipe left to remove, right to swap.")
            }

            if model.source == .aiGenerated {
                Section {
                    Button {
                        Task { await model.regenerateSelected() }
                    } label: {
                        HStack {
                            if model.isRegenerating { ProgressView().controlSize(.small) }
                            Label(
                                model.selectedForRegenerate.isEmpty ? "Select exercises to replace" : "Replace \(model.selectedForRegenerate.count) with AI",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                    .disabled(!model.canRegenerate)
                    if let error = model.regenerateError {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    Button("Edit in manual builder", action: onEditManually)
                }
            } else {
                Section { Button("Add more exercises", action: onEditManually) }
            }

            if let notice = model.duplicateNotice {
                Text(notice).font(.footnote).foregroundStyle(Theme.warning)
            }
            if let error = model.startError {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review Workout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            RookButton(title: "Start Workout", isLoading: model.isStarting, action: onStart)
                .buttonStyle(.rookSuccess)
                .disabled(!model.canStart)
                .padding(Theme.Spacing.m)
                .background(.bar)
                .accessibilityIdentifier("review.start")
        }
        .sheet(item: Binding(get: { swapIndex.map(SwapTarget.init) }, set: { swapIndex = $0?.index })) { target in
            SwapExerciseSheet(search: model.makeSearch()) { item in
                if model.swap(at: target.index, with: item) { swapIndex = nil }
            }
        }
    }

    private struct SwapTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

private struct ReviewRow: View {
    let exercise: WorkoutExercise
    let isAI: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onSets: (Int) -> Void
    let onReps: (Int) -> Void
    let onDuration: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            if isAI {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.primary : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isSelected ? "Selected for replacement" : "Select for replacement")
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(exercise.exerciseName).font(.subheadline.weight(.semibold))
                if exercise.modality.isTimed {
                    Stepper(value: Binding(get: { exercise.durationSeconds ?? 60 }, set: onDuration), in: 5...3600, step: 15) {
                        Text("\(exercise.durationSeconds ?? 60) seconds").font(.subheadline.monospacedDigit())
                    }
                } else {
                    Stepper(value: Binding(get: { exercise.sets ?? 3 }, set: onSets), in: 1...20) {
                        Text("\(exercise.sets ?? 3) sets").font(.subheadline.monospacedDigit())
                    }
                    Stepper(value: Binding(get: { exercise.reps ?? 8 }, set: onReps), in: 1...100) {
                        Text("\(exercise.reps ?? 8) reps").font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SwapExerciseSheet: View {
    @State var search: ExerciseSearchModel
    let onChoose: (ExerciseCatalogItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(search.results) { item in
                Button { onChoose(item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text((item.muscleGroup ?? "").capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if search.isLoading && search.results.isEmpty { ProgressView() }
                if let error = search.errorMessage { ErrorStateView(message: error) { search.retry() } }
            }
            .searchable(text: $search.query, prompt: "Search exercises")
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await search.loadIfNeeded() }
        }
    }
}
