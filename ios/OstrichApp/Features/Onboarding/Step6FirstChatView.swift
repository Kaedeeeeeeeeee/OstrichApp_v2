import SwiftUI

/// Step 6: 第一次传心。鸵鸟首问「你为什么给我起这个名字？」（UI 模拟 message bubble，不调 Sonnet）。
struct Step6FirstChatView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @State private var bubbleVisible = false

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer(minLength: OstrichSpacing.xl)

            LiquidOstrichHeadView(size: 200)
                .frame(width: 240, height: 240)

            // 鸵鸟说话气泡
            HStack {
                Text("你为什么给我起这个名字？")
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink)
                    .padding(.horizontal, OstrichSpacing.l)
                    .padding(.vertical, OstrichSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                            .fill(OstrichColors.cream)
                    )
                Spacer(minLength: OstrichSpacing.xxl)
            }
            .padding(.horizontal, OstrichSpacing.xl)
            .opacity(bubbleVisible ? 1 : 0)
            .offset(y: bubbleVisible ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: bubbleVisible)

            Spacer()

            OstrichButton("回答它") {
                coordinator.next()
            }
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
        .task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            bubbleVisible = true
        }
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step6FirstChatView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}
