import SwiftUI

/// Day 1 占位视图。Day 2+ 会被启动相位状态机替换。
/// 参考 docs/BLUEPRINT.md §13.1
///
/// Phase 1 demo 第一眼资产：液态鸵鸟头（WS-B-2 / #10）。
/// 见 `LiquidOstrichHeadView`。
struct RootView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OstrichColors.bodyBackground
                    .ignoresSafeArea()

                LiquidOstrichHeadView(size: min(proxy.size.width, proxy.size.height) * 0.92)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

#Preview {
    RootView()
}
