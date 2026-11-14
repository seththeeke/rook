import Foundation

/// `GET /metrics/me/global` (`toGlobalResponse` in `lambdas/metrics`).
/// The server returns 404 until the user completes their first workout; callers treat that as `.empty`.
public struct GlobalMetrics: Codable, Equatable, Sendable {
    public var totalWorkouts: Int
    public var currentStreak: Int
    public var longestStreak: Int
    /// Day key ("YYYY-MM-DD", UTC).
    public var lastWorkoutDate: String?
    public var workoutsLast30: Int
    public var workoutsLast90: Int
    public var workoutsLast180: Int
    public var totalVolumeAllTime: Double
    /// UTC day keys ("YYYY-MM-DD") with at least one completed workout.
    public var completedDates: [String]
    public var updatedAt: Date?

    public init(
        totalWorkouts: Int = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastWorkoutDate: String? = nil,
        workoutsLast30: Int = 0,
        workoutsLast90: Int = 0,
        workoutsLast180: Int = 0,
        totalVolumeAllTime: Double = 0,
        completedDates: [String] = [],
        updatedAt: Date? = nil
    ) {
        self.totalWorkouts = totalWorkouts
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastWorkoutDate = lastWorkoutDate
        self.workoutsLast30 = workoutsLast30
        self.workoutsLast90 = workoutsLast90
        self.workoutsLast180 = workoutsLast180
        self.totalVolumeAllTime = totalVolumeAllTime
        self.completedDates = completedDates
        self.updatedAt = updatedAt
    }

    public static let empty = GlobalMetrics()

    private enum CodingKeys: String, CodingKey {
        case totalWorkouts, currentStreak, longestStreak, lastWorkoutDate
        case workoutsLast30, workoutsLast90, workoutsLast180, totalVolumeAllTime, completedDates, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalWorkouts = try c.decodeIfPresent(Int.self, forKey: .totalWorkouts) ?? 0
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        lastWorkoutDate = try c.decodeIfPresent(String.self, forKey: .lastWorkoutDate)
        workoutsLast30 = try c.decodeIfPresent(Int.self, forKey: .workoutsLast30) ?? 0
        workoutsLast90 = try c.decodeIfPresent(Int.self, forKey: .workoutsLast90) ?? 0
        workoutsLast180 = try c.decodeIfPresent(Int.self, forKey: .workoutsLast180) ?? 0
        totalVolumeAllTime = try c.decodeIfPresent(Double.self, forKey: .totalVolumeAllTime) ?? 0
        completedDates = try c.decodeIfPresent([String].self, forKey: .completedDates) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// `GET /metrics/me/exercises` item (`toExerciseSummary` in `lambdas/metrics`).
public struct ExerciseMetricsSummary: Codable, Equatable, Identifiable, Sendable {
    public var exerciseId: String
    public var exerciseName: String
    public var totalSessions: Int
    public var maxWeight: Double
    public var maxWeightUnit: WeightUnit?
    /// Day key ("YYYY-MM-DD", UTC).
    public var lastPerformedDate: String?
    public var lastUsedWeight: Double?

    public var id: String { exerciseId }

    public init(
        exerciseId: String,
        exerciseName: String,
        totalSessions: Int,
        maxWeight: Double,
        maxWeightUnit: WeightUnit? = nil,
        lastPerformedDate: String? = nil,
        lastUsedWeight: Double? = nil
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.totalSessions = totalSessions
        self.maxWeight = maxWeight
        self.maxWeightUnit = maxWeightUnit
        self.lastPerformedDate = lastPerformedDate
        self.lastUsedWeight = lastUsedWeight
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseId, exerciseName, totalSessions, maxWeight, maxWeightUnit, lastPerformedDate, lastUsedWeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        exerciseName = try c.decodeIfPresent(String.self, forKey: .exerciseName) ?? ""
        totalSessions = try c.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        maxWeight = try c.decodeIfPresent(Double.self, forKey: .maxWeight) ?? 0
        maxWeightUnit = try c.decodeIfPresent(WeightUnit.self, forKey: .maxWeightUnit)
        lastPerformedDate = try c.decodeIfPresent(String.self, forKey: .lastPerformedDate)
        lastUsedWeight = try c.decodeIfPresent(Double.self, forKey: .lastUsedWeight)
    }
}

/// API error body shape: `{ "error": "message" }` (`lambdas/shared/src/response.ts`).
public struct APIErrorBody: Codable, Equatable, Sendable {
    public var error: String
}
