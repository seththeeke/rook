import Foundation

/// An exercise from the catalog (`GET /exercises`).
public struct ExerciseCatalogItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var exerciseId: String
    public var name: String
    public var muscleGroups: [String]?
    public var muscleGroup: String?
    public var equipment: [String]?
    public var equipmentPrimary: String?
    public var modality: ExerciseModality
    public var defaultSets: Int?
    public var defaultReps: Int?
    public var defaultDurationSeconds: Int?
    public var difficulty: String?
    public var instructions: String?
    public var isActive: Bool?

    public var id: String { exerciseId }

    public init(
        exerciseId: String,
        name: String,
        muscleGroups: [String]? = nil,
        muscleGroup: String? = nil,
        equipment: [String]? = nil,
        equipmentPrimary: String? = nil,
        modality: ExerciseModality,
        defaultSets: Int? = nil,
        defaultReps: Int? = nil,
        defaultDurationSeconds: Int? = nil,
        difficulty: String? = nil,
        instructions: String? = nil,
        isActive: Bool? = nil
    ) {
        self.exerciseId = exerciseId
        self.name = name
        self.muscleGroups = muscleGroups
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.equipmentPrimary = equipmentPrimary
        self.modality = modality
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultDurationSeconds = defaultDurationSeconds
        self.difficulty = difficulty
        self.instructions = instructions
        self.isActive = isActive
    }
}

/// One exercise inside a workout instance.
public struct WorkoutExercise: Codable, Equatable, Hashable, Sendable {
    public static let defaultSets = 3
    public static let defaultReps = 8
    public static let defaultDurationSeconds = 60

    public var exerciseId: String
    public var exerciseName: String
    public var modality: ExerciseModality
    public var sets: Int?
    public var reps: Int?
    public var durationSeconds: Int?
    public var weight: Double?
    public var weightUnit: WeightUnit?
    public var notes: String?
    public var completedAt: Date?
    public var skipped: Bool
    public var orderIndex: Int
    /// Enriched by the server from exercise metrics when the workout is created.
    public var lastUsedWeight: Double?
    public var lastUsedWeightUnit: WeightUnit?
    /// Calendar day key ("YYYY-MM-DD", UTC) of the last session with this exercise.
    public var lastPerformedDate: String?

    public init(
        exerciseId: String,
        exerciseName: String,
        modality: ExerciseModality,
        sets: Int? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = nil,
        notes: String? = nil,
        completedAt: Date? = nil,
        skipped: Bool = false,
        orderIndex: Int = 0,
        lastUsedWeight: Double? = nil,
        lastUsedWeightUnit: WeightUnit? = nil,
        lastPerformedDate: String? = nil
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.modality = modality
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.weight = weight
        self.weightUnit = weightUnit
        self.notes = notes
        self.completedAt = completedAt
        self.skipped = skipped
        self.orderIndex = orderIndex
        self.lastUsedWeight = lastUsedWeight
        self.lastUsedWeightUnit = lastUsedWeightUnit
        self.lastPerformedDate = lastPerformedDate
    }

    /// Builds a new workout exercise from a catalog item using the catalog's defaults
    /// (or 3×8 / 60s, matching the web builder).
    public init(catalogItem item: ExerciseCatalogItem, orderIndex: Int) {
        let timed = item.modality.isTimed
        self.init(
            exerciseId: item.exerciseId,
            exerciseName: item.name,
            modality: item.modality,
            sets: timed ? nil : (item.defaultSets ?? Self.defaultSets),
            reps: timed ? nil : (item.defaultReps ?? Self.defaultReps),
            durationSeconds: timed ? (item.defaultDurationSeconds ?? Self.defaultDurationSeconds) : nil,
            orderIndex: orderIndex
        )
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseId, exerciseName, modality, sets, reps, durationSeconds, weight, weightUnit, notes
        case completedAt, skipped, orderIndex, lastUsedWeight, lastUsedWeightUnit, lastPerformedDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        exerciseName = try c.decodeIfPresent(String.self, forKey: .exerciseName) ?? ""
        modality = try c.decodeIfPresent(ExerciseModality.self, forKey: .modality) ?? .setsReps
        sets = try c.decodeIfPresent(Int.self, forKey: .sets)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        weightUnit = try c.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        orderIndex = try c.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        lastUsedWeight = try c.decodeIfPresent(Double.self, forKey: .lastUsedWeight)
        lastUsedWeightUnit = try c.decodeIfPresent(WeightUnit.self, forKey: .lastUsedWeightUnit)
        lastPerformedDate = try c.decodeIfPresent(String.self, forKey: .lastPerformedDate)
    }

