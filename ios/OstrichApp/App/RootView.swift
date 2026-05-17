import SwiftUI

/// 启动相位机：splash → onboarding | main。
/// 参考 docs/BLUEPRINT.md §13.1。
public enum LaunchPhase: Equatable {
    case splash
    case onboarding
    case main
}

struct RootView: View {
    @State private var phase: LaunchPhase = .splash
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"
    @AppStorage("mainRoomId") private var mainRoomId: String = ""
    /// 刚完成 onboarding 时置 true，MainTabView 看到后立即 push 到 Chat。
    @AppStorage("autoOpenChatOnLaunch") private var autoOpenChatOnLaunch = false
    @EnvironmentObject private var deps: AppDependency

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashScreen {
                    phase = hasCompletedOnboarding ? .main : .onboarding
                }
                .transition(.opacity)
            case .onboarding:
                OnboardingFlow(client: deps.client) { ostrichDTO in
                    // 持久化 awaken 拿到的 ids（即便 awaken 失败也标完成，
                    // 让用户进 main，Chat tab 占位提示）。
                    if let dto = ostrichDTO {
                        mainOstrichId = dto.id
                        mainOstrichName = dto.name.isEmpty ? "鸵鸟" : dto.name
                        if let roomId = dto.mainRoomId, !roomId.isEmpty {
                            mainRoomId = roomId
                        }
                    }
                    autoOpenChatOnLaunch = true
                    hasCompletedOnboarding = true
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .main
                    }
                }
                .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
    }
}

/// 启动 splash：液态鸵鸟头 320pt 居中，奶油背景，0.8s 后 onComplete。
struct SplashScreen: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            OstrichColors.bodyBackground
                .ignoresSafeArea()

            LiquidOstrichHeadView(size: 320)
        }
        .task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onComplete()
        }
    }
}

#Preview("Splash") {
    SplashScreen(onComplete: {})
}

#Preview("Root") {
    RootView()
        .environmentObject(AppDependency(client: MockConvexClient()))
}
