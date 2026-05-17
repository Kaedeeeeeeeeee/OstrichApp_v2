// DiaryView.swift
// 日记 timeline：聚合 diary + thought + visited 三类条目。
//
// - diary  (visible/redacted) → 卡片 + 灰色态可点弹 UnlockRequestSheet
// - thought                   → 云气泡 icon + 鸵鸟头顶那一刻的内心独白
// - visited                   → 地点 icon + POI 名 ("到达 X")
//
// DEMO_SCRIPT 04:00-04:40。

import SwiftUI

public struct DiaryView: View {

    @StateObject private var viewModel: DiaryViewModel
    @State private var selectedDiaryEntry: TimelineEntryDTO?

    public init(client: ConvexClientProtocol) {
        _viewModel = StateObject(wrappedValue: DiaryViewModel(client: client))
    }

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            if viewModel.timelineEntries.isEmpty && !viewModel.isLoading {
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
        .sheet(item: $selectedDiaryEntry) { selection in
            UnlockRequestSheet(
                state: viewModel.unlockState(for: selection),
                onAsk: {
                    Task { await viewModel.requestUnlock(selection) }
                },
                onClose: {
                    selectedDiaryEntry = nil
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
            Text("鸵鸟还没记下什么呢")
                .font(OstrichTypography.headline)
                .foregroundStyle(OstrichColors.ink.opacity(0.6))
            Text("出去溜达几趟它就有故事了。")
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
                ForEach(viewModel.timelineEntries) { entry in
                    timelineCell(for: entry)
                }
            }
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.vertical, OstrichSpacing.l)
        }
    }

    @ViewBuilder
    private func timelineCell(for entry: TimelineEntryDTO) -> some View {
        switch entry.kind {
        case "diary":
            DiaryCell(entry: entry, unlockState: viewModel.unlockState(for: entry))
                .contentShape(Rectangle())
                .onTapGesture {
                    if entry.visibility == "redacted" {
                        selectedDiaryEntry = entry
                    }
                }
        case "visited":
            VisitedCell(entry: entry)
        case "thought":
            ThoughtCell(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Diary Cell (来自 diary_entries 表，可能 redacted)

struct DiaryCell: View {
    let entry: TimelineEntryDTO
    let unlockState: DiaryUnlockUIState

    private var isRedacted: Bool { entry.visibility == "redacted" }

    var body: some View {
        OstrichCard {
            VStack(alignment: .leading, spacing: OstrichSpacing.xs) {
                header
                Text(entry.content ?? "")
                    .font(OstrichTypography.body)
                    .foregroundStyle(
                        isRedacted ? OstrichColors.ink.opacity(0.45) : OstrichColors.ink
                    )
                    .blur(radius: isRedacted ? 3.5 : 0)
                if let loc = entry.locationName, !loc.isEmpty, !isRedacted {
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
        .overlay(redactionOverlay, alignment: .topTrailing)
        .accessibilityLabel(
            isRedacted ? "灰色日记条目，已隐藏。点击可请求解锁。" : "日记：\(entry.content ?? "")"
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: OstrichSpacing.s) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OstrichColors.orangeDeep.opacity(0.8))
            Text(formattedTime(entry.timestamp))
                .font(OstrichTypography.caption)
                .foregroundStyle(
                    isRedacted ? OstrichColors.ink.opacity(0.4) : OstrichColors.ink.opacity(0.6)
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
    private var redactionOverlay: some View {
        if isRedacted {
            RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                .fill(OstrichColors.bodyBackground.opacity(0.35))
                .allowsHitTesting(false)
        }
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
}

// MARK: - Visited Cell (合成自 thoughts 的 locationName 变化点)

struct VisitedCell: View {
    let entry: TimelineEntryDTO

    var body: some View {
        HStack(spacing: OstrichSpacing.m) {
            ZStack {
                Circle()
                    .fill(OstrichColors.cream)
                    .frame(width: 36, height: 36)
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OstrichColors.orangeDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("到了 \(entry.locationName ?? "")")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink)
                Text(formattedTime(entry.timestamp))
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, OstrichSpacing.m)
        .padding(.vertical, OstrichSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                .fill(OstrichColors.cream.opacity(0.5))
        )
        .accessibilityLabel("鸵鸟到了 \(entry.locationName ?? "未知地点")")
    }
}

// MARK: - Thought Cell (来自 ostrich_thoughts，头顶气泡历史)

struct ThoughtCell: View {
    let entry: TimelineEntryDTO

    var body: some View {
        HStack(alignment: .top, spacing: OstrichSpacing.m) {
            ZStack {
                Circle()
                    .fill(OstrichColors.cream)
                    .frame(width: 36, height: 36)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content ?? "")
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.85))
                    .italic()
                HStack(spacing: OstrichSpacing.xs) {
                    if let loc = entry.locationName, !loc.isEmpty {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(loc)
                            .font(OstrichTypography.caption)
                    }
                    Text(formattedTime(entry.timestamp))
                        .font(OstrichTypography.caption)
                }
                .foregroundStyle(OstrichColors.ink.opacity(0.45))
            }
            Spacer()
        }
        .padding(.horizontal, OstrichSpacing.m)
        .padding(.vertical, OstrichSpacing.s)
        .accessibilityLabel("鸵鸟的想法：\(entry.content ?? "")")
    }
}

// MARK: - Helpers

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

#Preview {
    DiaryView(client: MockConvexClient())
}
