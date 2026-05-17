// OnboardingFlow.swift
// 主容器，根据 coordinator.step 切换 9 个步骤视图。
// 见 BLUEPRINT §13.2 / DEMO_SCRIPT 00:15-02:00。

import SwiftUI

struct OnboardingFlow: View {
    @StateObject private var coordinator: OnboardingCoordinator
    let onComplete: () -> Void

    init(client: ConvexClientProtocol, onComplete: @escaping () -> Void) {
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
                case .mbti:
                    Step2MBTIView(coordinator: coordinator)
                case .zodiac:
                    Step3ZodiacView(coordinator: coordinator)
                case .eggBlindBox:
                    Step4EggBlindBoxView(coordinator: coordinator)
                case .eggHatch:
                    Step5EggHatchView(coordinator: coordinator)
                case .firstChat:
                    Step6FirstChatView(coordinator: coordinator)
                case .nameInput:
                    Step7NameInputView(coordinator: coordinator)
                case .ostrichResponds:
                    Step8OstrichRespondsView(coordinator: coordinator)
                case .finish:
                    Step9FinishView(coordinator: coordinator, onComplete: onComplete)
                }
            }
            .animation(.easeInOut(duration: 0.32), value: coordinator.step)
            .transition(.opacity)
        }
    }
}

#Preview {
    OnboardingFlow(client: MockConvexClient(), onComplete: {})
}
