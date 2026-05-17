// OnboardingCoordinator.swift
// 驱动 Onboarding 9 步状态机；持有 ConvexClientProtocol 用于 awaken + 首次 chat send。
// 见 BLUEPRINT §13.2。

import Foundation
import SwiftUI

@MainActor
public final class OnboardingCoordinator: ObservableObject {

    // MARK: - Published state

    @Published public var step: OnboardingStep = .welcome
    @Published public var selectedMBTI: MBTI?
    @Published public var selectedZodiac: Zodiac?
    @Published public var selectedEgg: EggArchetype?
    /// 用户自己的名字（新流程 Step4 收集）。
    @Published public var userName: String = ""
    /// 用户给鸵鸟起的名字（新流程 Step5 收集）。
    @Published public var ostrichName: String = ""
    @Published public var ostrichReply: String = ""
    @Published public var ostrichDTO: OstrichDTO?
    @Published public var isAwakening = false

    // MARK: - Deps

    private let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    // MARK: - Navigation

    public func next() {
        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    public func goTo(_ target: OnboardingStep) {
        step = target
    }

    // MARK: - Selection

    public func selectMBTI(_ value: MBTI) {
        selectedMBTI = value
    }

    public func selectZodiac(_ value: Zodiac) {
        selectedZodiac = value
    }

    public func selectEgg(_ value: EggArchetype) {
        selectedEgg = value
    }

    // MARK: - Awaken + first message

    /// 新流程：所有选择收集完后只调 /api/awaken，不再前置发"why this name"消息
    /// （第一句话留给 Chat 界面让用户看到鸵鸟硬编码的"你为什么给我起这个名字？"
    /// 然后用户自己回答启动真正对话）。
    public func awaken() async -> OstrichDTO? {
        guard let egg = selectedEgg,
              let mbti = selectedMBTI,
              let zodiac = selectedZodiac else { return nil }
        let trimmedName = ostrichName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "鸵鸟" : trimmedName

        isAwakening = true
        defer { isAwakening = false }

        do {
            let trimmedUserName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            let awakenBody = AwakenRequest(
                eggType: egg.eggType,
                name: resolvedName,
                userMbti: mbti.rawValue,
                userZodiac: zodiac.apiKey,
                userName: trimmedUserName.isEmpty ? nil : trimmedUserName
            )
            let dto: OstrichDTO = try await client.call(Endpoints.awaken, body: awakenBody)
            ostrichDTO = dto
            return dto
        } catch {
            return nil
        }
    }
}
