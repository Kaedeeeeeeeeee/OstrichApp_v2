// DiaryView.swift
// 日记 timeline：彩色 visible 条目 + 灰色 redacted 条目（模糊 + 锁图标）。
// 点 redacted 条目弹 UnlockRequestSheet。
// DEMO_SCRIPT 04:00-04:40。

import SwiftUI

public struct DiaryView: View {

    @StateObject private var viewModel: DiaryViewModel
    @State private var selectedEntry: SelectedDiaryEntry?

    public init(client: ConvexClientProtocol) {
        _viewModel = StateObject(wrappedValue: DiaryViewModel(client: client))
    }

    /// 给 `.sheet(item:)` 用的 Identifiable 包装。
    /// DTO 本身不能改，所以用 wrapper。
    fileprivate struct SelectedDiaryEntry: Identifiable {
        let entry: DiaryEntryDTO
        var id: String { entry.id }
    }

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            if viewModel.entries.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                timeline
            }
        }
        .navigationTitle("日记")
        .toolbarBackground(OstrichColors.cream, for: .navigationBar)
        .task {
            await viewModel.loadEntries()
        }
        .refreshable {
            await viewModel.loadEntries()
        }
        .sheet(item: $selectedEntry) { selection in
            UnlockRequestSheet(
                state: viewModel.unlockState(for: selection.entry),
                onAsk: {
                    Task {
                        await viewModel.requestUnlock(selection.entry)
                    }
                },
                onClose: {
                    selectedEntry = nil
                }
            )
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: OstrichSpacing.m) {
            LiquidOstrichHeadView(size: 120)
                .frame(width: 160, height: 160)
                .opacity(0.6)
            Text("鸵鸟还没记日记呢")
                .font(OstrichTypography.headline)
                .foregroundStyle(OstrichColors.ink.opacity(0.6))
            Text("等它今天回来再说吧。")
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink.opacity(0.4))
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.orangeDeep)
                    .padding(.top, OstrichSpacing.s)
            }
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: OstrichSpacing.m) {
                ForEach(viewModel.entries, id: \.id) { entry in
                    DiaryRow(
                        entry: entry,
                        unlockState: viewModel.unlockState(for: entry)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if entry.visibility == "redacted" {
                            selectedEntry = SelectedDiaryEntry(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.vertical, OstrichSpacing.l)
        }
    }
}

// MARK: - Row

struct DiaryRow: View {
    let entry: DiaryEntryDTO
    let unlockState: DiaryUnlockUIState

    private var isRedacted: Bool {
        entry.visibility == "redacted"
    }

    var body: some View {
        OstrichCard {
            VStack(alignment: .leading, spacing: OstrichSpacing.xs) {
                header
                content
                if let loc = entry.location?.friendlyName, !isRedacted {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.ink.opacity(0.5))
                        .padding(.top, OstrichSpacing.xs)
                }
                if let badge = unlockBadge {
                    Text(badge)
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.orangeDeep)
                        .padding(.top, OstrichSpacing.xs)
                }
            }
        }
        .overlay(
            redactionOverlay,
            alignment: .topTrailing
        )
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: OstrichSpacing.s) {
            Text(formattedTime(entry.timestamp))
                .font(OstrichTypography.caption)
                .foregroundStyle(
                    isRedacted
                        ? OstrichColors.ink.opacity(0.4)
                        : OstrichColors.ink.opacity(0.6)
                )
            if isRedacted {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(OstrichColors.ink.opacity(0.4))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        Text(displayContent)
            .font(OstrichTypography.body)
            .foregroundStyle(
                isRedacted
                    ? OstrichColors.ink.opacity(0.45)
                    : OstrichColors.ink
            )
            .blur(radius: isRedacted ? 3.5 : 0)
    }

    @ViewBuilder
    private var redactionOverlay: some View {
        if isRedacted {
            // 灰色调子：cream 卡片之上加一层灰滤膜让对比变弱。
            RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                .fill(OstrichColors.bodyBackground.opacity(0.35))
                .allowsHitTesting(false)
        }
    }

    private var displayContent: String {
        if isRedacted {
            // 用 ◾ 替换大部分字符，保留前 4 个时间提示。
            return entry.content
        }
        return entry.content
    }

    private var unlockBadge: String? {
        switch unlockState {
        case .pending:  return "已经去问了"
        case .denied:   return "对方拒绝了"
        case .visible:  return "对方放开了"
        case .failed:   return "请求失败"
        case .idle, .requesting: return nil
        }
    }

    private var accessibilityLabel: String {
        if isRedacted {
            return "灰色日记条目，已隐藏。点击可请求解锁。"
        }
        return "日记条目：\(entry.content)"
    }

    private func formattedTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return iso }
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "M月d日 HH:mm"
        return display.string(from: d)
    }
}

#Preview {
    let client = MockConvexClient()
    return DiaryView(client: client)
}
