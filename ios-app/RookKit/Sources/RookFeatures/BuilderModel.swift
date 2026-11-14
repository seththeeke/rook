import Foundation
import Observation
import RookModels
import RookNetworking

/// Catalog search with debounced queries and muscle-group filtering (manual builder and swap sheet).
@MainActor
@Observable
public final class ExerciseSearchModel {
    public static let muscleGroups = ["chest", "back", "shoulders", "biceps", "triceps", "quadriceps", "hamstrings", "glutes", "core"]

    public var query = "" {
        didSet { if query != oldValue { scheduleSearch(debounced: true) } }
    }
    public var muscleGroup: String? {
        didSet { if muscleGroup != oldValue { scheduleSearch(debounced: false) } }
    }
    public private(set) var results: [ExerciseCatalogItem] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let api: RookAPI
    private let sleep: Sleeper
    private var searchTask: Task<Void, Never>?

    public init(api: RookAPI, sleep: @escaping Sleeper = systemSleeper) {
        self.api = api
        self.sleep = sleep
    }

    /// Initial load (no filters).
    public func loadIfNeeded() async {
        guard results.isEmpty, !isLoading else { return }
        await search()
    }

    /// Waits for any in-flight search (tests and retry buttons).
    public func waitForSearch() async { await searchTask?.value }

    public func retry() { scheduleSearch(debounced: false) }

