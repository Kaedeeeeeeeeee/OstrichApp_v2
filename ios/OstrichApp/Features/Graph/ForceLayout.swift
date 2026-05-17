// ForceLayout.swift
// 自实现 force-directed graph 物理积分器。BLUEPRINT §8.4 / GitHub issue #24。
//
// 算法（每 step）：
//   1. 节点斥力（Coulomb-like）：F = k_repel / dist^2，沿连线推开。
//   2. 边吸引（Hooke 弹簧）：F = k_spring * (dist - restLength)，沿连线相吸。
//   3. 中心重力 + 分类区域吸引：把每类节点拉向自己的 anchor。
//   4. 阻尼：velocity *= damping。
//   5. clip 到 bounds（含 radius 内缩）。
//
// 收敛标准：所有节点 |velocity| < epsilon。
// 不引入 RealityKit / 第三方 force-graph 库。

import Combine
import CoreGraphics
import Foundation

@MainActor
public final class ForceLayout: ObservableObject {

    // MARK: - 可调参数

    /// 节点相斥强度。值越大节点散得越开。
    public var repulsion: Double = 12_000

    /// 边吸引（弹簧）系数。
    public var springStiffness: Double = 0.04

    /// 弹簧理想长度。weight=1 边偏短（更亲密）；weight=0 边偏长。
    public var baseRestLength: Double = 110

    /// 分类区域吸引强度（每帧朝 anchor 拉的比例）。
    public var anchorPull: Double = 0.015

    /// 阻尼：每帧 velocity 乘此系数。
    public var damping: Double = 0.85

    /// 单步最大位移（防爆炸）。
    public var maxStep: Double = 18

    /// 收敛 epsilon — 测试用。
    public var convergenceEpsilon: Double = 0.05

    // MARK: - State

    @Published public private(set) var nodes: [GraphNode] = []
    @Published public private(set) var edges: [GraphEdge] = []

    /// 节点 id → nodes 下标，加速边/拖拽查找。每次 load / step-after-pin 重建。
    private var indexById: [String: Int] = [:]

    /// 当前被用户拖拽固定的节点 id；它在 step 中不更新位置。
    private var pinnedId: String?

    /// 上一次 step 用的 bounds，便于 load 后第一次重排。
    private var lastBounds: CGRect = .zero

    public init() {}

    // MARK: - 加载

    /// 从后端 GraphDTO 初始化。会按分类 anchor + 微随机 jitter 撒点，避免全部叠在中心。
    public func load(graph: GraphResponseDTO, in size: CGSize = CGSize(width: 360, height: 600)) {
        var built: [GraphNode] = []
        built.reserveCapacity(graph.people.count + 1)

        // 中心 self 节点。
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        built.append(GraphNode(
            id: GraphSelf.id,
            position: center,
            velocity: .zero,
            radius: GraphRadius.selfRadius,
            category: GraphCategory.family.rawValue,  // 仅占位，self 渲染独立分支
            isSelf: true,
            displayName: GraphSelf.displayName
        ))

        // 其他人按分类 anchor + 偏移撒点。
        for (idx, person) in graph.people.enumerated() {
            let cat = GraphCategory.from(person.category)
            let anchor = anchorPoint(for: cat, in: size)
            // 用 (idx, name.hash) 派生确定性 jitter，避免每次 load 跳来跳去。
            let jitter = deterministicJitter(seed: person.id, index: idx, in: size)
            let pos = CGPoint(
                x: anchor.x + jitter.x,
                y: anchor.y + jitter.y
            )
            built.append(GraphNode(
                id: person.id,
                position: pos,
                velocity: .zero,
                radius: GraphRadius.from(closeness: person.closeness),
                category: cat.rawValue,
                isSelf: false,
                displayName: person.name
            ))
        }

        self.nodes = built
        self.edges = graph.edges.map {
            GraphEdge(
                fromId: $0.fromPersonId,
                toId: $0.toPersonId,
                weight: CGFloat(max(0, min(1, $0.weight)))
            )
        }
        rebuildIndex()
        self.lastBounds = CGRect(origin: .zero, size: size)
    }

    /// 替换 bounds（视图首次出现 / size 变化时调用）。
    public func setBounds(_ bounds: CGRect) {
        // 如果之前用占位 size load 过、随后 GeometryReader 给真实 size，
        // 把节点按比例拉伸到新 bounds，避免初始位置都挤左上角。
        if lastBounds.width > 0, lastBounds.height > 0,
           lastBounds.size != bounds.size {
            let scaleX = bounds.width / lastBounds.width
            let scaleY = bounds.height / lastBounds.height
            for i in nodes.indices {
                nodes[i].position.x *= scaleX
                nodes[i].position.y *= scaleY
            }
        }
        lastBounds = bounds
    }

    // MARK: - 拖拽

    /// 找出离 point 最近、且距离 ≤ radius+触摸 slop 的节点 id；用于 DragGesture 起点 hit-test。
    public func nodeId(at point: CGPoint, slop: CGFloat = 12) -> String? {
        var bestId: String?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for node in nodes {
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            let d = sqrt(dx * dx + dy * dy)
            if d <= node.radius + slop && d < bestDist {
                bestDist = d
                bestId = node.id
            }
        }
        return bestId
    }

    /// 把节点直接移动到指定位置（被拖拽时调用），并固定它跳出力学计算。
    public func pin(id: String, to point: CGPoint) {
        guard let idx = indexById[id] else { return }
        nodes[idx].position = point
        nodes[idx].velocity = .zero
        pinnedId = id
    }

