import Foundation

/// `GET /users/me` and `PATCH /users/me` response (`toMeProfile` in `lambdas/user`).
public struct UserProfile: Codable, Equatable, Sendable {
    public var userId: String
    public var email: String?
    public var username: String
    public var displayName: String?
    public var profilePhoto: String?
    public var bio: String?
    public var weightUnit: WeightUnit?
    public var defaultGymId: String?
    public var onboardingCompletedAt: Date?
    public var createdAt: Date?

    public init(
        userId: String,
        email: String? = nil,
        username: String,
        displayName: String? = nil,
        profilePhoto: String? = nil,
        bio: String? = nil,
        weightUnit: WeightUnit? = nil,
        defaultGymId: String? = nil,
        onboardingCompletedAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.userId = userId
        self.email = email
        self.username = username
        self.displayName = displayName
        self.profilePhoto = profilePhoto
        self.bio = bio
        self.weightUnit = weightUnit
        self.defaultGymId = defaultGymId
        self.onboardingCompletedAt = onboardingCompletedAt
        self.createdAt = createdAt
    }

    /// The unit the user logs in. The server defaults new profiles to LBS.
    public var preferredUnit: WeightUnit { weightUnit ?? .lbs }

    /// Display name with a sensible fallback (the server sets displayName = username at sign-up).
    public var resolvedDisplayName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }

    public var needsOnboarding: Bool { onboardingCompletedAt == nil }
}

/// Fields accepted by `PATCH /users/me` that Rook writes. `nil` fields are omitted from the body.
public struct UserProfileUpdate: Encodable, Equatable, Sendable {
    public var weightUnit: WeightUnit?
    public var defaultGymId: String?
    public var onboardingCompletedAt: Date?

    public init(weightUnit: WeightUnit? = nil, defaultGymId: String? = nil, onboardingCompletedAt: Date? = nil) {
        self.weightUnit = weightUnit
        self.defaultGymId = defaultGymId
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}

/// A user-owned gym (`lambdas/gyms`).
public struct Gym: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var gymId: String
    public var name: String
    public var equipmentTypes: [String]

    public var id: String { gymId }

    public init(gymId: String, name: String, equipmentTypes: [String]) {
        self.gymId = gymId
        self.name = name
        self.equipmentTypes = equipmentTypes
    }
}

/// `GET /users/me/gyms` response.
public struct GymsListResponse: Codable, Equatable, Sendable {
    public var gyms: [Gym]
    public var defaultGymId: String?

    public init(gyms: [Gym], defaultGymId: String?) {
        self.gyms = gyms
        self.defaultGymId = defaultGymId
    }

    /// The gym to preselect: the default gym, else the first one.
    public var preferredGym: Gym? {
        gyms.first { $0.gymId == defaultGymId } ?? gyms.first
    }
}

/// `POST /users/me/gyms` body.
public struct CreateGymRequest: Encodable, Equatable, Sendable {
    public var name: String
    public var equipmentTypes: [String]

    public init(name: String, equipmentTypes: [String]) {
        self.name = name
        self.equipmentTypes = equipmentTypes
    }
}

/// Equipment type IDs stored on a gym. Must match `packages/web/src/constants/equipment.ts`.
public enum EquipmentType: String, CaseIterable, Sendable {
    case dumbbells
    case freeWeights = "free_weights"
    case cables
    case weightRack = "weight_rack"
    case cardio
    case machines

    public var label: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .freeWeights: "Free Weights"
        case .cables: "Cables"
        case .weightRack: "Weight Rack"
        case .cardio: "Cardio"
        case .machines: "Machines"
        }
    }

    public enum Preset: String, CaseIterable, Sendable {
        case commercial, home, minimalist

        public var equipment: [EquipmentType] {
            switch self {
            case .commercial: EquipmentType.allCases
            case .home: [.dumbbells, .freeWeights, .cardio]
            case .minimalist: [.dumbbells]
            }
        }
    }
}
