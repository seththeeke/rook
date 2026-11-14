import RookFeatures
import SwiftUI

/// Switches between launch, sign-in, onboarding and the signed-in app, and overlays the biometric lock.
struct RootView: View {
    let appModel: AppModel
    let dependencies: AppDependencies
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
        .task { await appModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: appModel.didEnterBackground()
            case .active: appModel.willEnterForeground()
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
            SignedInView(appModel: appModel, dependencies: dependencies, profile: profile)
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
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .accessibilityLabel("Rook")
                ProgressView().tint(.white).opacity(showsProgress ? 1 : 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.brand")
    }
}

/// Full-screen lock shown when biometric unlock is enabled.
struct BiometricLockView: View {
    let appModel: AppModel

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text("Rook is locked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Unlock to continue.")
                    .foregroundStyle(.white.opacity(0.8))
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
                .buttonStyle(RookPrimaryButtonStyle(tint: .white.opacity(0.25)))
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.m)
                Button("Sign in with password instead") {
                    Task { await appModel.signOut() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .task { await appModel.unlock() }
        .accessibilityIdentifier("lock.screen")
    }
}