    /// 松手：解除 pin，回归力学。
    public func unpin() {
        pinnedId = nil
    }

    // MARK: - 物理 step

    /// 单步积分。dt 给 30fps 使用；bounds 用于 anchor / clip。
    public func step(dt: TimeInterval, bounds: CGRect) {
        guard !nodes.isEmpty, bounds.width > 1, bounds.height > 1 else { return }
        self.lastBounds = bounds

        let size = bounds.size
        var forces = [CGVector](repeating: .zero, count: nodes.count)

        // 1) 节点斥力 O(n^2) — n<=100 完全 OK。
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                var dist2 = Double(dx * dx + dy * dy)
                if dist2 < 0.01 { dist2 = 0.01 }
                let dist = sqrt(dist2)
                let mag = repulsion / dist2
                let fx = (Double(dx) / dist) * mag
                let fy = (Double(dy) / dist) * mag
                forces[i].dx += CGFloat(fx)
                forces[i].dy += CGFloat(fy)
                forces[j].dx -= CGFloat(fx)
                forces[j].dy -= CGFloat(fy)
            }
        }

        // 2) 边弹簧 — restLength 由 weight 决定（亲密 = 短）。
        for edge in edges {
            guard let a = indexById[edge.fromId],
                  let b = indexById[edge.toId] else { continue }
            let dx = nodes[b].position.x - nodes[a].position.x
            let dy = nodes[b].position.y - nodes[a].position.y
            let dist = max(0.01, sqrt(Double(dx * dx + dy * dy)))
            let rest = baseRestLength * (1.0 - Double(edge.weight) * 0.55)
            let stretch = dist - rest
            let mag = springStiffness * stretch
            let fx = (Double(dx) / dist) * mag
            let fy = (Double(dy) / dist) * mag
            forces[a].dx += CGFloat(fx)
            forces[a].dy += CGFloat(fy)
            forces[b].dx -= CGFloat(fx)
            forces[b].dy -= CGFloat(fy)
        }

        // 3) 分类 anchor 吸引（self 固定中心，自己拥有独立处理）。
        for i in 0..<nodes.count {
            if nodes[i].isSelf {
                continue
            }
            let cat = GraphCategory.from(nodes[i].category)
            let anchor = anchorPoint(for: cat, in: size)
            let dx = anchor.x - nodes[i].position.x
            let dy = anchor.y - nodes[i].position.y
            forces[i].dx += CGFloat(Double(dx) * anchorPull)
            forces[i].dy += CGFloat(Double(dy) * anchorPull)
        }

        // 4) 积分 + 阻尼 + clip。
        let centerX = bounds.midX
        let centerY = bounds.midY
        for i in 0..<nodes.count {
            if nodes[i].isSelf {
                // self 固定画布中心。
                nodes[i].position = CGPoint(x: centerX, y: centerY)
                nodes[i].velocity = .zero
                continue
            }
            if nodes[i].id == pinnedId {
                nodes[i].velocity = .zero
                continue
            }
            // Euler：v += F*dt；x += v*dt；dt 标定化到 1/30s。
            nodes[i].velocity.dx = (nodes[i].velocity.dx + forces[i].dx * CGFloat(dt)) * CGFloat(damping)
            nodes[i].velocity.dy = (nodes[i].velocity.dy + forces[i].dy * CGFloat(dt)) * CGFloat(damping)

            // 限位移
            var stepX = nodes[i].velocity.dx
            var stepY = nodes[i].velocity.dy
            let mag = sqrt(Double(stepX * stepX + stepY * stepY))
            if mag > maxStep {
                let scale = CGFloat(maxStep / mag)
                stepX *= scale
                stepY *= scale
            }
            nodes[i].position.x += stepX
            nodes[i].position.y += stepY

            // clip 到 bounds（节点完整可见）。
            let r = nodes[i].radius
            nodes[i].position.x = max(bounds.minX + r, min(bounds.maxX - r, nodes[i].position.x))
            nodes[i].position.y = max(bounds.minY + r, min(bounds.maxY - r, nodes[i].position.y))
        }
    }

    /// 测试用：当前最大速度模长。
    public var maxSpeed: Double {
        nodes.reduce(0.0) { acc, n in
            let v = sqrt(Double(n.velocity.dx * n.velocity.dx + n.velocity.dy * n.velocity.dy))
            return max(acc, v)
        }
    }

    // MARK: - 私有辅助

    private func rebuildIndex() {
        indexById.removeAll(keepingCapacity: true)
        for (i, n) in nodes.enumerated() {
            indexById[n.id] = i
        }
    }

    /// 分类 anchor 的画布像素坐标。
    private func anchorPoint(for cat: GraphCategory, in size: CGSize) -> CGPoint {
        let off = cat.anchorOffset
        return CGPoint(x: size.width * off.x, y: size.height * off.y)
    }

    /// 用 id hash 派生确定性偏移，撒在 [-40, 40] 范围。
    private func deterministicJitter(seed: String, index: Int, in size: CGSize) -> CGPoint {
        var hash: UInt64 = 1469598103934665603
        for b in seed.utf8 {
            hash = (hash ^ UInt64(b)) &* 1099511628211
        }
        hash = hash &+ UInt64(index)
        let xRaw = Double(hash & 0xFFFF) / 65535.0       // 0..1
        let yRaw = Double((hash >> 16) & 0xFFFF) / 65535.0
        let span = min(size.width, size.height) * 0.15
        return CGPoint(x: (xRaw - 0.5) * span, y: (yRaw - 0.5) * span)
    }
}
