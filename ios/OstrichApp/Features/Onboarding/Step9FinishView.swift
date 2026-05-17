import SwiftUI

/// Step 9: 完成。CTA → 进入主页。
struct Step9FinishView: View {
    let onComplete: () -> Void

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
                onComplete()
            }
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step9FinishView(onComplete: {})
    }
}
