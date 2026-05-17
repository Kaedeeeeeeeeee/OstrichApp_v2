// DiaryModels.swift
// 日记请求体（INTERFACES §1.5）+ unlock 状态文案。

import Foundation

/// `/api/diary/requestUnlock` body。
public struct DiaryUnlockRequest: Encodable {
    public let diaryEntryId: String

    public init(diaryEntryId: String) {
        self.diaryEntryId = diaryEntryId
    }
}

/// 请求解锁后的 UI 状态。
public enum DiaryUnlockUIState: Equatable {
    case idle
    case requesting
    case pending          // status == "pending"
    case denied           // status == "denied"
    case visible          // status == "auto_visible"
    case failed(String)
}
