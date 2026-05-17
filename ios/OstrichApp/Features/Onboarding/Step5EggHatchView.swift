import SwiftUI

/// Step 5: 选定蛋旋转一圈 → 狗牙状裂缝撑开 → 替换为 LiquidOstrichHeadView。耗时 ~2.5s。
struct Step5EggHatchView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @State private var rotation: Double = 0
    @State private var crackOpacity: Double = 0
    @State private var crackHeight: CGFloat = 0
    @State private var eggScale: CGFloat = 1
    @State private var ostrichOpacity: Double = 0

    /// 蛋视觉尺寸。crack 高度按它的比例插值。
    private let eggWidth: CGFloat = 220
    private let eggHeight: CGFloat = 305  // aspect 0.72

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer()

            ZStack {
                if let egg = coordinator.selectedEgg {
                    // 蛋本体：EggShape + 斑点（与 Step4 风格一致）
                    EggShape()
                        .fill(egg.primary)
                        .overlay(
                            EggShape()
                                .stroke(OstrichColors.ink.opacity(0.1), lineWidth: 1)
                        )
                        .overlay(
                            EggHatchSpeckles(color: egg.secondary)
                                .clipShape(EggShape())
                        )
                        .frame(width: eggWidth, height: eggHeight)
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(eggScale)
                        .opacity(1.0 - ostrichOpacity)

                    // 狗牙状裂缝：横穿蛋中部的锯齿带。撑开时高度从 0 增长，露出背景色。
                    // 宽度比蛋略窄 (×0.92) 让锯齿不会超出蛋的侧缘。
                    EggCrackShape(toothCount: 9, peakDepth: 0.55)
                        .fill(OstrichColors.bodyBackground)
                        .frame(width: eggWidth * 0.92, height: crackHeight)
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
        // Stage 1 (0 - 1.0s): 旋转一圈
        withAnimation(.easeInOut(duration: 1.0)) {
            rotation = 360
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Stage 2 (1.0 - 2.0s): 狗牙裂缝撑开
        withAnimation(.easeOut(duration: 0.9)) {
            crackOpacity = 1.0
            crackHeight = 70  // 裂缝中间空隙撑到 70pt 高
            eggScale = 1.08
        }
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Stage 3 (2.0 - 2.5s): 鸵鸟显现 + 蛋淡出
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            ostrichOpacity = 1.0
        }
        try? await Task.sleep(nanoseconds: 600_000_000)

        coordinator.next()
    }
}

/// 横向锯齿带 —— 上下边都是三角牙齿，中间是空隙。
/// 视觉效果：蛋壳沿中线裂开，上下半各 N 颗向中心方向的尖牙。
struct EggCrackShape: Shape {
    /// 上半 / 下半各有多少颗牙齿。
    let toothCount: Int
    /// 牙齿尖端伸入空隙的比例 (0..1)。1.0 = 牙尖触碰中线。
    let peakDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let midY = rect.midY
        let halfH = h / 2
        let toothW = w / CGFloat(toothCount)
        let peakOffset = halfH * peakDepth

        // 上边：从左上角开始，沿牙齿轮廓走到右上角
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for i in 0..<toothCount {
            let baseX = rect.minX + CGFloat(i) * toothW
            let tipX = baseX + toothW / 2
            // 牙尖向下伸（向 midY 方向）
            path.addLine(to: CGPoint(x: tipX, y: midY - (halfH - peakOffset)))
            path.addLine(to: CGPoint(x: baseX + toothW, y: rect.minY))
        }

        // 右下角
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // 下边：从右下走回左下，牙尖向上伸
        for i in stride(from: toothCount - 1, through: 0, by: -1) {
            let baseRightX = rect.minX + CGFloat(i + 1) * toothW
            let tipX = baseRightX - toothW / 2
            path.addLine(to: CGPoint(x: tipX, y: midY + (halfH - peakOffset)))
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * toothW, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

/// 与 Step4 EggSpeckles 同形 — 但放在私有作用域避免 cross-file private 冲突。
private struct EggHatchSpeckles: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle()
                    .fill(color.opacity(0.55))
                    .frame(width: w * 0.18, height: w * 0.18)
                    .position(x: w * 0.35, y: h * 0.4)
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.65, y: h * 0.58)
                Circle()
                    .fill(color.opacity(0.5))
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.5, y: h * 0.78)
            }
        }
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
