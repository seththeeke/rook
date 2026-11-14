import RookFeatures
import RookFormatting
import RookModels
import RookSession
import SwiftUI
import UIKit

/// The in-progress workout screen. All actions go through `WorkoutSessionController`, which persists,
/// syncs and updates the Live Activity.
struct ExecutionView: View {
    let controller: WorkoutSessionController
    /// Called when the workout ends; `completed` is false when it was cancelled or discarded.
    let onFinished: (_ completed: Bool) -> Void
    @State private var didComplete = false
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var confirmingCancel = false
    @State private var confirmingComplete = false
    @State private var showingBlockers = false
    @AppStorage("rook.liveActivityTipDismissed") private var liveActivityTipDismissed = false
    @FocusState private var weightFocused: Bool

    var body: some View {
        ZStack {
            Theme.executionBackground.ignoresSafeArea()
            if let session = controller.session, let exercise = session.currentExercise {
                content(session: session, exercise: exercise)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: controller.session?.currentIndex, initial: true) { _, _ in syncWeightText() }
        .onChange(of: controller.isActive) { _, active in if !active { onFinished(didComplete) } }
        .confirmationDialog("Cancel this workout?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel Workout", role: .destructive) { Task { await controller.cancel() } }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your progress won't be saved.")
        }
        .alert("Complete workout?", isPresented: $confirmingComplete) {
            Button("Complete") { Task { await finish() } }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(completionSummary)
        }
        .alert("Some exercises aren't logged", isPresented: $showingBlockers) {
            if let first = controller.session?.completionBlockers.first {
                Button("Go to \(controller.session?.exercises[first].exerciseName ?? "exercise")") {
                    Task { await jump(to: first) }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Log a weight (0 for bodyweight) or skip: \(blockerNames).")
        }
        .alert("Workout not saved", isPresented: Binding(
            get: { controller.finishError != nil && !controller.isFinishing },
            set: { if !$0 { /* dismissed; error stays until next attempt */ } }
        )) {
            Button("Try Again") { Task { await finish() } }
            Button("Discard Workout", role: .destructive) { Task { await controller.discardLocally() } }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(controller.finishError ?? "")
        }
    }

    // MARK: - Layout

    private func content(session: WorkoutSessionState, exercise: WorkoutExercise) -> some View {
        VStack(spacing: 0) {
            header(session: session)
            if !liveActivityTipDismissed && !LiveActivityController.areEnabled {
                liveActivityTip
            }
            progress(session: session)
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    exerciseHeader(exercise)
                    if exercise.modality.isTimed {
                        DurationCard(controller: controller, session: session)
                    } else {
                        weightCard(exercise: exercise)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            footer(session: session, exercise: exercise)
        }
        .foregroundStyle(.white)
    }

    private func header(session: WorkoutSessionState) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimize workout")
            .accessibilityIdentifier("execution.minimize")
            Spacer()
            VStack(spacing: 0) {
                Group {
                    if session.isPaused {
                        Text(RookFormat.clock(seconds: session.elapsedSeconds(at: controller.now)))
                    } else {
                        Text(session.timerReferenceDate, style: .timer)
                    }
                }
                .font(.rookNumber(28))
                .accessibilityIdentifier("execution.timer")
                syncLabel
            }
            Spacer()
            Button { Task { await controller.togglePause() } } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(session.isPaused ? "Resume workout" : "Pause workout")
            .accessibilityIdentifier("execution.pause")
            Menu {
                Button("Skip Exercise", systemImage: "forward") { Task { await controller.skipCurrent() } }
                Button("Cancel Workout", systemImage: "xmark", role: .destructive) { confirmingCancel = true }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, Theme.Spacing.s)
    }

    @ViewBuilder
    private var syncLabel: some View {
        switch controller.syncStatus {
        case .synced: EmptyView()
        case .saving: Text("Saving…").font(.caption2).foregroundStyle(.white.opacity(0.6))
        case .pending: Label("Not synced yet", systemImage: "icloud.slash").font(.caption2).foregroundStyle(Theme.warning)
        }
    }

    private var liveActivityTip: some View {
        HStack(alignment: .top) {
            Image(systemName: "lock.iphone")
            Text("Turn on Live Activities in Settings → Rook to follow your workout from the Lock Screen and Dynamic Island.")
                .font(.footnote)
            Spacer()
            Button { liveActivityTipDismissed = true } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss tip")
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .padding(.horizontal, Theme.Spacing.m)
    }

    private func progress(session: WorkoutSessionState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exercise \(session.currentIndex + 1) of \(session.exercises.count)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            ProgressView(value: Double(session.currentIndex + 1), total: Double(max(session.exercises.count, 1)))
                .tint(Theme.primaryLight)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
    }

    private func exerciseHeader(_ exercise: WorkoutExercise) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if let last = exercise.lastUsedWeight, !exercise.modality.isTimed {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Last: ").foregroundStyle(.white.opacity(0.6))
                        + Text(RookFormat.weight(last, unit: exercise.lastUsedWeightUnit ?? controller.unit)).bold()
                        + Text(lastDate(exercise)).foregroundStyle(.white.opacity(0.6))
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
            }
            Image(systemName: exercise.modality.isTimed ? "timer" : "dumbbell.fill")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 80, height: 80)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            Text(exercise.exerciseName)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("execution.exerciseName")
            Text(target(exercise))
                .foregroundStyle(.white.opacity(0.6))
            if exercise.skipped {
                Label("Skipped", systemImage: "forward.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private func weightCard(exercise: WorkoutExercise) -> some View {
        let unit = exercise.weightUnit ?? controller.unit
        let step = unit == .kg ? 2.5 : 5
        return VStack(spacing: Theme.Spacing.m) {
            Text("Weight (\(unit.label))").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: Theme.Spacing.m) {
                stepButton("minus", label: "Decrease weight") { adjustWeight(by: -step) }
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.rookNumber(48))
                    .focused($weightFocused)
                    .frame(maxWidth: 180)
                    .onChange(of: weightText) { _, text in
                        if let value = RookFormat.parseWeight(text) { Task { await controller.setWeight(value) } }
                    }
                    .accessibilityLabel("Weight in \(unit.label)")
                    .accessibilityIdentifier("execution.weight")
                stepButton("plus", label: "Increase weight") { adjustWeight(by: step) }
            }
            if let last = exercise.lastUsedWeight, exercise.weight != last {
                Button("Use previous (\(RookFormat.weight(last)))") { weightText = RookFormat.weight(last) }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.primaryLight)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
        .sensoryFeedback(.increase, trigger: weightText)
    }

    private func footer(session: WorkoutSessionState, exercise: WorkoutExercise) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await commitWeight(); await controller.goToPrevious() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(RookSecondaryButtonStyle(tint: .white))
            .disabled(session.isFirst)

            if session.isLast {
                RookButton(title: "Complete", isLoading: controller.isFinishing) {
                    Task { await requestComplete() }
                }
                .buttonStyle(.rookSuccess)
                .accessibilityIdentifier("execution.complete")
            } else {
                Button {
                    Task { await commitWeight(); await controller.goToNext() }
                } label: {
                    Label("Next", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.rookPrimary)
                .accessibilityIdentifier("execution.next")
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.executionBackground)
    }

    // MARK: - Actions

    private func syncWeightText() {
        guard let exercise = controller.session?.currentExercise, !exercise.modality.isTimed else {
            weightText = ""
            return
        }
        weightText = (exercise.weight ?? exercise.lastUsedWeight).map { RookFormat.weight($0) } ?? ""
    }

    private func adjustWeight(by delta: Double) {
        let current = RookFormat.parseWeight(weightText) ?? 0
        weightText = RookFormat.weight(max(0, current + delta))
    }

    /// Records the prefilled/typed weight (as the web app does on Next), so "Last" values count.
    private func commitWeight() async {
        weightFocused = false
        guard let exercise = controller.session?.currentExercise, !exercise.modality.isTimed,
              exercise.weight == nil, let value = RookFormat.parseWeight(weightText)
        else { return }
        await controller.setWeight(value)
    }

    private func requestComplete() async {
        await commitWeight()
        if controller.session?.canComplete == true {
            confirmingComplete = true
        } else {
            showingBlockers = true
        }
    }

    private func finish() async {
        didComplete = true
        if await controller.complete() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            didComplete = false
        }
    }

    private func jump(to index: Int) async {
        guard let session = controller.session else { return }
        let steps = index - session.currentIndex
        for _ in 0..<abs(steps) {
            if steps > 0 { await controller.goToNext() } else { await controller.goToPrevious() }
        }
    }

    // MARK: - Text

    private var completionSummary: String {
        guard let session = controller.session else { return "" }
        let time = RookFormat.clock(seconds: session.elapsedSeconds(at: controller.now))
        let done = session.exercises.count - session.skippedCount
        var text = "\(done) of \(session.exercises.count) exercises in \(time)."
        if session.skippedCount > 0 { text += " \(session.skippedCount) skipped." }
        return text
    }

    private var blockerNames: String {
        guard let session = controller.session else { return "" }
        return session.completionBlockers.map { session.exercises[$0].exerciseName }.joined(separator: ", ")
    }

    private func target(_ exercise: WorkoutExercise) -> String {
        exercise.modality.isTimed
            ? "\(exercise.durationSeconds ?? 60) seconds"
            : "\(exercise.sets ?? 3) sets × \(exercise.reps ?? 8) reps"
    }

    private func lastDate(_ exercise: WorkoutExercise) -> String {
        guard let key = exercise.lastPerformedDate, let relative = RookFormat.relativeDay(dayKey: key) else { return "" }
        return " · \(relative.lowercased())"
    }
}

/// Countdown for timed exercises.
private struct DurationCard: View {
    let controller: WorkoutSessionController
    let session: WorkoutSessionState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.durationRemainingSeconds(at: context.date)
            let target = session.currentDurationTarget
            VStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(target - remaining) / CGFloat(max(target, 1)))
                        .stroke(Theme.accentGreen, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    Text(RookFormat.clock(seconds: remaining))
                        .font(.rookNumber(44))
                        .accessibilityLabel("\(remaining) seconds left")
                }
                .frame(width: 200, height: 200)

