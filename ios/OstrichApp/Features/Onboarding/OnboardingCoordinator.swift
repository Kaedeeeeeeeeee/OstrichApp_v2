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
    @Published public var ostrichName: String = ""
    @Published public var nameReason: String = ""
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

    /// 真接入 ConvexClient.awaken + chat/send。失败 fallback mock 文案。
    /// 返回时已写入 ostrichReply / ostrichDTO（如果成功）。
    public func awakenAndSendFirstMessage() async {
        guard let egg = selectedEgg,
              let mbti = selectedMBTI,
              let zodiac = selectedZodiac else {
            ostrichReply = fallbackReply()
            return
        }
        let trimmedName = ostrichName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "鸵鸟" : trimmedName

        isAwakening = true
        defer { isAwakening = false }

        do {
            let awakenBody = AwakenRequest(
                eggType: egg.eggType,
                name: resolvedName,
                userMbti: mbti.rawValue,
                userZodiac: zodiac.apiKey
            )
            let dto: OstrichDTO = try await client.call(Endpoints.awaken, body: awakenBody)
            ostrichDTO = dto

            // 用 ostrich.id 作为 roomId 兜底（后端实际 roomId 由 awaken 写好；
            // demo 阶段第一句话直接用 ostrich.id 当 roomId，后端会路由到主传心室）。
            let roomId = dto.id
            let trimmedReason = nameReason.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = trimmedReason.isEmpty
                ? "我给你起了这个名字。"
                : trimmedReason
            let sendBody = SendMessageRequest(roomId: roomId, content: content)
            let response: ChatSendResponseDTO = try await client.call(
                Endpoints.chatSend, body: sendBody
            )
            ostrichReply = response.ostrichReply.content
        } catch {
            ostrichReply = fallbackReply()
        }
    }

    private func fallbackReply() -> String {
        let trimmed = ostrichName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "这个名字" : trimmed
        return "你叫我「\(name)」…嗯。我会记住。"
    }
}
