import SwiftUI

@main
struct RookApp: App {
    @State private var dependencies = AppDependencies.live(configuration: .fromMainBundle())
    @State private var network = NetworkMonitor()
    @State private var toasts = ToastCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !network.isOnline { OfflineBanner() }
                }
                .toasts(toasts)
                .tint(Theme.primary)
        }
    }
}

/// Root of the view hierarchy. Phase 0 shows only the brand mark; Phase 1 replaces this with
/// the authenticated app state machine (see specs/ios-native-rebuild-plan.md).
struct RootView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .accessibilityLabel("Rook")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.brand")
    }
}

#Preview {
    RootView()
}
