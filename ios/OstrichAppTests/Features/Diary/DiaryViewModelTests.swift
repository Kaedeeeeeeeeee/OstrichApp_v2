// DiaryViewModelTests.swift
// 验证 loadEntries / requestUnlock + DiaryRow visibility 处理。

import Foundation
import Testing
@testable import OstrichApp

@MainActor
struct DiaryViewModelTests {

    @Test func loadEntriesPopulatesList() async {
        let mock = MockConvexClient()
        let entries = [
            DiaryEntryDTO(
                id: "d1",
                timestamp: "2026-05-17T10:23:00Z",
                content: "上午 10:23 在涩谷见到了飒飒",
                visibility: "visible",
                location: DiaryLocationDTO(
                    lat: 35.66,
                    lng: 139.70,
                    friendlyName: "涩谷",
                    lookAroundAvailable: true
                )
            ),
            DiaryEntryDTO(
                id: "d2",
                timestamp: "2026-05-17T13:45:00Z",
                content: "13:45 在 ◾◾◾ 和 ◾◾◾ 的鸵鸟有了一场很特别的对话",
                visibility: "redacted",
                redactionReason: "另一只鸵鸟主人未授权"
            )
        ]
        // path 带 query → MockConvexClient.get 会拼成完整字符串
        mock.stub(
            path: Endpoints.diary + "?limit=20",
            response: DiaryListResponseDTO(entries: entries)
        )

        let vm = DiaryViewModel(client: mock)
        await vm.loadEntries()

        #expect(vm.entries.count == 2)
        #expect(vm.entries.last?.visibility == "redacted")
    }

    @Test func loadEntriesSurfacesError() async {
        let mock = MockConvexClient()
        mock.stubError(
            path: Endpoints.diary + "?limit=20",
            error: .claudeUnavailable
        )
        let vm = DiaryViewModel(client: mock)
        await vm.loadEntries()
        #expect(vm.entries.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - requestUnlock

    @Test func requestUnlockPendingState() async {
        let mock = MockConvexClient()
        mock.stub(
            path: Endpoints.requestUnlock,
            response: DiaryUnlockResponseDTO(status: "pending")
        )
        let vm = DiaryViewModel(client: mock)
        let entry = DiaryEntryDTO(
            id: "d2",
            timestamp: "2026-05-17T13:45:00Z",
            content: "灰色条目",
            visibility: "redacted"
        )
        await vm.requestUnlock(entry)
        #expect(vm.unlockState(for: entry) == .pending)
    }

    @Test func requestUnlockDeniedState() async {
        let mock = MockConvexClient()
        mock.stub(
            path: Endpoints.requestUnlock,
            response: DiaryUnlockResponseDTO(status: "denied")
        )
        let vm = DiaryViewModel(client: mock)
        let entry = DiaryEntryDTO(
            id: "d3",
            timestamp: "2026-05-17T13:45:00Z",
            content: "灰色",
            visibility: "redacted"
        )
        await vm.requestUnlock(entry)
        #expect(vm.unlockState(for: entry) == .denied)
    }

    @Test func requestUnlockFailureCaptured() async {
        let mock = MockConvexClient()
        mock.stubError(
            path: Endpoints.requestUnlock,
            error: .rateLimited
        )
        let vm = DiaryViewModel(client: mock)
        let entry = DiaryEntryDTO(
            id: "d4",
            timestamp: "x",
            content: "x",
            visibility: "redacted"
        )
        await vm.requestUnlock(entry)
        if case .failed = vm.unlockState(for: entry) {
            #expect(Bool(true))
        } else {
            Issue.record("expected .failed state")
        }
    }

    // MARK: - DiaryView smoke

    @Test func diaryViewInstantiates() {
        let view = DiaryView(client: MockConvexClient())
        _ = view.body
    }
}
