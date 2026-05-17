import SwiftUI

/// Step 8: 最终唤醒鸵鸟（调 /api/awaken），完成后立即触发 onComplete → 跳 Chat。
struct Step8AwakeningView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onComplete: (_ ostrichDTO: OstrichDTO?) -> Void

    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: OstrichSpacing.l) {
            Spacer()

            LiquidOstrichHeadView(size: 260)
                .frame(width: 300, height: 300)

            VStack(spacing: OstrichSpacing.s) {
                Text(headline)
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text(subtitle)
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.xl)
            }

            Spacer()
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            let dto = await coordinator.awaken()
            // 即便 awaken 失败也通过 onComplete (dto=nil)，让 MainTabView 显示
            // mainRoomId 占位提示，不卡住用户。
            onComplete(dto)
        }
    }

    private var headline: String {
        if coordinator.isAwakening { return "正在唤醒它…" }
        return "它睁开了眼睛。"
    }

    private var subtitle: String {
        if coordinator.isAwakening { return "鸵鸟正从蛋里走出来。" }
        return "马上就到。"
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step8AwakeningView(
            coordinator: OnboardingCoordinator(client: MockConvexClient()),
            onComplete: { _ in }
        )
    }
}
