// DiaryViewModel.swift
// 日记 timeline + requestUnlock。
// INTERFACES.md §1.5 + DEMO_SCRIPT 04:00-04:40。

import Foundation
import SwiftUI

@MainActor
public final class DiaryViewModel: ObservableObject {

    @Published public var entries: [DiaryEntryDTO] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    /// entryId → 最近一次 unlock 请求的 UI 状态。
    @Published public var unlockStates: [String: DiaryUnlockUIState] = [:]

    private let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    /// 拉历史。下拉刷新或进入页面时调。
    public func loadEntries() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: DiaryListResponseDTO = try await client.get(
                Endpoints.diary,
                query: [URLQueryItem(name: "limit", value: "20")]
            )
            entries = response.entries
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 请求解锁某条 redacted 日记。
    public func requestUnlock(_ entry: DiaryEntryDTO) async {
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

    public func unlockState(for entry: DiaryEntryDTO) -> DiaryUnlockUIState {
        unlockStates[entry.id] ?? .idle
    }
}
