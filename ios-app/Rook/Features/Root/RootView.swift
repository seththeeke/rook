import RookFeatures
import SwiftUI

/// Switches between launch, sign-in, onboarding and the signed-in app, and overlays the biometric lock.
struct RootView: View {
    let appModel: AppModel
    let dependencies: AppDependencies
    let workout: WorkoutRuntime
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            content
            if appModel.isLocked {
                BiometricLockView(appModel: appModel)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.isLocked)
        .task {
            await workout.ensureRestored()
            await appModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: appModel.didEnterBackground()
            case .active:
                appModel.willEnterForeground()
                Task { await workout.controller.sceneDidBecomeActive() }
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.phase {
        case .launching, .loadingProfile:
            BrandSplashView(showsProgress: appModel.phase == .loadingProfile)
        case .signedOut:
            AuthView(model: AuthFlowModel(auth: dependencies.auth, notice: appModel.signOutNotice) {
                await appModel.didSignIn()
            })
        case .onboarding:
            OnboardingView(appModel: appModel, model: OnboardingModel(api: dependencies.api))
        case .ready(let profile):
            SignedInView(appModel: appModel, dependencies: dependencies, controller: workout.controller, profile: profile)
        case .failed(let message):
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: Theme.Spacing.l) {
                    ErrorStateView(message: message) { Task { await appModel.loadProfile() } }
                    Button("Sign out") { Task { await appModel.signOut() } }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Brand background with the R mark (matches the launch screen, so app start feels seamless).
struct BrandSplashView: View {
    var showsProgress = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Same image, size and centered position as the launch screen, so app start looks continuous.
            Wordmark(width: 220)
            ProgressView()
                .tint(Theme.primaryLight)
                .offset(y: 70)
                .opacity(showsProgress ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.brand")
    }
}

/// The ROOK wordmark. Its transparent background sits on `Theme.background`, which matches the logo.
struct Wordmark: View {
    var width: CGFloat = 220

    var body: some View {
        Image("Wordmark")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel("Rook")
    }
}

/// Full-screen lock shown when biometric unlock is enabled.
struct BiometricLockView: View {
    let appModel: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.primaryLight)
                    .frame(width: 72, height: 72)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border))
                    .accessibilityHidden(true)
                Text("Rook is locked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Unlock to continue.")
                    .foregroundStyle(Theme.textSecondary)
                if let error = appModel.unlockError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button {
                    Task { await appModel.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                }
                .buttonStyle(.rookPrimary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.m)
                Button("Sign in with password instead") {
                    Task { await appModel.signOut() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .task { await appModel.unlock() }
        .accessibilityIdentifier("lock.screen")
    }
}
