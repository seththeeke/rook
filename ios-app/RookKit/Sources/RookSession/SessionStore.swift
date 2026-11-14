import Foundation
import RookModels

/// Persists the active workout so it survives app termination (replaces zustand `persist`).
public protocol SessionStoring: Sendable {
    func load() -> WorkoutSessionState?
    func save(_ state: WorkoutSessionState) throws
    func clear() throws
}

/// Stores the session as versioned JSON in Application Support, written atomically.
public final class FileSessionStore: SessionStoring {
    /// Bump when `WorkoutSessionState` changes incompatibly; older files are discarded (the workout
    /// itself is safe on the server and can be resumed from there).
    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var state: WorkoutSessionState
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/Rook/active-workout.json`, excluded from iCloud backup.
    public static func standard() throws -> FileSessionStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        var directory = base.appendingPathComponent("Rook", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return FileSessionStore(fileURL: directory.appendingPathComponent("active-workout.json"))
    }

    public func load() -> WorkoutSessionState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let envelope = try? RookJSON.makeDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion
        else {
            // Corrupt or outdated: remove so we don't keep failing on every launch.
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return envelope.state
    }

    public func save(_ state: WorkoutSessionState) throws {
        let data = try RookJSON.makeEncoder().encode(Envelope(version: Self.currentVersion, state: state))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
