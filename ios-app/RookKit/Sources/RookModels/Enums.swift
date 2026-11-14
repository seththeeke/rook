import Foundation

/// String-backed "open" enums: known values are static constants, and any unknown value the
/// server sends still decodes (instead of failing the whole response). Mirrors
/// `packages/lambdas/shared/src/enums.ts`.
public protocol OpenStringEnum: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral where RawValue == String
{
    init(rawValue: String)
}

extension OpenStringEnum {
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct WorkoutStatus: OpenStringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let inProgress: Self = "in_progress"
    public static let completed: Self = "completed"
    public static let cancelled: Self = "cancelled"
}

public struct WorkoutSource: OpenStringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let aiGenerated: Self = "ai_generated"
    public static let manual: Self = "manual"
}

public struct PermissionType: OpenStringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let `public`: Self = "PUBLIC"
    public static let followersOnly: Self = "FOLLOWERS_ONLY"
    public static let `private`: Self = "PRIVATE"
}

public struct ExerciseModality: OpenStringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let setsReps: Self = "sets_reps"
    public static let duration: Self = "duration"
    public static let burnout: Self = "burnout"

    /// Duration exercises are timed; everything else is logged with a weight.
    public var isTimed: Bool { self == .duration }
}

public struct WeightUnit: OpenStringEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let lbs: Self = "LBS"
    public static let kg: Self = "KG"

    /// Short lowercase label for display ("lbs" / "kg").
    public var label: String {
        switch self {
        case .kg: "kg"
        default: "lbs"
        }
    }
}
