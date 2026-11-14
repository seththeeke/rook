import ActivityKit
import AppIntents
import RookLiveActivityKit
import SwiftUI
import WidgetKit

@main
struct RookLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

/// Lock Screen + Dynamic Island UI for an in-progress workout.
///
/// Ported from the Capacitor app's extension, keeping what works: timers are `Text(_, style: .timer)` /
/// `Text(timerInterval:)` anchored to dates (WidgetKit keeps those ticking while the app is suspended;
/// `TimelineView` gets throttled), the compact trailing timer has a fixed narrow column, and the expanded
/// island keeps leading/trailing empty with a large centered timer.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Brand.gunmetal)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { EmptyView() }
                DynamicIslandExpandedRegion(.trailing) { EmptyView() }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedTimer(state: context.state)
                }
                .contentMargins(.horizontal, 4)
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text(caption(context.state))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                        WorkoutControls(state: context.state, compact: true)
                    }
                }
                .contentMargins(.horizontal, 8)
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 22, alignment: .leading)
            } compactTrailing: {
                SessionTimer(state: context.state, font: .caption2.weight(.semibold))
                    .frame(width: 56, alignment: .trailing)
                    .clipped()
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(Brand.accent)
            }
            .keylineTint(Brand.accent)
        }
    }

    private func caption(_ state: WorkoutActivityAttributes.ContentState) -> String {
        let workout = state.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return workout.isEmpty ? state.exerciseName : "\(workout) · \(state.exerciseName)"
    }
}

/// Mirrors the app's Theme tokens (the extension can't import the app target).
enum Brand {
    static let accent = Color(red: 0x9F / 255, green: 0x86 / 255, blue: 0xFF / 255)
    static let gunmetal = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1C / 255)
    static let secondaryText = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA6 / 255)
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.workoutName ?? "Rook")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                    .lineLimit(1)
                Spacer()
                Text(state.progressDescription)
                    .font(.caption)
                    .foregroundStyle(Brand.secondaryText)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                SessionTimer(state: state, font: .system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            HStack {
                DetailLine(state: state)
                Spacer()
                WorkoutControls(state: state, compact: false)
            }
        }
        .padding()
    }
}

/// "3 sets × 8 reps · 135 lbs", a running countdown for timed work, or "Paused".
private struct DetailLine: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Label("Paused", systemImage: "pause.fill")
            } else if state.modality == .duration, let end = state.durationEnd {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
                        .monospacedDigit()
                    Text("left")
                }
            } else if state.modality == .duration, let remaining = state.durationRemaining {
                Text("\(state.targetDescription) · \(remaining) s left")
            } else if let weight = state.weightDescription {
                Text("\(state.targetDescription) · \(weight)")
            } else {
                Text(state.targetDescription)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Controls (interactive, iOS 17)

private struct WorkoutControls: View {
    let state: WorkoutActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 12 : 8) {
            Button(intent: PauseResumeWorkoutIntent()) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .tint(Brand.accent.opacity(state.isPaused ? 1 : 0.35))
            if state.exercisePosition < state.exerciseCount {
                Button(intent: NextExerciseIntent()) {
                    Label("Next exercise", systemImage: "forward.end.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 36)
                }
                .tint(Brand.accent)
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .font(.subheadline.weight(.bold))
    }
}

// MARK: - Timers

/// Elapsed session time: ticks via a date-anchored timer while running, frozen while paused.
private struct SessionTimer: View {
    let state: WorkoutActivityAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.isPaused {
                Text(Self.format(state.pausedElapsedSeconds))
            } else {
                Text(state.timerReference, style: .timer)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.trailing)
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Large centered timer for the expanded Dynamic Island (stays in the safe center region).
private struct ExpandedTimer: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        SessionTimer(state: state, font: .system(size: 34, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .dynamicIsland(verticalPlacement: .belowIfTooWide)
    }
}

// MARK: - Previews

private extension WorkoutActivityAttributes.ContentState {
    static let preview = WorkoutActivityAttributes.ContentState(
        workoutName: "Garage Gym", exerciseName: "Barbell Bench Press", exercisePosition: 2, exerciseCount: 6,
        nextExerciseName: "Plank", timerReference: .now.addingTimeInterval(-754), isPaused: false,
        pausedElapsedSeconds: 754, modality: .setsReps, targetSets: 4, targetReps: 6, weight: 185,
        weightUnitLabel: "lbs", durationTarget: nil, durationEnd: nil, durationRemaining: nil
    )
}

#Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes(workoutId: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.preview
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes(workoutId: "preview")) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.preview
}
