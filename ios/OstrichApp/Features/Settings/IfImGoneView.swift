// IfImGoneView.swift
// 「如果有一天我不在了」入口页（BLUEPRINT §12 + DEMO_SCRIPT 04:40-05:00）。
// Demo 阶段只展示三种处置说明，不实现真功能。点击 → 「功能开发中」alert。

import SwiftUI

public struct IfImGoneView: View {

    @State private var alertMessage: String?

    /// 三种处置选项。public 以便单测。
    public enum Disposition: String, CaseIterable, Identifiable {
        case takeAway       // 带它走
        case transfer       // 指定继承
        case release        // 放生

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .takeAway: return "带它走"
            case .transfer: return "指定继承"
            case .release:  return "放生"
            }
        }

        public var subtitle: String {
            switch self {
            case .takeAway: return "封蛋沉睡，一切冻结"
            case .transfer: return "鸵鸟转交给你信任的人"
            case .release:  return "放回鸵鸟世界，去替你说没说出口的话"
            }
        }

        public var detail: String {
            switch self {
            case .takeAway:
                return "鸵鸟会重新回到蛋里，封闭睡去。需要密码才能再唤醒。它见证过的一切都跟着你一起带走。"
            case .transfer:
                return "选一个你信任的人。鸵鸟会带着原有记忆继续陪 ta。你可以选擦掉哪一部分。"
            case .release:
                return "鸵鸟变成鸵鸟世界的 NPC，无主，按你留下的关系图谱去寻找你提过的人，替你转一句话。"
            }
        }

        public var icon: String {
            switch self {
            case .takeAway: return "moon.zzz.fill"
            case .transfer: return "person.line.dotted.person.fill"
            case .release:  return "wind"
            }
        }
    }

    public init() {}

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OstrichSpacing.l) {
                    intro
                        .padding(.top, OstrichSpacing.m)

                    ForEach(Disposition.allCases) { option in
                        dispositionCard(option)
                            .onTapGesture {
                                alertMessage = "「\(option.title)」功能开发中。"
                            }
                    }
                }
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.bottom, OstrichSpacing.xxl)
            }
        }
        .navigationTitle("如果有一天我不在了")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OstrichColors.cream, for: .navigationBar)
        .alert("功能开发中", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: OstrichSpacing.s) {
            Text("你的鸵鸟知道你太多了。")
                .font(OstrichTypography.headline)
                .foregroundStyle(OstrichColors.ink)
            Text("它见证了你的一生。你想怎么安排它？")
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dispositionCard(_ option: Disposition) -> some View {
        OstrichCard {
            VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                HStack(spacing: OstrichSpacing.m) {
                    Image(systemName: option.icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(OstrichColors.ink)
                        .frame(width: 32, height: 32)
                    Text(option.title)
                        .font(OstrichTypography.headline)
                        .foregroundStyle(OstrichColors.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OstrichColors.ink.opacity(0.3))
                }
                Text(option.subtitle)
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.7))
                Text(option.detail)
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
                    .padding(.top, OstrichSpacing.xs)
            }
        }
    }
}

#Preview {
    NavigationStack {
        IfImGoneView()
    }
}
