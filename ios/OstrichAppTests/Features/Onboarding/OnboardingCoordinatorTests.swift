// OnboardingCoordinatorTests.swift
// 验证 OnboardingCoordinator：新流程的 step 状态转移 + awaken 调用。
//
// 新流程: welcome → eggBlindBox → eggHatch → userNameAsk → ostrichNameInput →
//          mbti → zodiac → awakening

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
            .eggBlindBox, .eggHatch,
            .userNameAsk, .ostrichNameInput,
            .mbti, .zodiac, .awakening
        ]
        for step in expected {
            coordinator.next()
            #expect(coordinator.step == step)
        }
    }

    @Test func nextAtAwakeningIsNoop() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        coordinator.goTo(.awakening)
        coordinator.next()
        #expect(coordinator.step == .awakening)
    }

    @Test func selectionsAreStored() {
        let coordinator = OnboardingCoordinator(client: MockConvexClient())
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        coordinator.userName = "诗枫"
        coordinator.ostrichName = "柱子"
        #expect(coordinator.selectedMBTI == .INFP)
        #expect(coordinator.selectedZodiac == .cancer)
        #expect(coordinator.selectedEgg?.archetype == "CUDDLER")
        #expect(coordinator.userName == "诗枫")
        #expect(coordinator.ostrichName == "柱子")
    }

    // MARK: - Awaken 流程（不再前置 chat send）

    @Test func awakenCallsConvex() async {
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
            daysTogether: 1,
            mainRoomId: "room_abc"
        )
        mock.stub(path: Endpoints.awaken, response: dto)

        let coordinator = OnboardingCoordinator(client: mock)
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        coordinator.userName = "诗枫"
        coordinator.ostrichName = "柱子"

        let result = await coordinator.awaken()

        #expect(result?.id == "ost_123")
        #expect(coordinator.ostrichDTO?.id == "ost_123")
        #expect(coordinator.ostrichDTO?.mainRoomId == "room_abc")
        #expect(mock.calls.count == 1)
        #expect(mock.calls[0].path == Endpoints.awaken)
    }

    @Test func awakenReturnsNilOnFailure() async {
        let mock = MockConvexClient()
        mock.stubError(path: Endpoints.awaken, error: .claudeUnavailable)

        let coordinator = OnboardingCoordinator(client: mock)
        coordinator.selectMBTI(.INFP)
        coordinator.selectZodiac(.cancer)
        coordinator.selectEgg(EggCatalog.all[3])
        coordinator.userName = "诗枫"
        coordinator.ostrichName = "柱子"

        let result = await coordinator.awaken()

        #expect(result == nil)
        #expect(coordinator.ostrichDTO == nil)
    }

    @Test func awakenSkippedWhenMissingSelections() async {
        let mock = MockConvexClient()
        let coordinator = OnboardingCoordinator(client: mock)
        // 故意不选 egg / mbti / zodiac
        let result = await coordinator.awaken()
        #expect(result == nil)
        #expect(mock.calls.isEmpty)
    }
}
