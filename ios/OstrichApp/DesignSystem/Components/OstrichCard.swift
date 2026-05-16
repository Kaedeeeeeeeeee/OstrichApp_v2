import SwiftUI

/// 通用卡片容器：cream 底 + 圆角 large + padding m。
public struct OstrichCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(OstrichSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                    .fill(OstrichColors.cream)
            )
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        VStack(spacing: OstrichSpacing.l) {
            OstrichCard {
                VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                    Text("今天")
                        .font(OstrichTypography.headline)
                        .foregroundStyle(OstrichColors.ink)
                    Text("鸵鸟看了看你，然后又看了看远方。")
                        .font(OstrichTypography.body)
                        .foregroundStyle(OstrichColors.ink.opacity(0.6))
                }
            }
            OstrichCard {
                Text("一段更短的说明")
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink)
            }
        }
        .padding(.horizontal, OstrichSpacing.xl)
    }
}
