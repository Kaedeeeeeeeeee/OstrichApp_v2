// DiaryViewModel.swift
// 日记 timeline + requestUnlock。
// INTERFACES.md §1.5 + DEMO_SCRIPT 04:00-04:40。
//
// v2 改造：从单一 diary entries 改成聚合 timeline（diary + thought + visited），
// 接 GET /api/diary/timeline。原来的 entries (DiaryEntryDTO) 字段保留给 unlock
// 流程内部用——unlock 还是按 diaryEntryId 操作，从 timeline 里的 kind="diary"
// 条目映射回去。

import Foundation
import SwiftUI

@MainActor
public final class DiaryViewModel: ObservableObject {

    /// 聚合时间线条目（含 diary / thought / visited 三类）。DiaryView 主数据源。
    @Published public var timelineEntries: [TimelineEntryDTO] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    /// diaryEntryId → 最近一次 unlock 请求的 UI 状态。
    @Published public var unlockStates: [String: DiaryUnlockUIState] = [:]

    private let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    /// 拉聚合时间线。下拉刷新或进入页面时调。
    public func loadEntries() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: DiaryTimelineResponseDTO = try await client.get(
                Endpoints.diaryTimeline,
                query: [URLQueryItem(name: "limit", value: "80")]
            )
            timelineEntries = response.entries
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 请求解锁某条 redacted 日记。entry 是 timeline 里 kind="diary" 的条目。
    public func requestUnlock(_ entry: TimelineEntryDTO) async {
        unlockStates[entry.id] = .requesting
        let body = DiaryUnlockRequest(diaryEntryId: entry.id)
        do {
            let response: DiaryUnlockResponseDTO = try await client.call(
                Endpoints.requestUnlock, body: body
            )
            switch response.status {
            case "pending":      unlockStates[entry.id] = .pending
            case "denied":       unlockStates[entry.id] = .denied
            case "auto_visible": unlockStates[entry.id] = .visible
            default:             unlockStates[entry.id] = .pending
            }
        } catch let err as ConvexError {
            unlockStates[entry.id] = .failed(err.errorDescription ?? "请求失败")
        } catch {
            unlockStates[entry.id] = .failed(error.localizedDescription)
        }
    }

    public func unlockState(for entry: TimelineEntryDTO) -> DiaryUnlockUIState {
        unlockStates[entry.id] ?? .idle
    }
}
