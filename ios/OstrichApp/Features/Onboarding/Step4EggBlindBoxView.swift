import SwiftUI

/// Step 4: 16 个蛋盲盒。每个蛋呼吸 (scale 0.97-1.03)，选中高亮。
struct Step4EggBlindBoxView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: OstrichSpacing.m),
        count: 4
    )

    var body: some View {
        VStack(spacing: OstrichSpacing.l) {
            VStack(spacing: OstrichSpacing.s) {
                Text("16 个蛋")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text("你不知道你会遇到谁。这是缘分。")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
            }
            .padding(.top, OstrichSpacing.xl)

            LazyVGrid(columns: columns, spacing: OstrichSpacing.m) {
                ForEach(EggCatalog.all) { egg in
                    EggCell(egg: egg, isSelected: coordinator.selectedEgg?.eggType == egg.eggType)
                        .onTapGesture {
                            coordinator.selectEgg(egg)
                        }
                }
            }
            .padding(.horizontal, OstrichSpacing.l)

            Spacer()

            OstrichButton("就是它") {
                coordinator.next()
            }
            .opacity(coordinator.selectedEgg == nil ? 0.35 : 1)
            .disabled(coordinator.selectedEgg == nil)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }
}

/// 蛋视觉：上窄下宽 Bezier 蛋型，主色填充 + 副色斑点 + 呼吸动画。
private struct EggCell: View {
    let egg: EggArchetype
    let isSelected: Bool

    @State private var breath: CGFloat = 1.0

    var body: some View {
        ZStack {
            EggShape()
                .fill(egg.primary)
                .overlay(
                    EggShape()
                        .stroke(
                            isSelected ? OstrichColors.ink : OstrichColors.ink.opacity(0.08),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .overlay(
                    EggSpeckles(color: egg.secondary)
                        .clipShape(EggShape())
                )
                .aspectRatio(0.72, contentMode: .fit)
                .scaleEffect(breath)
        }
        .accessibilityLabel("蛋 \(egg.eggType) \(egg.displayName)")
        .onAppear {
            // 随 eggType 错峰，避免 16 蛋同步呼吸像方阵。
            let delay = Double(egg.eggType % 4) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                ) {
                    breath = 1.03
                }
            }
        }
    }
}

/// 蛋纹斑点：简单 deterministic 三块圆，作为蛋的副色装饰。
private struct EggSpeckles: View {
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
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step4EggBlindBoxView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}
