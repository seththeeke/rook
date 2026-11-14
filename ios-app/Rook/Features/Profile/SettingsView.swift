import RookFeatures
import RookModels
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var confirmingSignOut = false
    @State private var showingDelete = false

    let onSignOut: () async -> Void

    init(model: SettingsModel, onSignOut: @escaping () async -> Void) {
        _model = State(initialValue: model)
        self.onSignOut = onSignOut
    }

    var body: some View {
        Form {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Picker("Weight unit", selection: Binding(
                    get: { model.weightUnit },
                    set: { unit in Task { await model.setWeightUnit(unit) } }
                )) {
                    Text("Pounds (lbs)").tag(WeightUnit.lbs)
                    Text("Kilograms (kg)").tag(WeightUnit.kg)
                }
                .disabled(model.isSavingUnit)
                .accessibilityIdentifier("settings.unit")
            } header: {
                Text("Workouts")
            } footer: {
                Text("Used when logging weights and generating workouts.")
            }

            if let biometry = model.biometry {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.biometricEnabled },
                        set: { enabled in Task { await model.setBiometricEnabled(enabled) } }
                    )) {
                        Label("Unlock with \(biometry.label)", systemImage: biometry == .touchID ? "touchid" : "faceid")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Require \(biometry.label) when opening Rook.")
                }
            }

            Section {
                Button("Sign Out") { confirmingSignOut = true }
                    .accessibilityIdentifier("settings.signOut")
                Button("Delete Account", role: .destructive) {
                    model.deleteAcknowledged = false
                    showingDelete = true
                }
            }

            Section {
                LabeledContent("Version", value: model.appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of Rook?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await onSignOut() } }
        }
        .sheet(isPresented: $showingDelete) {
            DeleteAccountSheet(model: model)
                .presentationDetents([.medium])
        }
    }
}

private struct DeleteAccountSheet: View {
    @Bindable var model: SettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Delete your account?")
                .font(.title2.bold())
            Text("This permanently deletes your account, workouts, and progress. This can't be undone.")
                .foregroundStyle(.secondary)
            Toggle(isOn: $model.deleteAcknowledged) {
                Text("I understand my account and data will be permanently deleted.")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
            Spacer()
            RookButton(title: "Delete Account", isLoading: model.isDeleting) {
                Task { await model.deleteAccount() }
            }
            .buttonStyle(.rookDestructive)
            .disabled(!model.deleteAcknowledged)
            Button("Cancel") { dismiss() }
                .frame(maxWidth: .infinity)
                .disabled(model.isDeleting)
        }
        .padding(Theme.Spacing.l)
        .interactiveDismissDisabled(model.isDeleting)
    }
}
