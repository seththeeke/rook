import RookFeatures
import RookModels
import SwiftUI

/// Log a sauna session: choose the minutes, then complete. No workout screen in between.
struct SaunaLogView: View {
    @State private var model: SaunaLogModel
    let onLogged: (WorkoutInstance) -> Void
    @FocusState private var minutesFocused: Bool

    init(model: SaunaLogModel, onLogged: @escaping (WorkoutInstance) -> Void) {
        _model = State(initialValue: model)
        self.onLogged = onLogged
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFC14D), Theme.accentOrange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 84)
                    .background(Theme.accentOrange.opacity(0.12), in: Circle())
                    .padding(.top, Theme.Spacing.l)
                    .accessibilityHidden(true)

                Text("How long were you in?")
                    .font(.title2.bold())

                minutesField

                HStack(spacing: Theme.Spacing.s) {
                    ForEach(Sauna.presetMinutes, id: \.self) { preset in
                        Button("\(preset) min") {
                            model.minutes = preset
                            minutesFocused = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.minutes == preset ? .white : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            model.minutes == preset ? AnyShapeStyle(Theme.accentOrange) : AnyShapeStyle(Theme.surfaceElevated),
                            in: Capsule()
                        )
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.minutes == preset ? .isSelected : [])
                    }
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Sauna")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                minutesFocused = false
                Task { if let workout = await model.log() { onLogged(workout) } }
            } label: {
                if model.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Complete \(model.minutes) min session")
                }
            }
            .buttonStyle(.rookPrimary)
            .disabled(!model.canLog)
            .padding(Theme.Spacing.m)
            .background(Theme.background.overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) })
            .accessibilityIdentifier("sauna.complete")
        }
        .interactiveDismissDisabled(model.isSaving)
    }

    private var minutesField: some View {
        HStack(spacing: Theme.Spacing.m) {
            stepButton("minus", delta: -1)
            VStack(spacing: 0) {
                TextField("Minutes", value: $model.minutes, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.rookNumber(56))
                    .focused($minutesFocused)
                    .accessibilityLabel("Minutes")
                    .accessibilityIdentifier("sauna.minutes")
                Text("minutes")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            stepButton("plus", delta: 1)
        }
        .rookCard()
    }

    private func stepButton(_ icon: String, delta: Int) -> some View {
        Button {
            model.minutes += delta
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .frame(width: 48, height: 48)
                .background(Theme.surfaceElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "One more minute" : "One less minute")
    }
}
