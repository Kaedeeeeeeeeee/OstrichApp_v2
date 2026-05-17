import SwiftUI

@main
struct OstrichAppMain: App {
    @StateObject private var deps = AppDependency.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deps)
        }
    }
}
