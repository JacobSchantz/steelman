import SwiftUI
import TestablesKit

@main
struct SteelmanApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

@MainActor
struct RootView: View {
    var body: some View {
        ContentView()
            .overlay(alignment: .top) {
                TestingBannerView(config: TestingViewModel.shared.config)
            }
            .onAppear {
                TestingViewModel.shared.loadTestables()
            }
    }
}
