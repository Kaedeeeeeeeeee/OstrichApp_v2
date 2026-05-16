import SwiftUI

/// 步骤指示器。对齐 v4 HTML `.page-dots`：18×4 圆角 2；active 24×4，opacity 0.18 → 0.7。
public struct PageDots: View {
    public let total: Int
    public let current: Int

    public init(total: Int, current: Int) {
        self.total = total
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 0), id: \.self) { idx in
                let isActive = idx == current
                Capsule(style: .continuous)
                    .fill(OstrichColors.ink)
                    .opacity(isActive ? 0.7 : 0.18)
                    .frame(width: isActive ? 24 : 18, height: 4)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(current + 1) 步，共 \(total) 步")
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        VStack(spacing: OstrichSpacing.xl) {
            PageDots(total: 9, current: 0)
            PageDots(total: 9, current: 3)
            PageDots(total: 9, current: 8)
        }
    }
}
