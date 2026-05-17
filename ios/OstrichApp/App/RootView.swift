import SwiftUI

/// 启动相位机：splash → onboarding | main。
/// 参考 docs/BLUEPRINT.md §13.1。
public enum LaunchPhase: Equatable {
    case splash
    case onboarding
    case main
}

extension Notification.Name {
    /// 占位屏「重新走一遍 onboarding」按钮发出。RootView 监听后清状态、切回 .onboarding 相位。
    static let resetOnboarding = Notification.Name("OstrichApp.resetOnboarding")
}

struct RootView: View {
    @State private var phase: LaunchPhase = .splash
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"
    @AppStorage("mainRoomId") private var mainRoomId: String = ""
    /// 刚完成 onboarding 时置 true，MainTabView 看到后立即 push 到 Chat。
    @AppStorage("autoOpenChatOnLaunch") private var autoOpenChatOnLaunch = false
    /// awaken 失败时的最后一条错误；占位屏读它显示给用户。空串表示无错误。
    @AppStorage("lastAwakenError") private var lastAwakenError: String = ""
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
                OnboardingFlow(client: deps.client) { ostrichDTO, awakenError in
                    // 持久化 awaken 拿到的 ids（即便 awaken 失败也标完成，
                    // 让用户进 main，Chat tab 占位提示）。
                    if let dto = ostrichDTO {
                        mainOstrichId = dto.id
                        mainOstrichName = dto.name.isEmpty ? "鸵鸟" : dto.name
                        if let roomId = dto.mainRoomId, !roomId.isEmpty {
                            mainRoomId = roomId
                        }
                    }
                    lastAwakenError = awakenError ?? ""
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
        .task {
            await signInIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetOnboarding)) { _ in
            hasCompletedOnboarding = false
            mainRoomId = ""
            autoOpenChatOnLaunch = false
            lastAwakenError = ""
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .onboarding
            }
        }
    }

    /// Phase 1 mock 鉴权：启动时自动 sign in 拿固定 token，后续所有 endpoint 才能过 requireAuth。
    /// /api/auth/signInWithApple 后端只校验 body 是合法 JSON，body 内容随意。
    /// 之后切真 Apple Sign In 时这里改成 ASAuthorizationAppleIDProvider 走真 flow。
    private func signInIfNeeded() async {
        if deps.client.sessionToken != nil { return }
        do {
            let resp: SignInResponseDTO = try await deps.client.call(
                Endpoints.signInWithApple,
                body: nil
            )
            deps.client.sessionToken = resp.sessionToken
        } catch {
            print("[RootView] signIn failed: \(error)")
        }
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
