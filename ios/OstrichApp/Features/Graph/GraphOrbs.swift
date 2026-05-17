// GraphOrbs.swift
// 关系图谱的光球粒子系统。
//
// 设计：
//   每条「我 → ta」边按 person.memoryWeight 派生一个 spawnRate（颗/秒）。
//   每颗光球以恒定速度沿连线从「我」流向对方节点，progress 0→1 后回收。
//   被记忆字符越多的人 → spawnRate 越大 → 飞向 ta 的光球越密集。
//
// 不 @Published：渲染由 GraphView 的 TimelineView 30fps 自驱，
//   避免 ObservableObject change 触发多余 view rebuild。
//
// 上限保护：单边活跃光球 maxOrbsPerEdge，全场 spawnRate 还有 maxSpawnRate 截断。

import CoreGraphics
import Foundation
import SwiftUI

/// 单颗光球。
/// - toPersonId 同时充当所属边的 key（所有边都是 self → person，源端一致）。
/// - progress 0 = 在「我」位置，1 = 在 person 位置。
public struct GraphOrb: Identifiable, Equatable {
    public let id: UUID
    public let toPersonId: String
    public var progress: Double
    public let speed: Double   // 每秒 progress 增量（恒定）

    public init(
        id: UUID = UUID(),
        toPersonId: String,
        progress: Double = 0,
        speed: Double
    ) {
        self.id = id
        self.toPersonId = toPersonId
        self.progress = progress
        self.speed = speed
    }
}

/// 关系图谱光球场。GraphView 持有一个 @StateObject 实例，每帧调用 step(dt:edges:)。
@MainActor
public final class OrbsField: ObservableObject {

    // MARK: - 调参

    /// 单颗光球穿越整条边所需秒数（越小越快）。
    public var traversalSeconds: Double = 2.4

    /// 单条边的最大 spawn 频率（颗/秒），防止 memoryWeight 极大时刷屏。
    public var maxSpawnRate: Double = 3.5

    /// memoryWeight → spawnRate 的线性系数：weight / weightPerSecond = rate。
    /// 默认 250：memoryWeight = 250 字 → 1 颗/秒。
    public var weightPerSecond: Double = 250

    /// 单条边活跃光球数量上限（防止极端情况下队列爆炸）。
    public var maxOrbsPerEdge: Int = 8

    // MARK: - 状态

    public private(set) var orbs: [GraphOrb] = []

    /// 每条边「自上次 spawn 以来累积的秒数」。
    private var pendingSpawnTime: [String: Double] = [:]

    public init() {}

    public func reset() {
        orbs.removeAll()
        pendingSpawnTime.removeAll()
    }

    // MARK: - 物理推进

    /// 单帧。
    /// - Parameters:
    ///   - dt: 与 GraphView TimelineView 同频，1/30s。
    ///   - edges: 当前所有「我 → ta」边及其 memoryWeight。
    public func step(dt: Double, edges: [(toPersonId: String, memoryWeight: Double)]) {
        // 1) 推进 + 回收。
        for i in orbs.indices {
            orbs[i].progress += orbs[i].speed * dt
        }
        orbs.removeAll { $0.progress >= 1.0 }

        // 2) 清理已无边的累积器（避免无限增长）。
        let activeIds = Set(edges.map(\.toPersonId))
        pendingSpawnTime = pendingSpawnTime.filter { activeIds.contains($0.key) }

        // 3) 按 spawnRate 决定是否再投一颗。
        for edge in edges {
            let rate = spawnRate(for: edge.memoryWeight)
            guard rate > 0 else { continue }
            var elapsed = (pendingSpawnTime[edge.toPersonId] ?? 0) + dt
            let interval = 1.0 / rate
            while elapsed >= interval {
                if orbCount(for: edge.toPersonId) >= maxOrbsPerEdge {
                    elapsed = 0
                    break
                }
                spawnOrb(to: edge.toPersonId)
                elapsed -= interval
            }
            pendingSpawnTime[edge.toPersonId] = max(0, elapsed)
        }
    }

    // MARK: - 单测可用

    /// 给定 memoryWeight 算出 spawnRate（颗/秒）。
    public func spawnRate(for memoryWeight: Double) -> Double {
        guard memoryWeight > 0 else { return 0 }
        let raw = memoryWeight / weightPerSecond
        return min(maxSpawnRate, raw)
    }

    public func orbCount(for toPersonId: String) -> Int {
        orbs.reduce(0) { $0 + ($1.toPersonId == toPersonId ? 1 : 0) }
    }

    // MARK: - 私有

    private func spawnOrb(to toPersonId: String) {
        let speed = 1.0 / max(0.01, traversalSeconds)
        orbs.append(GraphOrb(toPersonId: toPersonId, progress: 0, speed: speed))
    }
}
