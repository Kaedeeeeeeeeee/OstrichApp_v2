// HomeView.swift
// 主 Tab 第一屏：液态鸵鸟 hero + 三个入口卡片 + 传心 CTA。
// 见 BLUEPRINT §13.3。

import SwiftUI

struct HomeView: View {

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

                    OstrichButton("传心") {
                        // demo 阶段不实际跳转；后续 WS-F 接入主传心室。
                    }
                    .padding(.horizontal, OstrichSpacing.xxl)
                    .padding(.bottom, OstrichSpacing.xxl)
                }
            }
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeView.formattedDate())
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink)
                Text("今天东京晴 23°")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
            }
            Spacer()
            Text("在一起 1 天")
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink.opacity(0.8))
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(
                    Capsule().fill(OstrichColors.cream)
                )
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
            entryCard(icon: "book.closed.fill", label: "日记")
            entryCard(icon: "point.3.connected.trianglepath.dotted", label: "图谱")
            entryCard(icon: "figure.walk", label: "遛弯")
        }
    }

    private func entryCard(icon: String, label: String) -> some View {
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

    // MARK: - Helpers

    private static func formattedDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

#Preview {
    HomeView()
}
