// GodViewView.swift
// 上帝视角 overlay：顶部 caption（含鸵鸟当前目标）+ 底部「召回我的鸵鸟」按钮。
//
// 重构后职责（v3）：只渲染 UI overlay。
//   - 地图由 WanderView 持有的共享 OstrichMapView 渲染。
//   - 数据（ostrichCount / destinationName）由 WanderView 维护并传入。
//   - 按 onRecall callback 通知父切到 local 视角。
//
// caption 三层：
//   - 主：附近鸵鸟数
//   - 副：上帝视角
//   - 当鸵鸟有 currentIntention 时再加一行：我的鸵鸟正在去 [POI 名]

import SwiftUI

struct GodViewView: View {

    let ostrichCount: Int
    let destinationName: String?
    let onRecall: () -> Void
    /// 右上角日记按钮回调。点击进入 DiaryView 看鸵鸟去过哪 / 想过啥 / 遇见过谁。
    let onOpenDiary: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                topCaption
                    .padding(.top, OstrichSpacing.xl)
                Spacer()
                recallButton
                    .padding(.horizontal, OstrichSpacing.xxl)
                    .padding(.bottom, OstrichSpacing.xxl + 8)
            }
            HStack {
                Spacer()
                diaryButton
                    .padding(.trailing, OstrichSpacing.l)
                    .padding(.top, OstrichSpacing.xl)
            }
        }
    }

    private var diaryButton: some View {
        Button(action: onOpenDiary) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OstrichColors.ink)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(OstrichColors.cream.opacity(0.95))
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .accessibilityLabel("打开日记")
    }

    private var topCaption: some View {
        VStack(spacing: OstrichSpacing.xs) {
            Text("附近有 \(ostrichCount) 只鸵鸟在活动")
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink)
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(
                    Capsule().fill(OstrichColors.cream.opacity(0.95))
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Text("上帝视角")
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.55))
                .padding(.horizontal, OstrichSpacing.s)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(OstrichColors.cream.opacity(0.75))
                )
            if let name = destinationName, !name.isEmpty {
                // 鸵鸟有当前目标 → 这里显式告知用户"它现在在做什么"，
                // 让上帝视角也有可读叙事，不只是匿名密度。
                Text("ta 正在去 \(name)")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.75))
                    .padding(.horizontal, OstrichSpacing.m)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(OstrichColors.cream.opacity(0.92))
                    )
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: destinationName)
    }

    private var recallButton: some View {
        OstrichButton("找到") {
            onRecall()
        }
    }
}

#Preview("no intention") {
    ZStack {
        Color.gray.ignoresSafeArea()
        GodViewView(ostrichCount: 24, destinationName: nil, onRecall: {}, onOpenDiary: {})
    }
}

#Preview("with intention") {
    ZStack {
        Color.gray.ignoresSafeArea()
        GodViewView(
            ostrichCount: 24,
            destinationName: "%%% Coffee 表参道店",
            onRecall: {},
            onOpenDiary: {}
        )
    }
}