    private func scheduleSearch(debounced: Bool) {
        searchTask?.cancel()
        searchTask = Task { [weak self, sleep] in
            if debounced {
                do { try await sleep(.milliseconds(300)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.search()
        }
    }

    private func search() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = muscleGroup
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let items = try await api.fetchExercises(muscleGroup: group, search: query.isEmpty ? nil : query)
            guard !Task.isCancelled else { return }
            // Match the web app: also filter locally by name or muscle so results feel instant and exact.
            results = query.isEmpty ? items : items.filter { item in
                item.name.localizedCaseInsensitiveContains(query)
                    || (item.muscleGroups ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = userMessage(for: error)
        }
    }
}

/// Owns the workout draft from "New workout" through "Start workout".
@MainActor
@Observable
public final class BuilderModel {
    // Gyms
    public private(set) var gyms: [Gym] = []
    public var selectedGymId: String?
    public private(set) var gymsError: String?

    // Draft
    public private(set) var exercises: [WorkoutExercise] = []
    public private(set) var source: WorkoutSource = .manual
    public private(set) var aiPrompt: String?
    public private(set) var builderSessionId: String
    /// Set when the user tries to add an exercise that's already in the draft.
    public private(set) var duplicateNotice: String?

    // AI generation
    public var prompt = ""
    public private(set) var aiProgress: [String] = []
    public private(set) var isGenerating = false
    public private(set) var aiError: String?
    public var selectedForRegenerate: Set<Int> = []
    public private(set) var isRegenerating = false
    public private(set) var regenerateError: String?

    // Starting
    public private(set) var isStarting = false
    public private(set) var startError: String?

    public let unit: WeightUnit
    public let search: ExerciseSearchModel

    public static let quickPrompts = ["Push day", "Pull day", "Leg day", "Full body", "30 min quick"]

    private let api: RookAPI
    private let aiStream: AIWorkoutStreaming
    private let makeSessionId: @Sendable () -> String
    private let onSessionExpired: @MainActor () async -> Void
    private var catalogMuscleGroups: [String: String]?
    private var generationTask: Task<[WorkoutExercise]?, Never>?

    public init(
        api: RookAPI,
        aiStream: AIWorkoutStreaming,
        unit: WeightUnit,
        search: ExerciseSearchModel? = nil,
        makeSessionId: @escaping @Sendable () -> String = { UUID().uuidString },
        onSessionExpired: @escaping @MainActor () async -> Void
    ) {
        self.api = api
        self.aiStream = aiStream
        self.unit = unit
        self.search = search ?? ExerciseSearchModel(api: api)
        self.makeSessionId = makeSessionId
        self.builderSessionId = makeSessionId()
        self.onSessionExpired = onSessionExpired
    }

    /// A separate catalog search (e.g. for the swap sheet) so it doesn't disturb the manual builder's filters.
    public func makeSearch() -> ExerciseSearchModel { ExerciseSearchModel(api: api) }

    // MARK: - Gyms

    public var selectedGym: Gym? { gyms.first { $0.gymId == selectedGymId } }

    public func loadGyms() async {
        do {
            let response = try await api.fetchGyms()
            gyms = response.gyms
            if selectedGym == nil { selectedGymId = response.preferredGym?.gymId }
            gymsError = nil
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return }
            gymsError = userMessage(for: error) // non-blocking: building works without a gym
        }
    }

    // MARK: - Manual editing

    public func contains(_ exerciseId: String) -> Bool { exercises.contains { $0.exerciseId == exerciseId } }

    /// Adds a catalog exercise. Duplicates are rejected: the server merges progress by exercise ID,
    /// so the same exercise twice would corrupt logging (spec §6.4).
    @discardableResult
    public func add(_ item: ExerciseCatalogItem) -> Bool {
        guard !contains(item.exerciseId) else {
            duplicateNotice = "\(item.name) is already in this workout."
            return false
        }
        duplicateNotice = nil
        exercises.append(WorkoutExercise(catalogItem: item, orderIndex: exercises.count))
        if source == .aiGenerated { source = .manual }
        return true
    }

    /// Adds or removes a catalog exercise (manual builder checklist).
    public func toggle(_ item: ExerciseCatalogItem) {
        if let index = exercises.firstIndex(where: { $0.exerciseId == item.exerciseId }) {
            remove(at: IndexSet(integer: index))
        } else {
            add(item)
        }
    }

    public func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where exercises.indices.contains(index) {
            exercises.remove(at: index)
        }
        selectedForRegenerate = []
        renumber()
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)` (destination is in pre-move indices).
        let moving = offsets.filter { exercises.indices.contains($0) }.map { exercises[$0] }
        let insertAt = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where exercises.indices.contains(index) {
            exercises.remove(at: index)
        }
        exercises.insert(contentsOf: moving, at: min(max(0, insertAt), exercises.count))
        selectedForRegenerate = []
        renumber()
    }

    public func clear() {
        exercises = []
        selectedForRegenerate = []
    }

    public func setSets(_ value: Int, at index: Int) { update(index) { $0.sets = min(max(1, value), 20) } }
    public func setReps(_ value: Int, at index: Int) { update(index) { $0.reps = min(max(1, value), 100) } }
    public func setDuration(_ seconds: Int, at index: Int) { update(index) { $0.durationSeconds = min(max(5, seconds), 3600) } }

    /// Replaces the exercise at `index` with a catalog item (rejects items already elsewhere in the draft).
    @discardableResult
    public func swap(at index: Int, with item: ExerciseCatalogItem) -> Bool {
        guard exercises.indices.contains(index) else { return false }
        if let existing = exercises.firstIndex(where: { $0.exerciseId == item.exerciseId }), existing != index {
            duplicateNotice = "\(item.name) is already in this workout."
            return false
        }
        duplicateNotice = nil
        exercises[index] = WorkoutExercise(catalogItem: item, orderIndex: index)
        return true
    }

    /// Copies a past workout's exercises into the draft (fresh, unlogged).
    public func loadPastWorkout(_ workout: WorkoutInstance) {
        var seen = Set<String>()
        exercises = workout.orderedExercises.compactMap { ex in
            guard seen.insert(ex.exerciseId).inserted else { return nil }
            return WorkoutExercise(
                exerciseId: ex.exerciseId, exerciseName: ex.exerciseName, modality: ex.modality,
                sets: ex.sets, reps: ex.reps, durationSeconds: ex.durationSeconds
            )
        }
        renumber()
        source = .manual
        aiPrompt = nil
        selectedForRegenerate = []
        if let gymId = workout.gymId, gyms.contains(where: { $0.gymId == gymId }) { selectedGymId = gymId }
    }

    /// "Edit in manual builder" from an AI draft.
    public func convertToManual() {
        source = .manual
        selectedForRegenerate = []
    }

    // MARK: - AI

    public var canGenerate: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating }

    public func appendQuickPrompt(_ text: String) {
        prompt = prompt.isEmpty ? text : "\(prompt) \(text)"
    }

    /// Streams a new AI workout into the draft. Returns true when exercises were produced.
    public func generate() async -> Bool {
        guard canGenerate else { return false }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isGenerating = true
        aiError = nil
        aiProgress = []
        builderSessionId = makeSessionId()
        defer { isGenerating = false }

        let request = AIGenerateRequest(
            aiPrompt: trimmed, weightUnit: unit,
            equipmentTypes: selectedGym.map(\.equipmentTypes), builderSessionId: builderSessionId
        )
        guard let result = await consume(aiStream.generate(request), onError: { self.aiError = $0 }) else { return false }
        let cleaned = Self.normalized(result)
        guard !cleaned.isEmpty else {
            aiError = "No exercises matched that request. Try describing it differently."
            return false
        }
        exercises = cleaned
        source = .aiGenerated
        aiPrompt = trimmed
        selectedForRegenerate = []
        return true
    }

    public func cancelGeneration() {
        generationTask?.cancel()
    }

    public var canRegenerate: Bool {
        source == .aiGenerated && !selectedForRegenerate.isEmpty && !isRegenerating
    }

    public func toggleRegenerateSelection(_ index: Int) {
        if selectedForRegenerate.contains(index) { selectedForRegenerate.remove(index) } else { selectedForRegenerate.insert(index) }
        regenerateError = nil
    }

    /// Replaces the selected exercises with new AI picks targeting the same muscle groups.
    public func regenerateSelected() async {
        guard canRegenerate else { return }
        isRegenerating = true
        regenerateError = nil
        defer { isRegenerating = false }

        let indices = selectedForRegenerate.sorted()
        let muscles = await muscleGroupsByExercise()
        let context = AIRegenerateRequest.Context(
            exerciseIndices: indices,
            currentExerciseIds: exercises.map(\.exerciseId),
            targetMuscleGroups: indices.map { muscles[exercises[$0].exerciseId] ?? "full" },
            userPrompt: aiPrompt ?? "",
            equipmentTypes: selectedGym.map(\.equipmentTypes)
        )
        let request = AIRegenerateRequest(regenerateContext: context, currentExercises: exercises, builderSessionId: builderSessionId)
        guard let result = await consume(aiStream.regenerate(request), onError: { self.regenerateError = $0 }) else { return }
        let cleaned = Self.normalized(result)
        guard !cleaned.isEmpty else {
            regenerateError = "Couldn't find replacements. Try selecting different exercises."
            return
        }
        exercises = cleaned
        selectedForRegenerate = []
    }

    /// Runs a stream to completion, recording progress. Returns the exercises, or nil after reporting an error.
    private func consume(
        _ stream: AsyncThrowingStream<AIStreamEvent, Error>,
        onError: @escaping @MainActor (String) -> Void
    ) async -> [WorkoutExercise]? {
        let task = Task { @MainActor () -> [WorkoutExercise]? in
            do {
                var outcome: [WorkoutExercise]?
                for try await event in stream {
                    switch event {
                    case .progress(_, let message):
                        if !message.isEmpty, self.aiProgress.last != message { self.aiProgress.append(message) }
                    case .complete(let exercises):
                        outcome = exercises
                    }
                }
                if Task.isCancelled { return nil }
                if outcome == nil { onError(AIStreamError.incomplete.userMessage) }
                return outcome
            } catch is CancellationError {
                return nil // user cancelled: no error message
            } catch {
                if isSessionExpired(error) {
                    await self.onSessionExpired()
                } else {
                    onError(userMessage(for: error))
                }
                return nil
            }
        }
        generationTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        generationTask = nil
        return result
    }

    private func muscleGroupsByExercise() async -> [String: String] {
        if let catalogMuscleGroups { return catalogMuscleGroups }
        let catalog = (try? await api.fetchExercises(muscleGroup: nil, search: nil)) ?? []
        let map = Dictionary(catalog.compactMap { item in item.muscleGroup.map { (item.exerciseId, $0) } }, uniquingKeysWith: { a, _ in a })
        if !map.isEmpty { catalogMuscleGroups = map }
        return map
    }

    /// Applies defaults, drops duplicate exercise IDs, and renumbers.
    static func normalized(_ exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        var seen = Set<String>()
        return exercises.filter { seen.insert($0.exerciseId).inserted }.enumerated().map { index, ex in
            var e = ex
            if e.modality.isTimed {
                e.durationSeconds = e.durationSeconds ?? WorkoutExercise.defaultDurationSeconds
            } else {
                e.sets = e.sets ?? WorkoutExercise.defaultSets
                e.reps = e.reps ?? WorkoutExercise.defaultReps
            }
            e.skipped = false
            e.orderIndex = index
            return e
        }
    }

    // MARK: - Start

    public var canStart: Bool { !exercises.isEmpty && !isStarting }

    /// Creates the workout on the server. Returns it so the caller can start the session.
    public func startWorkout() async -> WorkoutInstance? {
        guard canStart else { return nil }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            renumber()
            let request = CreateWorkoutRequest(
                exercises: exercises, source: source, permissionType: .followersOnly,
                gymId: selectedGym?.gymId, gymName: selectedGym?.name
            )
            return try await api.createWorkout(request)
        } catch {
            if isSessionExpired(error) { await onSessionExpired(); return nil }
            startError = "Couldn't start the workout. \(userMessage(for: error))"
            return nil
        }
    }

    // MARK: - Helpers

    private func update(_ index: Int, _ body: (inout WorkoutExercise) -> Void) {
        guard exercises.indices.contains(index) else { return }
        body(&exercises[index])
    }

    private func renumber() {
        for i in exercises.indices { exercises[i].orderIndex = i }
    }
}
