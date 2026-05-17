import SwiftUI

/// Step 9: 完成。CTA → 持久化 ostrich 标识 → 进入主页。
struct Step9FinishView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onComplete: () -> Void

    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"
    /// 主传心室 id (来自 /api/awaken 响应)。ChatView 用它作 roomId。
    /// 与 ostrichId 是不同表 (chat_rooms vs ostriches)，不能混用。
    @AppStorage("mainRoomId") private var mainRoomId: String = ""

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer()

            LiquidOstrichHeadView(size: 220)
                .frame(width: 260, height: 260)

            VStack(spacing: OstrichSpacing.s) {
                Text("它来了。")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text("从今天起，你们在一起 1 天。")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
            }

            Spacer()

            OstrichButton("进入鸵鸟的世界") {
                persistAndFinish()
            }
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }

    /// 把 onboarding 拿到的鸵鸟标识写到 @AppStorage，让其他 tab (Chat 等)
    /// 重启后能继续找到主传心室。
    private func persistAndFinish() {
        if let dto = coordinator.ostrichDTO {
            mainOstrichId = dto.id
            mainOstrichName = dto.name.isEmpty ? "鸵鸟" : dto.name
            // mainRoomId 仅 /api/awaken 响应里有，其他 endpoint 返回的 OstrichDTO 没这字段
            if let roomId = dto.mainRoomId, !roomId.isEmpty {
                mainRoomId = roomId
            }
        }
        onComplete()
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step9FinishView(
            coordinator: OnboardingCoordinator(client: MockConvexClient()),
            onComplete: {}
        )
    }
}
