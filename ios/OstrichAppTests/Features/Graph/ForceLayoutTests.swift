// ForceLayoutTests.swift
// 关系图谱力学引擎单测：节点稳定 / 圆圈大小 / 分类落位 / 拖拽 pin。

import CoreGraphics
import Foundation
import Testing
@testable import OstrichApp

@MainActor
struct ForceLayoutTests {

    // MARK: - 半径映射

    @Test func radiusMapsClosenessLinearly() {
        #expect(GraphRadius.from(closeness: 0) == 18)
        #expect(GraphRadius.from(closeness: 1) == 48)
        // 中点 0.5 → 33pt
        #expect(abs(GraphRadius.from(closeness: 0.5) - 33) < 0.001)
    }

    @Test func radiusClampsOutOfRange() {
        #expect(GraphRadius.from(closeness: -2) == 18)
        #expect(GraphRadius.from(closeness: 5) == 48)
    }

    @Test func selfRadiusIsConstant() {
        #expect(GraphRadius.selfRadius == 36)
    }

    // MARK: - 分类映射

    @Test func categoryFromRawValueParses() {
        #expect(GraphCategory.from("family") == .family)
        #expect(GraphCategory.from("friend") == .friend)
        #expect(GraphCategory.from("colleague") == .colleague)
        #expect(GraphCategory.from("ostrich_introduced") == .ostrichIntroduced)
        #expect(GraphCategory.from("x_person") == .xPerson)
    }

    @Test func categoryUnknownFallsBackToXPerson() {
        #expect(GraphCategory.from("totally-unknown") == .xPerson)
        #expect(GraphCategory.from("") == .xPerson)
    }

    // MARK: - load

    @Test func loadInsertsSelfNodeAtCenter() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let size = CGSize(width: 360, height: 600)
        layout.load(graph: graph, in: size)

        #expect(layout.nodes.count == graph.people.count + 1)
        let selfNode = layout.nodes.first { $0.isSelf }
        #expect(selfNode != nil)
        #expect(selfNode?.id == GraphSelf.id)
        #expect(selfNode?.position.x == size.width / 2)
        #expect(selfNode?.position.y == size.height / 2)
        #expect(selfNode?.radius == GraphRadius.selfRadius)
    }

    @Test func loadAppliesClosenessRadius() {
        let layout = ForceLayout()
        let people = [
            PersonDTO(
                id: "p_a", name: "A", aliases: [], category: "family",
                closeness: 0.0, recentInteractionCount: 0, notes: "",
                hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
            ),
            PersonDTO(
                id: "p_b", name: "B", aliases: [], category: "friend",
                closeness: 1.0, recentInteractionCount: 0, notes: "",
                hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
            )
        ]
        let graph = GraphResponseDTO(people: people, edges: [])
        layout.load(graph: graph)

        let a = layout.nodes.first { $0.id == "p_a" }
        let b = layout.nodes.first { $0.id == "p_b" }
        #expect(a?.radius == 18)
        #expect(b?.radius == 48)
    }

    // MARK: - 稳定性

    @Test func smallGraphStabilizesAfter300Steps() {
        // 5 个真实节点 + self；100+ step 后速度应明显收敛。
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 600)
        layout.load(graph: graph, in: bounds.size)

        for _ in 0..<300 {
            layout.step(dt: 1.0 / 30.0, bounds: bounds)
        }

        // 阻尼 0.85^300 远小于 epsilon；最大速度应趋近 0。
        #expect(layout.maxSpeed < 1.0)
    }

    @Test func nodesStayInsideBounds() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
        layout.load(graph: graph, in: bounds.size)

        for _ in 0..<60 {
            layout.step(dt: 1.0 / 30.0, bounds: bounds)
        }

        for node in layout.nodes {
            #expect(node.position.x >= bounds.minX)
            #expect(node.position.x <= bounds.maxX)
            #expect(node.position.y >= bounds.minY)
            #expect(node.position.y <= bounds.maxY)
        }
    }

    @Test func selfNodeStaysPinnedAtCenter() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        layout.load(graph: graph, in: bounds.size)

        for _ in 0..<50 {
            layout.step(dt: 1.0 / 30.0, bounds: bounds)
        }

        let selfNode = layout.nodes.first { $0.isSelf }
        #expect(selfNode?.position.x == bounds.midX)
        #expect(selfNode?.position.y == bounds.midY)
    }

    // MARK: - 拖拽

    @Test func hitTestFindsClosestNode() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        layout.load(graph: graph, in: bounds.size)

        guard let firstNonSelf = layout.nodes.first(where: { !$0.isSelf }) else {
            Issue.record("expected at least one non-self node")
            return
        }
        let id = layout.nodeId(at: firstNonSelf.position)
        #expect(id == firstNonSelf.id)
    }

    @Test func hitTestReturnsNilFarFromNodes() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        layout.load(graph: graph, in: CGSize(width: 400, height: 600))

        // (-9999, -9999) 离所有节点都远
        let id = layout.nodeId(at: CGPoint(x: -9999, y: -9999))
        #expect(id == nil)
    }

    @Test func pinKeepsNodeAtFixedPosition() {
        let layout = ForceLayout()
        let graph = GraphViewModel.fallbackMock()
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        layout.load(graph: graph, in: bounds.size)

        guard let target = layout.nodes.first(where: { !$0.isSelf }) else {
            Issue.record("expected non-self node")
            return
        }
        let pinned = CGPoint(x: 100, y: 100)
        layout.pin(id: target.id, to: pinned)

        for _ in 0..<30 {
            layout.step(dt: 1.0 / 30.0, bounds: bounds)
        }

        let after = layout.nodes.first { $0.id == target.id }
        #expect(after?.position == pinned)

        // 松开后应可自由移动
        layout.unpin()
        for _ in 0..<60 {
            layout.step(dt: 1.0 / 30.0, bounds: bounds)
        }
        let moved = layout.nodes.first { $0.id == target.id }
        // 不再固定（位置应不等于 pinned，因为 anchor 拉力 + 斥力）
        #expect(moved?.position != pinned)
    }

    // MARK: - 边粗细

    @Test func edgeThicknessMapsWeight() {
        let e0 = GraphEdge(fromId: "a", toId: "b", weight: 0)
        let e1 = GraphEdge(fromId: "a", toId: "b", weight: 1)
        let half = GraphEdge(fromId: "a", toId: "b", weight: 0.5)
        #expect(e0.thickness == 1.0)
        #expect(e1.thickness == 5.0)
        #expect(abs(half.thickness - 3.0) < 0.001)
    }

    @Test func edgeThicknessClampsAboveOne() {
        let oversized = GraphEdge(fromId: "a", toId: "b", weight: 5.0)
        #expect(oversized.thickness == 5.0)
    }
}
