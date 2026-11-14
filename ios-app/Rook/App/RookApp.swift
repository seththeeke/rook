import SwiftUI

@main
struct RookApp: App {
    private let configuration = AppConfiguration.fromMainBundle()

    var body: some Scene {
        WindowGroup {
            RootView()
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
