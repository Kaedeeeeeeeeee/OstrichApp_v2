// MainTabView.swift
// 5 tab 主结构（BLUEPRINT §13.3）。
// WS-F-1 接入 tab 2 (传心) + tab 5 (设置)。tab 3/4 留给 WS-F-2/WS-F-3。

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var deps: AppDependency
    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"

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
    @ViewBuilder
    private var chatTab: some View {
        if mainOstrichId.isEmpty {
            PlaceholderView(
                title: "传心",
                subtitle: "先完成 onboarding，鸵鸟才能听见你"
            )
        } else {
            ChatView(
                client: deps.client,
                roomId: mainOstrichId,
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
