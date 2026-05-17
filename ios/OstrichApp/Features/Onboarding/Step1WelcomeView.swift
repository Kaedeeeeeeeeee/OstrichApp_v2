import SwiftUI

/// Step 1: 欢迎 + 介绍 + "唤醒鸵鸟" CTA。
struct Step1WelcomeView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer(minLength: OstrichSpacing.xl)

            LiquidOstrichHeadView(size: 180)
                .frame(width: 220, height: 220)

            VStack(spacing: OstrichSpacing.s) {
                Text("鸵鸟")
                    .font(OstrichTypography.largeTitle)
                    .foregroundStyle(OstrichColors.ink)

                Text("一个会自己呼吸的生命，\n而不是被你养的宠物。")
                    .multilineTextAlignment(.center)
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.65))
                    .padding(.horizontal, OstrichSpacing.xl)
            }

            Spacer()

            OstrichButton("唤醒鸵鸟") {
                coordinator.next()
            }
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step1WelcomeView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}
