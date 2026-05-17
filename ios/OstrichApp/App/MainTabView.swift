// MainTabView.swift
// 5 tab 主结构（BLUEPRINT §13.3）。
// 4 个 placeholder 等 WS-F / WS-G / WS-H / WS-I 接入。

import SwiftUI

struct MainTabView: View {

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

            PlaceholderView(
                title: "传心",
                subtitle: "ChatView · 等 WS-F"
            )
            .tabItem {
                Label("传心", systemImage: "bubble.left.fill")
            }

            PlaceholderView(
                title: "关系图谱",
                subtitle: "GraphView · 等 WS-G"
            )
            .tabItem {
                Label("图谱", systemImage: "point.3.connected.trianglepath.dotted")
            }

            PlaceholderView(
                title: "遛弯",
                subtitle: "WanderView · 等 WS-H"
            )
            .tabItem {
                Label("遛弯", systemImage: "figure.walk")
            }

            PlaceholderView(
                title: "设置",
                subtitle: "SettingsView · 等 WS-I"
            )
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
        .tint(OstrichColors.orange)
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
}
