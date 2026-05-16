import SwiftUI

/// Day 1 占位视图。Day 2+ 会被启动相位状态机替换。
/// 参考 docs/BLUEPRINT.md §13.1
struct RootView: View {
    var body: some View {
        ZStack {
            Color(red: 0xDB / 255.0, green: 0xD3 / 255.0, blue: 0xB8 / 255.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("鸵鸟")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color(red: 0x27 / 255.0, green: 0x28 / 255.0, blue: 0x1D / 255.0))

                Text("Phase 1 · Day 1 脚手架")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color(red: 0x27 / 255.0, green: 0x28 / 255.0, blue: 0x1D / 255.0).opacity(0.6))
            }
        }
    }
}

#Preview {
    RootView()
}
