import SwiftUI

/// Step 5: 选定蛋旋转一圈 → 破壳 → 替换为 LiquidOstrichHeadView。耗时 ~2.5s。
struct Step5EggHatchView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @State private var rotation: Double = 0
    @State private var crackOpacity: Double = 0
    @State private var crackWidth: CGFloat = 1
    @State private var eggScale: CGFloat = 1
    @State private var ostrichOpacity: Double = 0

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer()

            ZStack {
                if let egg = coordinator.selectedEgg {
                    RoundedRectangle(cornerRadius: 64, style: .continuous)
                        .fill(egg.primary)
                        .frame(width: 220, height: 314)
                        .overlay(
                            RoundedRectangle(cornerRadius: 64, style: .continuous)
                                .stroke(OstrichColors.ink.opacity(0.1), lineWidth: 1)
                        )
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(eggScale)
                        .opacity(1.0 - ostrichOpacity)

                    // 破壳：从中央垂直伸开一道裂缝
                    Rectangle()
                        .fill(OstrichColors.bodyBackground)
                        .frame(width: crackWidth, height: 320)
                        .opacity(crackOpacity)
                }

                LiquidOstrichHeadView(size: 260)
                    .frame(width: 260, height: 260)
                    .opacity(ostrichOpacity)
            }

            Text("…")
                .font(OstrichTypography.title)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))

            Spacer()
        }
        .task {
            await runHatchSequence()
        }
    }

    private func runHatchSequence() async {
        // Stage 1 (0 - 1.0s)：旋转一圈
        withAnimation(.easeInOut(duration: 1.0)) {
            rotation = 360
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Stage 2 (1.0 - 2.0s)：裂缝渐宽
        withAnimation(.easeOut(duration: 0.9)) {
            crackOpacity = 1.0
            crackWidth = 100
            eggScale = 1.08
        }
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Stage 3 (2.0 - 2.5s)：鸵鸟显现 + 蛋淡出
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            ostrichOpacity = 1.0
        }
        try? await Task.sleep(nanoseconds: 600_000_000)

        coordinator.next()
    }
}

#Preview {
    let c = OnboardingCoordinator(client: MockConvexClient())
    c.selectedEgg = EggCatalog.all[3]
    return ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step5EggHatchView(coordinator: c)
    }
}
