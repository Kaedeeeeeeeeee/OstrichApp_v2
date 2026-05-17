// PersonDetailSheet.swift
// 关系图谱节点点击 → 底部弹层。展示 PersonDTO 关键字段 + "在传心室聊关于 ta" 主按钮。
// Phase 1：进入 person_room 暂未实装（issue #24 反对模式：不做 Chat），按钮显示提示。

import SwiftUI

public struct PersonDetailSheet: View {

    let person: PersonDTO

    /// 用户点 CTA 时调用，由外部决定是跳路由还是弹 alert。
    let onOpenRoom: () -> Void

    public init(person: PersonDTO, onOpenRoom: @escaping () -> Void) {
        self.person = person
        self.onOpenRoom = onOpenRoom
    }

    private var category: GraphCategory { GraphCategory.from(person.category) }

    public var body: some View {
        VStack(alignment: .leading, spacing: OstrichSpacing.l) {

            // 顶部：名字 + 分类 chip
            HStack(alignment: .center, spacing: OstrichSpacing.m) {
                Circle()
                    .fill(category.fillColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().strokeBorder(category.strokeColor, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(OstrichTypography.title)
                        .foregroundStyle(OstrichColors.ink)
                    Text(category.displayLabel)
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.55))
                }
                Spacer()
            }

            // 亲密度条
            VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                HStack {
                    Text("亲密度")
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.6))
                    Spacer()
                    Text(closenessLabel)
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink)
                }
                closenessBar
            }

            // 最近互动
            HStack(spacing: OstrichSpacing.s) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(OstrichColors.orange)
                Text("最近聊到 \(person.recentInteractionCount) 次")
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.75))
            }

            // notes（鸵鸟攒下来的一句话总结）
            if !person.notes.isEmpty {
                Text(person.notes)
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.85))
                    .padding(OstrichSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OstrichColors.cream)
                    .clipShape(RoundedRectangle(cornerRadius: OstrichRadius.medium, style: .continuous))
            }

            Spacer(minLength: 0)

            // CTA pill
            Button(action: onOpenRoom) {
                HStack {
                    Spacer()
                    Text("在传心室聊关于 ta")
                        .font(OstrichTypography.headline)
                        .foregroundStyle(OstrichColors.cream)
                    Spacer()
                }
                .padding(.vertical, OstrichSpacing.m)
                .background(OstrichColors.ink)
                .clipShape(RoundedRectangle(cornerRadius: OstrichRadius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开关于 \(person.name) 的传心室")
        }
        .padding(OstrichSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OstrichColors.bodyBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 私有渲染

    private var closenessLabel: String {
        let pct = Int((max(0, min(1, person.closeness)) * 100).rounded())
        return "\(pct)%"
    }

    @ViewBuilder
    private var closenessBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(OstrichColors.ink.opacity(0.12))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(category.fillColor)
                    .frame(
                        width: geo.size.width * CGFloat(max(0, min(1, person.closeness)))
                    )
            }
        }
        .frame(height: 8)
    }
}

#Preview {
    PersonDetailSheet(
        person: PersonDTO(
            id: "p_mom",
            name: "妈妈",
            aliases: ["妈"],
            category: "family",
            closeness: 0.82,
            recentInteractionCount: 14,
            notes: "最近聊得多，但你说有点窒息。",
            hasOstrich: false,
            lastMentionedAt: "2026-05-17T10:00:00Z"
        ),
        onOpenRoom: {}
    )
}
