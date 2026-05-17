import SwiftUI

/// Step 5: 蛋旋转 → 沿狗牙状中线裂成上下两半（上半上移、下半下移）→ 鸵鸟出现。耗时 ~2.5s。
struct Step5EggHatchView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @State private var rotation: Double = 0
    /// 两半各向相反方向位移的距离。0 = 紧贴成完整蛋形。
    @State private var separation: CGFloat = 0
    @State private var eggScale: CGFloat = 1
    @State private var ostrichOpacity: Double = 0

    private let eggWidth: CGFloat = 220
    private let eggHeight: CGFloat = 305  // aspect 0.72
    private let toothCount = 9
    private let toothDepth: CGFloat = 22

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer()

            ZStack {
                if let egg = coordinator.selectedEgg {
                    // 两半蛋同源（颜色 + 斑点），用上/下半 mask 切开。
                    // 旋转和缩放共同应用到 ZStack 让两半作为整体保持配准。
                    ZStack {
                        // 上半（向上位移）
                        eggBody(for: egg)
                            .mask(
                                EggHalfMaskShape(
                                    isTop: true,
                                    toothCount: toothCount,
                                    toothDepth: toothDepth
                                )
                            )
                            .offset(y: -separation)

                        // 下半（向下位移）
                        eggBody(for: egg)
                            .mask(
                                EggHalfMaskShape(
                                    isTop: false,
                                    toothCount: toothCount,
                                    toothDepth: toothDepth
                                )
                            )
                            .offset(y: separation)
                    }
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(eggScale)
                    .opacity(1.0 - ostrichOpacity)
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

    /// 单个蛋（颜色 + 描边 + 斑点）。两半共用，由 mask 切上下。
    @ViewBuilder
    private func eggBody(for egg: EggArchetype) -> some View {
        EggShape()
            .fill(egg.primary)
            .overlay(
                EggShape().stroke(OstrichColors.ink.opacity(0.1), lineWidth: 1)
            )
            .overlay(
                EggHatchSpeckles(color: egg.secondary)
                    .clipShape(EggShape())
            )
            .frame(width: eggWidth, height: eggHeight)
    }

    private func runHatchSequence() async {
        // Stage 1 (0 - 1.0s): 旋转一圈
        withAnimation(.easeInOut(duration: 1.0)) {
            rotation = 360
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Stage 2 (1.0 - 2.0s): 两半沿狗牙线分开，向相反方向位移
        withAnimation(.easeOut(duration: 0.9)) {
            separation = 36   // 上下各偏 36pt，总间距 72pt
            eggScale = 1.05
        }
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Stage 3 (2.0 - 2.5s): 鸵鸟显现 + 两半淡出
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            ostrichOpacity = 1.0
        }
        try? await Task.sleep(nanoseconds: 600_000_000)

        coordinator.next()
    }
}

/// 上半 / 下半 mask 矩形，分界线是横向狗牙锯齿。
/// 用 `.mask(EggHalfMaskShape(isTop: true, ...))` 切到 EggShape 上得到上半蛋。
struct EggHalfMaskShape: Shape {
    /// true = 保留上半区（mask 在 y < midY 的矩形 + 锯齿底边伸入下半）
    /// false = 保留下半区（mask 在 y > midY 的矩形 + 锯齿顶边伸入上半）
    let isTop: Bool
    let toothCount: Int
    /// 锯齿牙尖伸入对面半区的深度（pt）。
    let toothDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let midY = rect.midY
        let toothW = w / CGFloat(toothCount)

        if isTop {
            // 上半 mask：覆盖 y ∈ [0, midY] + 锯齿牙尖朝下伸入对面
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: midY))
            // 从右往左走狗牙边（牙尖向下）
            for i in stride(from: toothCount - 1, through: 0, by: -1) {
                let baseRightX = CGFloat(i + 1) * toothW
                let tipX = baseRightX - toothW / 2
                path.addLine(to: CGPoint(x: tipX, y: midY + toothDepth))
                path.addLine(to: CGPoint(x: CGFloat(i) * toothW, y: midY))
            }
            path.closeSubpath()
        } else {
            // 下半 mask：覆盖 y ∈ [midY, height] + 锯齿牙尖朝上伸入对面
            path.move(to: CGPoint(x: 0, y: midY))
            // 从左往右走狗牙边（牙尖向上）—— 与上半的牙形互补，错开
            for i in 0..<toothCount {
                let baseLeftX = CGFloat(i) * toothW
                let tipX = baseLeftX + toothW / 2
                path.addLine(to: CGPoint(x: tipX, y: midY - toothDepth))
                path.addLine(to: CGPoint(x: CGFloat(i + 1) * toothW, y: midY))
            }
            path.addLine(to: CGPoint(x: w, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// 蛋上的副色斑点，与 Step4 EggSpeckles 同形（私有副本避免跨文件 private 冲突）。
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
