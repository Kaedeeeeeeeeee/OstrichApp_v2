import SwiftUI

/// Step 8: 最终唤醒鸵鸟（调 /api/awaken）。
/// 成功（拿到非空 dto + 非空 mainRoomId）→ 自动 onComplete → 跳 Chat。
/// 失败 → 留在本页，显示错误 + 「重试 / 先跳过」按钮，不再静默把用户推到占位屏。
struct Step8AwakeningView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onComplete: (_ ostrichDTO: OstrichDTO?, _ awakenError: String?) -> Void

    @State private var hasStarted = false
    @State private var didFail = false

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

            if didFail {
                errorActions
            }

            Spacer()
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await runAwaken()
        }
    }

    private func runAwaken() async {
        didFail = false
        let dto = await coordinator.awaken()
        if let dto, let roomId = dto.mainRoomId, !roomId.isEmpty {
            onComplete(dto, nil)
        } else {
            didFail = true
        }
    }

    private var errorActions: some View {
        VStack(spacing: OstrichSpacing.m) {
            if let err = coordinator.awakenError {
                Text(err)
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.orangeDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.xl)
            }
            HStack(spacing: OstrichSpacing.m) {
                Button {
                    Task { await runAwaken() }
                } label: {
                    Text("重试")
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.cream)
                        .padding(.horizontal, OstrichSpacing.l)
                        .padding(.vertical, OstrichSpacing.s)
                        .background(Capsule().fill(OstrichColors.orange))
                }
                .disabled(coordinator.isAwakening)

                Button {
                    onComplete(coordinator.ostrichDTO, coordinator.awakenError)
                } label: {
                    Text("先跳过")
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.6))
                        .padding(.horizontal, OstrichSpacing.l)
                        .padding(.vertical, OstrichSpacing.s)
                        .background(
                            Capsule().stroke(OstrichColors.ink.opacity(0.3), lineWidth: 1)
                        )
                }
                .disabled(coordinator.isAwakening)
            }
        }
    }

    private var headline: String {
        if coordinator.isAwakening { return "正在唤醒它…" }
        if didFail { return "好像没唤醒成功。" }
        return "它睁开了眼睛。"
    }

    private var subtitle: String {
        if coordinator.isAwakening { return "鸵鸟正从蛋里走出来。" }
        if didFail { return "再试一次，或者先看看主页。" }
        return "马上就到。"
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step8AwakeningView(
            coordinator: OnboardingCoordinator(client: MockConvexClient()),
            onComplete: { _, _ in }
        )
    }
}
