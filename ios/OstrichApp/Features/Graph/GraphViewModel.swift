// GraphViewModel.swift
// 关系图谱状态：load → 拉 ConvexClient.graph → 失败 fallback mock。
// INTERFACES.md §1.4 (graph endpoints) + §8 (轮询策略：进入时 1 次，不轮询)。

import Foundation
import SwiftUI

@MainActor
public final class GraphViewModel: ObservableObject {

    // MARK: - Published

    @Published public private(set) var graph: GraphResponseDTO?
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?
    @Published public private(set) var usedFallback = false
    @Published public var selectedPerson: PersonDTO?

    // MARK: - Deps

    private let client: ConvexClientProtocol

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    // MARK: - 加载

    /// 拉 /api/graph。失败时把 fallback mock 注入 graph，errorMessage 留作 UI 提示。
    public func load() async {
        isLoading = true
        loadError = nil
        usedFallback = false
        defer { isLoading = false }

        do {
            let response: GraphResponseDTO = try await client.get(Endpoints.graph)
            graph = response
        } catch let err as ConvexError {
            loadError = err.errorDescription
            graph = Self.fallbackMock()
            usedFallback = true
        } catch {
            loadError = error.localizedDescription
            graph = Self.fallbackMock()
            usedFallback = true
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

    // MARK: - Fallback mock

    /// 后端 503 / 404 时给 UI 一个看得到的图：自己 + 5 个常见角色 + 边。
    /// DEMO_SCRIPT 02-03min 用到的妈妈 / 阿杰 等。
    public static func fallbackMock() -> GraphResponseDTO {
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
                lastMentionedAt: now
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
                lastMentionedAt: now
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
                lastMentionedAt: now
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
                lastMentionedAt: now
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
                lastMentionedAt: now
            )
        ]
        let edges: [EdgeDTO] = [
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_mom", weight: 0.85),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_jie", weight: 0.65),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_lin", weight: 0.40),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_sasa", weight: 0.30),
            EdgeDTO(fromPersonId: GraphSelf.id, toPersonId: "p_x1", weight: 0.20),
            // 三角小连接
            EdgeDTO(fromPersonId: "p_jie", toPersonId: "p_sasa", weight: 0.25)
        ]
        return GraphResponseDTO(people: people, edges: edges)
    }
}
