// MainTabView.swift
// 5 tab 主结构（BLUEPRINT §13.3）。
// WS-F-1 接入 tab 2 (传心) + tab 5 (设置)。tab 3/4 留给 WS-F-2/WS-F-3。

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var deps: AppDependency
    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"
    /// 主传心室 id（chat_rooms 表）。Step9 onboarding 完写入。
    @AppStorage("mainRoomId") private var mainRoomId: String = ""

    init() {
        // 给 TabBar 设浅奶油色底，避免默认半透明灰。
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(OstrichColors.cream)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("鸵鸟今日", systemImage: "house.fill")
                }

            chatTab
                .tabItem {
                    Label("传心", systemImage: "bubble.left.fill")
                }

            GraphView(client: deps.client)
                .tabItem {
                    Label("图谱", systemImage: "point.3.connected.trianglepath.dotted")
                }

            WanderView(client: deps.client)
                .tabItem {
                    Label("遛弯", systemImage: "figure.walk")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
        .tint(OstrichColors.orange)
    }

    // MARK: - Chat tab

    /// roomId 为空（onboarding 还没存）时退化为占位提示。
    /// 注意：传给 ChatView 的是 chat_rooms.id，不是 ostriches.id。
    /// 老用户可能 @AppStorage 里只有 mainOstrichId（来自 #31 旧版），
    /// 缺 mainRoomId 时也走占位 — 实际 demo 时新装的 app 已经会写两个。
    @ViewBuilder
    private var chatTab: some View {
        if mainRoomId.isEmpty {
            PlaceholderView(
                title: "传心",
                subtitle: "先完成 onboarding，鸵鸟才能听见你"
            )
        } else {
            ChatView(
                client: deps.client,
                roomId: mainRoomId,
                ostrichName: mainOstrichName.isEmpty ? "鸵鸟" : mainOstrichName
            )
        }
    }
}

/// 占位视图：液态鸵鸟小图 + 标题 + 副标，作为非 Home tab 在 demo 阶段的展位。
private struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()
            VStack(spacing: OstrichSpacing.l) {
                LiquidOstrichHeadView(size: 160)
                    .frame(width: 200, height: 200)
                Text(title)
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text(subtitle)
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppDependency(client: MockConvexClient()))
}
