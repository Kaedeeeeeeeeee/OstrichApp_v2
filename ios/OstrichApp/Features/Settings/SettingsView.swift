// SettingsView.swift
// 设置 tab 列表 + 「如果有一天我不在了」入口（DEMO_SCRIPT 04:40-05:00）。
// BLUEPRINT §12 三种处置 → IfImGoneView。

import SwiftUI

public struct SettingsView: View {

    @State private var showComingSoon = false
    @State private var comingSoonMessage = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                OstrichColors.bodyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OstrichSpacing.m) {
                        section(title: "鸵鸟") {
                            row(
                                icon: "book.closed.fill",
                                title: "鸵鸟之书",
                                subtitle: "回忆与记录",
                                enabled: false
                            ) {
                                comingSoonMessage = "鸵鸟之书还在写。"
                                showComingSoon = true
                            }

                            row(
                                icon: "globe",
                                title: "鸵鸟的世界",
                                subtitle: "看看其他鸵鸟",
                                enabled: false
                            ) {
                                comingSoonMessage = "鸵鸟世界还在搭建。"
                                showComingSoon = true
                            }
                        }

                        section(title: "终章") {
                            NavigationLink {
                                IfImGoneView()
                            } label: {
                                rowContent(
                                    icon: "leaf.fill",
                                    title: "如果有一天我不在了",
                                    subtitle: "三种安排",
                                    enabled: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        section(title: "应用") {
                            row(
                                icon: "info.circle.fill",
                                title: "关于鸵鸟",
                                subtitle: "v0.1.0",
                                enabled: true
                            ) {
                                comingSoonMessage = "鸵鸟 v0.1.0 · 见 BLUEPRINT。"
                                showComingSoon = true
                            }

                            row(
                                icon: "rectangle.portrait.and.arrow.right",
                                title: "退出登录",
                                subtitle: nil,
                                enabled: true,
                                tint: OstrichColors.orangeDeep
                            ) {
                                comingSoonMessage = "退出登录功能开发中。"
                                showComingSoon = true
                            }
                        }
                    }
                    .padding(.horizontal, OstrichSpacing.l)
                    .padding(.vertical, OstrichSpacing.l)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(OstrichColors.cream, for: .navigationBar)
            .alert("功能开发中", isPresented: $showComingSoon) {
                Button("好") {}
            } message: {
                Text(comingSoonMessage)
            }
        }
    }

    // MARK: - Builders

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OstrichSpacing.s) {
            Text(title)
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
                .padding(.horizontal, OstrichSpacing.s)
            VStack(spacing: OstrichSpacing.s) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(
        icon: String,
        title: String,
        subtitle: String?,
        enabled: Bool,
        tint: Color = OstrichColors.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(
                icon: icon,
                title: title,
                subtitle: subtitle,
                enabled: enabled,
                tint: tint
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.45)
    }

    @ViewBuilder
    private func rowContent(
        icon: String,
        title: String,
        subtitle: String?,
        enabled: Bool,
        tint: Color = OstrichColors.ink
    ) -> some View {
        OstrichCard {
            HStack(spacing: OstrichSpacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OstrichTypography.body)
                        .foregroundStyle(tint)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(OstrichTypography.caption)
                            .foregroundStyle(OstrichColors.ink.opacity(0.5))
                    }
                }
                Spacer()
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OstrichColors.ink.opacity(0.3))
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