    /// Server-side completion rule (`lambdas/workout` PATCH status=completed): every non-skipped
    /// exercise needs a weight, or a duration if it is timed.
    public var isReadyForCompletion: Bool {
        if skipped { return true }
        return modality.isTimed ? durationSeconds != nil : weight != nil
    }

    /// weight × sets × reps for completed sets/reps work (matches the server's totalVolume).
    public var volume: Double {
        guard !skipped, modality == .setsReps, let weight, let sets, let reps else { return 0 }
        return weight * Double(sets) * Double(reps)
    }
}

/// A workout instance (`toResponse` in `lambdas/workout`).
public struct WorkoutInstance: Codable, Equatable, Identifiable, Sendable {
    public var workoutInstanceId: String
    public var userId: String?
    public var status: WorkoutStatus
    public var source: WorkoutSource?
    public var permissionType: PermissionType?
    public var startedAt: Date
    public var completedAt: Date?
    public var durationMinutes: Int?
    public var totalVolume: Double?
    public var notes: String?
    public var gymId: String?
    public var gymName: String?
    public var exercises: [WorkoutExercise]

    public var id: String { workoutInstanceId }

    public init(
        workoutInstanceId: String,
        userId: String? = nil,
        status: WorkoutStatus,
        source: WorkoutSource? = nil,
        permissionType: PermissionType? = nil,
        startedAt: Date,
        completedAt: Date? = nil,
        durationMinutes: Int? = nil,
        totalVolume: Double? = nil,
        notes: String? = nil,
        gymId: String? = nil,
        gymName: String? = nil,
        exercises: [WorkoutExercise]
    ) {
        self.workoutInstanceId = workoutInstanceId
        self.userId = userId
        self.status = status
        self.source = source
        self.permissionType = permissionType
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMinutes = durationMinutes
        self.totalVolume = totalVolume
        self.notes = notes
        self.gymId = gymId
        self.gymName = gymName
        self.exercises = exercises
    }

    private enum CodingKeys: String, CodingKey {
        case workoutInstanceId, userId, status, source, permissionType, startedAt, completedAt
        case durationMinutes, totalVolume, notes, gymId, gymName, exercises
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutInstanceId = try c.decode(String.self, forKey: .workoutInstanceId)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        status = try c.decode(WorkoutStatus.self, forKey: .status)
        source = try c.decodeIfPresent(WorkoutSource.self, forKey: .source)
        permissionType = try c.decodeIfPresent(PermissionType.self, forKey: .permissionType)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        totalVolume = try c.decodeIfPresent(Double.self, forKey: .totalVolume)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        gymId = try c.decodeIfPresent(String.self, forKey: .gymId)
        gymName = try c.decodeIfPresent(String.self, forKey: .gymName)
        exercises = try c.decodeIfPresent([WorkoutExercise].self, forKey: .exercises) ?? []
    }

    /// Exercises in their intended order.
    public var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}

/// `GET /workout-instances` page.
public struct WorkoutListPage: Codable, Equatable, Sendable {
    public var items: [WorkoutInstance]
    public var nextToken: String?

    public init(items: [WorkoutInstance], nextToken: String?) {
        self.items = items
        self.nextToken = nextToken
    }
}

/// `POST /workout-instances` body.
public struct CreateWorkoutRequest: Encodable, Equatable, Sendable {
    public var exercises: [WorkoutExercise]
    public var source: WorkoutSource
    public var permissionType: PermissionType
    public var gymId: String?
    public var gymName: String?

    public init(
        exercises: [WorkoutExercise],
        source: WorkoutSource,
        permissionType: PermissionType = .followersOnly,
        gymId: String? = nil,
        gymName: String? = nil
    ) {
        self.exercises = exercises
        self.source = source
        self.permissionType = permissionType
        self.gymId = gymId
        self.gymName = gymName
    }
}

/// `PATCH /workout-instances/{id}` body.
public struct UpdateWorkoutRequest: Encodable, Equatable, Sendable {
    public var status: WorkoutStatus?
    public var exercises: [WorkoutExercise]?
    public var notes: String?

    public init(status: WorkoutStatus? = nil, exercises: [WorkoutExercise]? = nil, notes: String? = nil) {
        self.status = status
        self.exercises = exercises
        self.notes = notes
    }

    public static func progress(_ exercises: [WorkoutExercise]) -> Self { .init(exercises: exercises) }
    public static func complete(_ exercises: [WorkoutExercise]) -> Self { .init(status: .completed, exercises: exercises) }
    public static let cancel = Self(status: .cancelled)
}
