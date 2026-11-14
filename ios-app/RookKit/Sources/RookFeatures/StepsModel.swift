import Foundation
import Observation

/// Whether the device's step counter can be read.
public enum StepAccess: Sendable, Equatable {
    /// Readable, or not yet asked (the first read shows the Motion & Fitness prompt).
    case available
    /// The user (or a device policy) turned off Motion & Fitness access for the app.
    case denied
    /// No step counting hardware (e.g. the simulator).
    case unavailable
}

/// The device pedometer (CoreMotion in the app; fakes in tests).
public protocol StepCounting: Sendable {
    var access: StepAccess { get }
    /// Steps taken between two dates.
    func steps(from start: Date, to end: Date) async throws -> Int
    /// Live cumulative step counts since `start`. Ends when the consumer stops iterating.
    func stepUpdates(from start: Date) -> AsyncStream<Int>
}

/// Today's step count for the dashboard tile, kept live while the dashboard is on screen.
@MainActor
@Observable
public final class StepsModel {
    public enum State: Equatable, Sendable {
        case loading
        case count(Int)
        case denied
        case unavailable
    }

    public private(set) var state: State = .loading

    private let counter: StepCounting
    private let clock: Clock
    private let calendar: Calendar

    public init(counter: StepCounting, clock: Clock = .system, calendar: Calendar = .current) {
        self.counter = counter
        self.clock = clock
        self.calendar = calendar
    }

    /// Reads today's total once.
    public func refresh() async {
        switch counter.access {
        case .unavailable: state = .unavailable; return
        case .denied: state = .denied; return
        case .available: break
        }
        let now = clock.now()
        do {
            state = .count(try await counter.steps(from: calendar.startOfDay(for: now), to: now))
        } catch is CancellationError {
            return
        } catch {
            // Reading fails when access was just denied at the prompt; otherwise keep what's shown.
            if counter.access == .denied {
                state = .denied
            } else if state == .loading {
                state = .unavailable
            }
        }
    }

    /// Reads today's total, then follows live updates until the calling task is cancelled.
    /// Starts counting from zero again after midnight.
    public func track() async {
        while !Task.isCancelled {
            await refresh()
            guard case .count = state else { return }
            let day = calendar.startOfDay(for: clock.now())
            var dayChanged = false
            for await steps in counter.stepUpdates(from: day) {
                if calendar.startOfDay(for: clock.now()) != day { dayChanged = true; break } // re-read from midnight
                state = .count(steps)
            }
            if !dayChanged { return } // cancelled, or the pedometer stopped sending updates
        }
    }
}
