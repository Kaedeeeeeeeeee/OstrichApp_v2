// HomeView.swift
// 主页（也是 App 唯一根视图）：液态鸵鸟 hero + 三个入口卡片 + 传心 CTA + 右上角 Settings 齿轮。
// 不再有底部 TabBar — 所有去处都从这里 NavigationLink push 出去。
// 见 BLUEPRINT §13.3 + Phase 1 demo 反馈。

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var deps: AppDependency
    @StateObject private var weather = WeatherViewModel()

    var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: OstrichSpacing.l) {
                    topBar
                        .padding(.horizontal, OstrichSpacing.xl)
                        .padding(.top, OstrichSpacing.s)

                    LiquidOstrichHeadView(size: 320)
                        .frame(width: 320, height: 320)
                        .padding(.vertical, OstrichSpacing.s)

                    todayReflection
                        .padding(.horizontal, OstrichSpacing.xl)

                    entriesRow
                        .padding(.horizontal, OstrichSpacing.xl)

                    NavigationLink(value: HomeRoute.chat) {
                        chatCTALabel
                    }
                    .padding(.horizontal, OstrichSpacing.xxl)
                    .padding(.bottom, OstrichSpacing.xxl)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeView.formattedDate())
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink)
                Text(weather.displayString)
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
                    .task { await weather.refresh() }
            }
            Spacer()
            Text("在一起 1 天")
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink.opacity(0.8))
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(Capsule().fill(OstrichColors.cream))

            NavigationLink(value: HomeRoute.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(OstrichColors.ink.opacity(0.65))
                    .padding(.leading, OstrichSpacing.s)
            }
            .accessibilityLabel("设置")
        }
    }

    private var todayReflection: some View {
        VStack(alignment: .leading, spacing: OstrichSpacing.xs) {
            Text("鸵鸟今天对你说的话")
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
            Text("今天涩谷有点风，我多走了两站。")
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entriesRow: some View {
        HStack(spacing: OstrichSpacing.m) {
            entryLink(route: .diary, icon: "book.closed.fill", label: "日记")
            entryLink(route: .graph, icon: "point.3.connected.trianglepath.dotted", label: "图谱")
            entryLink(route: .wander, icon: "figure.walk", label: "遛弯")
        }
    }

    private func entryLink(route: HomeRoute, icon: String, label: String) -> some View {
        NavigationLink(value: route) {
            OstrichCard {
                VStack(spacing: OstrichSpacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(OstrichColors.ink)
                    Text(label)
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OstrichSpacing.xs)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 传心 CTA 的视觉（NavigationLink 直接复用 OstrichButton 不好，自己造个 label）。
    private var chatCTALabel: some View {
        Text("传心")
            .font(OstrichTypography.headline)
            .foregroundStyle(OstrichColors.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(OstrichColors.ink))
    }

    // MARK: - Helpers

    private static func formattedDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentObject(AppDependency(client: MockConvexClient()))
}
