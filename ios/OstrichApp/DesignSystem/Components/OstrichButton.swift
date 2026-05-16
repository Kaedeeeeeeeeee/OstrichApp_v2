import SwiftUI

/// 鸵鸟主按钮样式。pill 56pt，墨底奶油字，press 弹性缩 0.97。
/// 对齐 v4 HTML `.cta` 定义。
public struct OstrichButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .tracking(0.17) // letter-spacing 0.01em ≈ 0.17pt
            .foregroundStyle(OstrichColors.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: OstrichRadius.pill, style: .continuous)
                    .fill(OstrichColors.ink)
            )
            .shadow(
                color: OstrichColors.ink.opacity(0.4),
                radius: 12,
                x: 0,
                y: 10
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.7),
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}

/// 便捷构造：`OstrichButton("开始") { ... }`
public struct OstrichButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(OstrichButtonStyle())
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        VStack(spacing: OstrichSpacing.l) {
            OstrichButton("开始") {}
            OstrichButton("继续") {}
        }
        .padding(.horizontal, OstrichSpacing.xxl)
    }
}
