// OnboardingCoordinatorTests.swift
// 验证 OnboardingCoordinator：step 状态转移 + awaken/chat 调用流程。

import Foundation
import Testing
@testable import OstrichApp

@MainActor
struct OnboardingCoordinatorTests {

    // MARK: - Step 状态转移

    @Test func initialStepIsWelcome() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        #expect(coordinator.step == .welcome)
    }

    @Test func nextAdvancesStepInOrder() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        let expected: [OnboardingStep] = [
            .mbti, .zodiac, .eggBlindBox, .eggHatch,
            .firstChat, .nameInput, .ostrichResponds, .finish
        ]
        for step in expected {
            coordinator.next()
            #expect(coordinator.step == step)
        }
    }

    @Test func nextAtFinishIsNoop() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        coordinator.goTo(.finish)
        coordinator.next()
        #expect(coordinator.step == .finish)
    }

    @Test func selectionsAreStored() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        #expect(coordinator.selectedMBTI == .INFP)
        #expect(coordinator.selectedZodiac == .cancer)
        #expect(coordinator.selectedEgg?.archetype == "CUDDLER")
    }

    // MARK: - Awaken + chat send 流程

    @Test func awakenCallsConvexThenChatSend() async {
        let mock = MockConvexClient()
        let dto = OstrichDTO(
            id: "ost_123",
            ownerId: "u1",
            name: "柱子",
            eggType: 4,
            archetype: "CUDDLER",
            awakenedAt: "2026-05-17T00:00:00Z",
            state: "awake",
            currentLocation: LocationDTO(lat: 35.6, lng: 139.7, friendlyName: "涩谷"),
            currentActivity: "resting",
            daysTogether: 1
        )
        mock.stub(path: Endpoints.awaken, response: dto)
        let reply = MessageDTO(
            id: "m1",
            roomId: "ost_123",
            sender: "ostrich",
            senderId: "ost_123",
            content: "嗯。我记住了。",
            createdAt: "2026-05-17T00:00:01Z"
        )
        let chatResponse = ChatSendResponseDTO(
            messageId: "m0",
            ostrichReply: reply,
            toolCalls: []
        )
        mock.stub(path: Endpoints.chatSend, response: chatResponse)

        let coordinator = OnboardingCoordinator(client: mock)
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        coordinator.ostrichName = "柱子"
        coordinator.nameReason = "看你像我表哥"

        await coordinator.awakenAndSendFirstMessage()

        #expect(coordinator.ostrichReply == "嗯。我记住了。")
        #expect(coordinator.ostrichDTO?.id == "ost_123")
        #expect(mock.calls.count == 2)
        #expect(mock.calls[0].path == Endpoints.awaken)
        #expect(mock.calls[1].path == Endpoints.chatSend)
    }

    @Test func awakenFallbackOnFailure() async {
        let mock = MockConvexClient()
        mock.stubError(path: Endpoints.awaken, error: .claudeUnavailable)

        let coordinator = OnboardingCoordinator(client: mock)
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        coordinator.ostrichName = "柱子"
        coordinator.nameReason = "看你像我表哥"

        await coordinator.awakenAndSendFirstMessage()

        #expect(coordinator.ostrichReply.contains("柱子"))
        #expect(coordinator.ostrichDTO == nil)
    }

    @Test func awakenFallbackOnChatSendFailure() async {
        let mock = MockConvexClient()
        let dto = OstrichDTO(
            id: "ost_xyz",
            ownerId: "u1",
            name: "豆子",
            eggType: 2,
            archetype: "POET",
            awakenedAt: "2026-05-17T00:00:00Z",
            state: "awake",
            currentLocation: LocationDTO(lat: 0, lng: 0, friendlyName: "?"),
            currentActivity: "resting",
            daysTogether: 1
        )
        mock.stub(path: Endpoints.awaken, response: dto)
        mock.stubError(path: Endpoints.chatSend, error: .rateLimited)

        let coordinator = OnboardingCoordinator(client: mock)
        coordinator.selectMBTI(.ENFP)
        coordinator.selectZodiac(.leo)
        coordinator.selectEgg(EggCatalog.all[1])
        coordinator.ostrichName = "豆子"
        coordinator.nameReason = "圆圆的"

        await coordinator.awakenAndSendFirstMessage()

        #expect(coordinator.ostrichReply.contains("豆子"))
        #expect(mock.calls.count == 2)
    }

    @Test func awakenSkippedWhenMissingSelections() async {
        let mock = MockConvexClient()
        let coordinator = OnboardingCoordinator(client: mock)
        // 故意不选 egg / mbti / zodiac
        await coordinator.awakenAndSendFirstMessage()
        #expect(coordinator.ostrichReply.isEmpty == false)
        #expect(mock.calls.isEmpty)
    }
}
