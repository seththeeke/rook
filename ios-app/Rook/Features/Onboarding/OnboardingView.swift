import RookFeatures
import RookModels
import SwiftUI

/// First-run: choose the equipment you have. Creates "My Gym" and completes onboarding.
struct OnboardingView: View {
    let appModel: AppModel
    @State private var model: OnboardingModel

    init(appModel: AppModel, model: OnboardingModel) {
        self.appModel = appModel
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("What equipment do you have?")
                            .font(.largeTitle.bold())
                        Text("Rook uses this to suggest exercises you can actually do. You can change it later.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(EquipmentType.Preset.allCases, id: \.self) { preset in
                            Button(preset.rawValue.capitalized) { model.apply(preset) }
                                .buttonStyle(ChipStyle(isSelected: model.isPresetActive(preset)))
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                        ForEach(EquipmentType.allCases, id: \.self) { type in
                            EquipmentTile(type: type, isSelected: model.selected.contains(type)) {
                                model.toggle(type)
                            }
                        }
                    }

                    if let error = model.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.Spacing.l)
            }

            VStack(spacing: Theme.Spacing.s) {
                RookButton(title: "Continue", isLoading: model.isWorking) { finish(skip: false) }
                    .buttonStyle(.rookPrimary)
                    .disabled(!model.canFinish)
                Button("Skip, I have everything") { finish(skip: true) }
                    .font(.subheadline.weight(.medium))
                    .disabled(model.isWorking)
            }
            .padding(Theme.Spacing.l)
            .background(.bar)
        }
        .background(Theme.background.ignoresSafeArea())
        .accessibilityIdentifier("onboarding")
    }

    private func finish(skip: Bool) {
        Task {
            do {
                let profile = skip ? try await model.skip() : try await model.finish()
                if let profile { appModel.completeOnboarding(with: profile) }
            } catch {
                await appModel.sessionExpired()
            }
        }
    }
}

private struct EquipmentTile: View {
    let type: EquipmentType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: type.symbol)
                    .font(.title2)
                Text(type.label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isSelected ? .clear : Color.secondary.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

extension EquipmentType {
    var symbol: String {
        switch self {
        case .dumbbells: "dumbbell.fill"
        case .freeWeights: "scalemass.fill"
        case .cables: "cable.connector"
        case .weightRack: "square.grid.3x1.below.line.grid.1x2"
        case .cardio: "figure.run"
        case .machines: "gearshape.2.fill"
        }
    }
}

/// Pill-shaped selectable chip (filters, presets, quick prompts).
struct ChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Theme.primary : Color.secondary.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
