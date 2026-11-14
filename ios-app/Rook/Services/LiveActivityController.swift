import ActivityKit
import Foundation
import RookFeatures
import RookLiveActivityKit
import os

/// ActivityKit implementation of `LiveActivityControlling`. If Live Activities are disabled in
/// Settings, every call is a no-op and the workout runs normally (spec §5.2).
struct LiveActivityController: LiveActivityControlling {
    private static let log = Logger(subsystem: "com.rookfitness.app", category: "live-activity")

    static var areEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(workoutId: String, state: WorkoutActivityAttributes.ContentState) async {
        guard Self.areEnabled else {
            Self.log.info("Live Activities disabled; skipping start")
            return
        }
        for activity in activities(for: workoutId) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity.request(
                attributes: WorkoutActivityAttributes(workoutId: workoutId),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(workoutId: String, state: WorkoutActivityAttributes.ContentState) async {
        let current = activities(for: workoutId)
        if current.isEmpty {
            // e.g. the user dismissed it, or it was started while Live Activities were off.
            await start(workoutId: workoutId, state: state)
            return
        }
        for activity in current {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(workoutId: String) async {
        for activity in activities(for: workoutId) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endAll(except workoutId: String?) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.workoutId != workoutId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func isRunning(workoutId: String) async -> Bool {
        !activities(for: workoutId).isEmpty
    }

    private func activities(for workoutId: String) -> [Activity<WorkoutActivityAttributes>] {
        Activity<WorkoutActivityAttributes>.activities.filter {
            $0.attributes.workoutId == workoutId && $0.activityState == .active
        }
    }
}
