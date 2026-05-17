// MainTabView.swift
// 应用主导航容器。
//
// 设计变更：去掉底部 TabBar —— Home 既然能放四个入口卡片 + 传心按钮，
// 五个 tab 就是冗余。Settings 太单薄不值得占一个 tab，移到 Home 右上角齿轮。
//
// 现在结构：
//   NavigationStack { HomeView }
//   HomeView 内部用 NavigationLink(value: HomeRoute) push 到子视图。
//
// 见 BLUEPRINT §13.3（虽然蓝图原本写的 5-tab 结构，根据 demo 真跑反馈调整）。

import SwiftUI

/// Home 出发的 4 + 1 个导航目的地。
public enum HomeRoute: Hashable {
    case chat
    case diary
    case graph
    case wander
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var deps: AppDependency
    @AppStorage("mainOstrichId") private var mainOstrichId: String = ""
    @AppStorage("mainOstrichName") private var mainOstrichName: String = "鸵鸟"
    /// 主传心室 id（chat_rooms 表）。Onboarding 完写入。
    @AppStorage("mainRoomId") private var mainRoomId: String = ""
    /// RootView 在 onboarding 完成时置 true → MainTabView 立刻 push Chat → 用完清空。
    @AppStorage("autoOpenChatOnLaunch") private var autoOpenChatOnLaunch = false
    /// 占位屏读这个错误展示。空串表示无错误。
    @AppStorage("lastAwakenError") private var lastAwakenError: String = ""

    /// NavigationStack 路径状态。
    @State private var path: [HomeRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(for: route)
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
        .tint(OstrichColors.orange)
        .task {
            // Onboarding 完成后第一次进 main：直接打开传心。
            if autoOpenChatOnLaunch {
                autoOpenChatOnLaunch = false
                path = [.chat]
            }
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .chat: chatDestination
        case .diary: DiaryView(client: deps.client)
        case .graph: GraphView(client: deps.client)
        case .wander: WanderView(client: deps.client)
        case .settings: SettingsView()
        }
    }

    /// 传心目的地：roomId 为空（onboarding 未完成或 awaken 失败）时占位。
    @ViewBuilder
    private var chatDestination: some View {
        if mainRoomId.isEmpty {
            ChatEmptyPlaceholder(lastError: lastAwakenError)
        } else {
            ChatView(
                client: deps.client,
                roomId: mainRoomId,
                ostrichName: mainOstrichName.isEmpty ? "鸵鸟" : mainOstrichName
            )
        }
    }
}

/// mainRoomId 为空时显示的占位屏：展示上次 awaken 错误（如果有）+
/// 「重新走一遍 onboarding」按钮（发 .resetOnboarding 通知，RootView 监听）。
private struct ChatEmptyPlaceholder: View {
    let lastError: String

    var body: some View {
        VStack(spacing: OstrichSpacing.l) {
            LiquidOstrichHeadView(size: 160)
                .frame(width: 200, height: 200)

            VStack(spacing: OstrichSpacing.s) {
                Text("鸵鸟还没真正醒过来")
                    .font(OstrichTypography.headline)
                    .foregroundStyle(OstrichColors.ink.opacity(0.65))
                Text("先把后端跑起来 + 走完 onboarding，它才能听见你。")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.xl)

                if !lastError.isEmpty {
                    Text("上次唤醒报错：\(lastError)")
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.orangeDeep)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OstrichSpacing.xl)
                        .padding(.top, OstrichSpacing.xs)
                }
            }

            Button {
                NotificationCenter.default.post(name: .resetOnboarding, object: nil)
            } label: {
                Text("重新走一遍 onboarding")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.cream)
                    .padding(.horizontal, OstrichSpacing.xl)
                    .padding(.vertical, OstrichSpacing.s)
                    .background(Capsule().fill(OstrichColors.ink))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OstrichColors.bodyBackground)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppDependency(client: MockConvexClient()))
}
