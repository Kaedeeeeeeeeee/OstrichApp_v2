import SwiftUI

/// Step 1: 欢迎屏 —— v4 HTML 设计：液态鸵鸟铺满整个屏幕作为背景，
/// 文字标题和 CTA 按钮 ZStack 叠在上面。
/// 参考 `shared/reference/v4_liquid_ostrich.html` 的 stage / copy-block / cta-wrap 三层结构。
struct Step1WelcomeView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        ZStack {
            // 背景：cream → cream-deep 渐变（v4 linear-gradient(180deg, #FCFEE8 0%, #F5EAB8 100%)）
            LinearGradient(
                colors: [OstrichColors.cream, OstrichColors.creamDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 鸵鸟铺满整个 frame 作为主视觉（v4 .stage { position: absolute; inset: 0 }）。
            // 没有 size 参数 → fill 父容器；按 viewBox aspect 自然居中。
            LiquidOstrichHeadView()
                .ignoresSafeArea()

            // 顶部标题 + 底部 hint/CTA 叠在鸵鸟上面
            VStack {
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
                .padding(.top, OstrichSpacing.xxl)

                Spacer()

                VStack(spacing: OstrichSpacing.m) {
                    Text("试试拖一下我的脖子")
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.ink.opacity(0.55))

                    OstrichButton("唤醒鸵鸟") {
                        coordinator.next()
                    }
                    .padding(.horizontal, OstrichSpacing.xxl)
                }
                .padding(.bottom, OstrichSpacing.xxl)
            }
        }
    }
}

#Preview {
    Step1WelcomeView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
}