                if remaining == 0 {
                    Text("Time's up!").font(.headline).foregroundStyle(Theme.accentGreen)
                }
                HStack(spacing: Theme.Spacing.m) {
                    if remaining > 0 {
                        Button(session.isDurationRunning ? "Pause" : (session.durationElapsedSeconds(at: context.date) > 0 ? "Resume" : "Start")) {
                            Task { await controller.toggleDuration() }
                        }
                        .buttonStyle(RookSecondaryButtonStyle(tint: .white))
                        .accessibilityIdentifier("execution.durationToggle")
                    }
                    Button("Done") { Task { await controller.completeDuration() } }
                        .buttonStyle(.rookSuccess)
                        .accessibilityIdentifier("execution.durationDone")
                }
            }
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// Dashboard banner shown while a workout is in progress.
struct ActiveWorkoutBanner: View {
    let session: WorkoutSessionState
    let now: Date
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isPaused ? "Workout paused" : "Workout in progress").font(.headline)
                    Group {
                        if session.isPaused {
                            Text(RookFormat.clock(seconds: session.elapsedSeconds(at: now)))
                        } else {
                            Text(session.timerReferenceDate, style: .timer)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .opacity(0.85)
                }
                Spacer()
                Text("Resume").font(.subheadline.weight(.bold))
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.m)
            .background(Theme.accentGreen, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.resume")
    }
}
