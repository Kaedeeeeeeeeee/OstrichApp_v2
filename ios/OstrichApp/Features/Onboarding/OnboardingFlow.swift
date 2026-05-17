// OnboardingFlow.swift
// 主容器，根据 coordinator.step 切换 8 个步骤视图。
// 流程见 OnboardingStep 注释（demo 试跑后的新顺序）：
//   welcome → eggBlindBox → eggHatch → userNameAsk → ostrichNameInput →
//   mbti → zodiac → awakening (调 /api/awaken 后直接跳 Chat)

import SwiftUI

struct OnboardingFlow: View {
    @StateObject private var coordinator: OnboardingCoordinator
    /// 完成 onboarding 时回调：第一个参数是 awaken 返回的 OstrichDTO（含 mainRoomId），
    /// 第二个参数是 awaken 失败时的错误字符串（成功为 nil）。
    let onComplete: (_ ostrichDTO: OstrichDTO?, _ awakenError: String?) -> Void

    init(
        client: ConvexClientProtocol,
        onComplete: @escaping (_ ostrichDTO: OstrichDTO?, _ awakenError: String?) -> Void
    ) {
        _coordinator = StateObject(wrappedValue: OnboardingCoordinator(client: client))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            Group {
                switch coordinator.step {
                case .welcome:
                    Step1WelcomeView(coordinator: coordinator)
                case .eggBlindBox:
                    Step4EggBlindBoxView(coordinator: coordinator)
                case .eggHatch:
                    Step5EggHatchView(coordinator: coordinator)
                case .userNameAsk:
                    Step4UserNameAskView(coordinator: coordinator)
                case .ostrichNameInput:
                    Step5OstrichNameView(coordinator: coordinator)
                case .mbti:
                    Step2MBTIView(coordinator: coordinator)
                case .zodiac:
                    Step3ZodiacView(coordinator: coordinator)
                case .awakening:
                    Step8AwakeningView(coordinator: coordinator, onComplete: onComplete)
                }
            }
            .animation(.easeInOut(duration: 0.32), value: coordinator.step)
            .transition(.opacity)
        }
    }
}

#Preview {
    OnboardingFlow(client: MockConvexClient(), onComplete: { _, _ in })
}
