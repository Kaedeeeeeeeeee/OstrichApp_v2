// GraphViewModel.swift
// 关系图谱状态：load → 拉 ConvexClient.graph → 失败时空图谱 + 错误文案。
// INTERFACES.md §1.4 (graph endpoints) + §8 (轮询策略：进入时 1 次，不轮询)。
//
// 设计原则：关系图谱必须只展示真实数据。若用户尚未在传心室提到过任何人，
// 后端会返回空 people 数组 — UI 应该是中心一个「我」+ 提示文案，
// 绝不可以塞 demo 数据冒充。`demoFixture()` 仅供 SwiftUI Preview 与单测使用。

import Foundation
import SwiftUI

@MainActor
public final class GraphViewModel: ObservableObject {

    // MARK: - Published

    @Published public private(set) var graph: GraphResponseDTO?
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?
    @Published public var selectedPerson: PersonDTO?

    // MARK: - Deps

    private let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    // MARK: - 加载

    /// 拉 /api/graph。失败时图谱归为空（仅显示中心「我」）+ loadError 给 UI 提示。
    /// 不再注入 demo 数据冒充真实关系。
    public func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response: GraphResponseDTO = try await client.get(Endpoints.graph)
            graph = response
        } catch let err as ConvexError {
            loadError = err.errorDescription
            graph = GraphResponseDTO(people: [], edges: [])
        } catch {
            loadError = error.localizedDescription
            graph = GraphResponseDTO(people: [], edges: [])
        }
    }

    // MARK: - 选中节点 → 详情

    /// 视图收到 tap → 通过节点 id 找出对应 PersonDTO 并暴露给 sheet。
    /// id == "self" 不弹（中心自己不需要详情）。
    public func selectNode(id: String) {
        guard id != GraphSelf.id else { return }
        guard let people = graph?.people else { return }
        if let person = people.first(where: { $0.id == id }) {
            selectedPerson = person
        }
    }

    public func dismissDetail() {
        selectedPerson = nil
    }

    // MARK: - Demo fixture（仅 Preview + 单测）

    /// 给 SwiftUI Preview 与单元测试做物理 / UI 验证用的固定 graph。
    /// 生产 load() 流程**绝不**调用此 fixture — 真实图谱必须由后端 people 表驱动。
    public static func demoFixture() -> GraphResponseDTO {
        let now = "2026-05-17T10:00:00Z"
        let people: [PersonDTO] = [
            PersonDTO(
                id: "p_mom",
                name: "妈妈",
                aliases: ["妈"],
                category: "family",
                closeness: 0.82,
                recentInteractionCount: 14,
                notes: "最近聊得多，但你说有点窒息。",
                hasOstrich: false,
                lastMentionedAt: now,
                memoryWeight: 820
            ),
            PersonDTO(
                id: "p_jie",
                name: "阿杰",
                aliases: ["杰"],
                category: "friend",
                closeness: 0.65,
                recentInteractionCount: 6,
                notes: "周末经常一起打球。",
                hasOstrich: true,
                lastMentionedAt: now,
                memoryWeight: 450
            ),
            PersonDTO(
                id: "p_lin",
                name: "林姐",
                aliases: [],
                category: "colleague",
                closeness: 0.40,
                recentInteractionCount: 3,
                notes: "新项目的 PM。",
                hasOstrich: false,
                lastMentionedAt: now,
                memoryWeight: 180
            ),
            PersonDTO(
                id: "p_sasa",
                name: "飒飒",
                aliases: [],
                category: "ostrich_introduced",
                closeness: 0.30,
                recentInteractionCount: 2,
                notes: "鸵鸟遛弯认识的音乐人。",
                hasOstrich: true,
                lastMentionedAt: now,
                memoryWeight: 220
            ),
            PersonDTO(
                id: "p_x1",
                name: "K",
                aliases: [],
                category: "x_person",
                closeness: 0.20,
                recentInteractionCount: 1,
                notes: "提过一次，关系待定。",
                hasOstrich: false,
                lastMentionedAt: now,
                memoryWeight: 30
            )
        ]
        let edges: [EdgeDTO] = [
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_mom", weight: 0.85),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_jie", weight: 0.65),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_lin", weight: 0.40),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_sasa", weight: 0.30),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_x1", weight: 0.20),
            EdgeDTO(fromPersonId: "p_jie", toPersonId: "p_sasa", weight: 0.25)
        ]
        return GraphResponseDTO(people: people, edges: edges)
    }
}
