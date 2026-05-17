// WanderView.swift
// Tab 4 「遛弯」入口。两级视角状态机：上帝 ↔ 局域。
// BLUEPRINT §10.3 + §13.3 + DEMO_SCRIPT 03:00-04:00。
//
// - 默认上帝视角（暗色背景 + 闪烁点）
// - 点 "召回我的鸵鸟" → 切到局域视角（3D 卫星地图 + 鸵鸟图标）
// - 局域视角顶部小按钮可切回上帝视角

import SwiftUI

public enum WanderViewMode: Equatable {
    case god
    case local
}

public struct WanderView: View {

    private let client: ConvexClientProtocol

    @State private var viewMode: WanderViewMode = .god

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    public var body: some View {
        ZStack {
            switch viewMode {
            case .god:
                GodViewView(client: client) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        viewMode = .local
                    }
                }
                .transition(.opacity)
            case .local:
                LocalViewView(client: client) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        viewMode = .god
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    WanderView(client: MockConvexClient())
}
