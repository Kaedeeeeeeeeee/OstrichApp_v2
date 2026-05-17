// LocalViewView.swift
// 局域视角 overlay：顶栏（返回 + activity 标签）+ speechBubble + Look Around 按钮 + 底部双按钮。
//
// 重构后职责（v3）：只渲染 UI overlay。
//   - 地图由 WanderView 持有的共享 OstrichMapView 渲染（无需自己 import MapKit）。
//   - 数据（destinationName/category/reason/activity/isLoadingRoute）由 WanderView 维护并传入。
//   - 按钮 action 通过 callback 上报。
//   - Look Around sheet 由 WanderView 持有。
//
// speechBubble 状态机（按 activityLabel + isLoadingRoute 分发）：
//   1. isLoadingRoute → spinner + "ta 在想去哪儿…"
//   2. activity="walking" + 有 destinationName + reason
//        → "想去 [名]"\n[reason]   （鸵鸟的目的地 + 解释）
//   3. activity in {resting, exploring, socializing} + 有 destinationName
//        → "在 [名] [verb]" + 动画点点     （鸵鸟到了，正在体验）
//        verb 由 destinationCategory 经 LocalActivityVerb 推出来
//   4. 兜底 → "在附近转转…"

import SwiftUI

struct LocalViewView: View {

    let destinationName: String?
    let destinationCategory: String?
    let reason: String?
    let activityLabel: String
    let isLoadingRoute: Bool
    let inFlightAction: Bool
    let onBackToGod: () -> Void
    let onCallHome: () -> Void
    let onAllowToStay: () -> Void
    let onLookAround: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.top, OstrichSpacing.s)
            speechBubble
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.top, OstrichSpacing.s)
            Spacer()
            lookAroundCallout
                .padding(.bottom, OstrichSpacing.s)
            bottomBar
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.bottom, OstrichSpacing.xl)
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button(action: onBackToGod) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上帝视角")
                }
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink)
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(
                    Capsule().fill(OstrichColors.cream.opacity(0.95))
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            Spacer()
            if !activityLabel.isEmpty {
                Text(activityLabel)
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink)
                    .padding(.horizontal, OstrichSpacing.m)
                    .padding(.vertical, OstrichSpacing.xs)
                    .background(
                        Capsule().fill(OstrichColors.cream.opacity(0.95))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }

    /// activityLabel 是否表示鸵鸟到了某个 POI 在体验（resting / exploring / socializing）。
    /// walking 是"在路上"，跟到达后的"在 X 干 Y"是两种文案。
    private var isAtPlace: Bool {
        let v = activityLabel.lowercased()
        return v == "resting" || v == "exploring" || v == "socializing"
    }

    @ViewBuilder
    private var speechBubble: some View {
        OstrichCard {
            if isLoadingRoute {
                HStack(spacing: OstrichSpacing.s) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("ta 在想去哪儿…")
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.7))
                }
            } else if isAtPlace, let name = destinationName, !name.isEmpty {
                // 到了：在 X [verb] ●●●
                let verb = LocalActivityVerb.verb(for: destinationCategory)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    (
                        Text("在 ")
                            .foregroundStyle(OstrichColors.ink.opacity(0.55))
                        + Text(name)
                            .foregroundStyle(OstrichColors.ink)
                            .fontWeight(.semibold)
                        + Text(" \(verb)")
                            .foregroundStyle(OstrichColors.ink.opacity(0.85))
                    )
                    .font(OstrichTypography.callout)
                    .lineLimit(2)
                    LocalAnimatedDots()
                        .padding(.leading, 6)
                        .padding(.bottom, 2)
                }
            } else if let name = destinationName, let r = reason, !name.isEmpty, !r.isEmpty {
                // 走路：想去 X / [reason]
                VStack(alignment: .leading, spacing: OstrichSpacing.xs) {
                    Text("想去")
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.ink.opacity(0.5))
                    Text(name)
                        .font(OstrichTypography.body)
                        .fontWeight(.bold)
                        .foregroundStyle(OstrichColors.ink)
                    Text(r)
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.75))
                }
            } else {
                Text("在附近转转…")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.6))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var lookAroundCallout: some View {
        Button(action: onLookAround) {
            HStack(spacing: OstrichSpacing.s) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("想看看这里长什么样吗？")
                    .font(OstrichTypography.callout)
            }
            .foregroundStyle(OstrichColors.ink)
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.vertical, OstrichSpacing.s)
            .background(
                Capsule().fill(OstrichColors.cream.opacity(0.95))
            )
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
    }

    private var bottomBar: some View {
        // 在 loading（鸵鸟还没决策出第一段路）时禁用召回相关按钮，
        // 避免用户在鸵鸟"没出门"前就召回，造成后端状态错位。
        let buttonsDisabled = inFlightAction || isLoadingRoute
        return HStack(spacing: OstrichSpacing.m) {
            Button(action: onAllowToStay) {
                Text("让 ta 继续玩")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OstrichColors.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule().fill(OstrichColors.cream)
                    )
                    .opacity(buttonsDisabled ? 0.5 : 1)
            }
            .disabled(buttonsDisabled)

            Button(action: onCallHome) {
                Text("叫回家")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OstrichColors.cream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule().fill(OstrichColors.ink)
                    )
                    .opacity(buttonsDisabled ? 0.5 : 1)
            }
            .disabled(buttonsDisabled)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - 动画点点（"在 X 干 Y..." 后面那三个会动的点）
//
// 3 个圆点 opacity 波纹：每个相位错开 0.18s，整体呈 "1 2 3 1 2 3..." 流动感。
// 用 opacity（而非 y-offset）—— 不影响行高，能干净地与 baseline 文字混排。

private struct LocalAnimatedDots: View {

    @State private var animating: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(OstrichColors.ink.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .opacity(animating ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

#Preview("loading") {
    ZStack {
        Color.gray.ignoresSafeArea()
        LocalViewView(
            destinationName: nil,
            destinationCategory: nil,
            reason: nil,
            activityLabel: "resting",
            isLoadingRoute: true,
            inFlightAction: false,
            onBackToGod: {},
            onCallHome: {},
            onAllowToStay: {},
            onLookAround: {}
        )
    }
}

#Preview("walking intention") {
    ZStack {
        Color.gray.ignoresSafeArea()
        LocalViewView(
            destinationName: "%%% Coffee 表参道店",
            destinationCategory: "Cafe",
            reason: "听说他们今天有新的肉桂拿铁",
            activityLabel: "walking",
            isLoadingRoute: false,
            inFlightAction: false,
            onBackToGod: {},
            onCallHome: {},
            onAllowToStay: {},
            onLookAround: {}
        )
    }
}

#Preview("at place · cafe") {
    ZStack {
        Color.gray.ignoresSafeArea()
        LocalViewView(
            destinationName: "Sigourny Bake & Coffee",
            destinationCategory: "Cafe",
            reason: "听说他们今天有新的肉桂拿铁",
            activityLabel: "resting",
            isLoadingRoute: false,
            inFlightAction: false,
            onBackToGod: {},
            onCallHome: {},
            onAllowToStay: {},
            onLookAround: {}
        )
    }
}

#Preview("at place · park") {
    ZStack {
        Color.gray.ignoresSafeArea()
        LocalViewView(
            destinationName: "新宿御苑",
            destinationCategory: "Park",
            reason: "想看看树",
            activityLabel: "resting",
            isLoadingRoute: false,
            inFlightAction: false,
            onBackToGod: {},
            onCallHome: {},
            onAllowToStay: {},
            onLookAround: {}
        )
    }
}
