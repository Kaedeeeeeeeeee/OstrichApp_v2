// GraphModels.swift
// 关系图谱内部模型：把 PersonDTO / EdgeDTO 转换成布局可用的 GraphNode / GraphEdge。
// BLUEPRINT §8.3 (圆圈大小) + §8.4 (五分类区域)。
//
// 设计约定：
// - 中心节点用户自己用 id = "self"，固定在画布中心，特殊配色。
// - 节点 radius 由 closeness 线性映射到 18-48pt（self 固定 36pt）。
// - 边粗细由 weight 线性映射到 1.0-5.0pt。
// - 五分类区域用相对画布尺寸的偏移向量，避免初始全部堆在中心。

import CoreGraphics
import SwiftUI

// MARK: - 节点

/// 力导向算法用的节点。值类型以便 ForceLayout 每帧整体替换 + SwiftUI diffing。
public struct GraphNode: Identifiable, Equatable {
    public let id: String
    public var position: CGPoint
    public var velocity: CGVector
    public let radius: CGFloat
    public let category: String
    public let isSelf: Bool
    public let displayName: String

    public init(
        id: String,
        position: CGPoint,
        velocity: CGVector = .zero,
        radius: CGFloat,
        category: String,
        isSelf: Bool,
        displayName: String
    ) {
        self.id = id
        self.position = position
        self.velocity = velocity
        self.radius = radius
        self.category = category
        self.isSelf = isSelf
        self.displayName = displayName
    }
}

// MARK: - 边

public struct GraphEdge: Equatable {
    public let fromId: String
    public let toId: String
    public let weight: CGFloat       // 0..1

    public init(fromId: String, toId: String, weight: CGFloat) {
        self.fromId = fromId
        self.toId = toId
        self.weight = weight
    }

    /// 粗细映射：1pt 起步 + weight * 4pt → 1..5pt。
    public var thickness: CGFloat {
        1.0 + max(0, min(1, weight)) * 4.0
    }
}

// MARK: - 分类

/// 五分类的可视化属性 + 区域吸引中心（相对画布 [0,1]^2 的归一化坐标）。
public enum GraphCategory: String, CaseIterable {
    case family
    case friend
    case colleague
    case ostrichIntroduced = "ostrich_introduced"
    case xPerson = "x_person"

    /// 容错：未知分类一律归到 xPerson（外圈飘）。
    public static func from(_ raw: String) -> GraphCategory {
        if let direct = GraphCategory(rawValue: raw) { return direct }
        // 兼容潜在简写
        switch raw {
        case "ostrich_intro": return .ostrichIntroduced
        case "x", "unknown":  return .xPerson
        default:              return .xPerson
        }
    }

    /// 五分类区域：family 左上 / friend 右上 / colleague 左下 / ostrich_intro 右下 / x_person 外圈。
    /// 单位归一化（0..1 = 画布左右/上下边）。
    public var anchorOffset: CGPoint {
        switch self {
        case .family:             return CGPoint(x: 0.25, y: 0.30)
        case .friend:             return CGPoint(x: 0.75, y: 0.30)
        case .colleague:          return CGPoint(x: 0.25, y: 0.70)
        case .ostrichIntroduced:  return CGPoint(x: 0.75, y: 0.70)
        case .xPerson:            return CGPoint(x: 0.50, y: 0.92)  // 飘外圈底部
        }
    }

    /// 节点底色（由 GraphView 渲染时取用）。
    public var fillColor: Color {
        switch self {
        case .family:             return OstrichColors.orangeDeep
        case .friend:             return OstrichColors.orange
        case .colleague:          return OstrichColors.ink.opacity(0.5)
        case .ostrichIntroduced:  return OstrichColors.orange.opacity(0.5)
        case .xPerson:            return OstrichColors.cream
        }
    }

    /// X 人需要描边以便在浅底上可见。
    public var strokeColor: Color {
        switch self {
        case .xPerson: return OstrichColors.ink
        default:       return .clear
        }
    }

    /// 中文标签（用于详情 sheet 等）。
    public var displayLabel: String {
        switch self {
        case .family:             return "家人"
        case .friend:             return "朋友"
        case .colleague:          return "同事"
        case .ostrichIntroduced:  return "鸵鸟介绍"
        case .xPerson:            return "X 人"
        }
    }
}

// MARK: - 半径映射

public enum GraphRadius {
    /// closeness ∈ [0,1] → radius ∈ [18,48] pt。
    /// 蓝图 §8.3 给出 size 公式（0.3 + 0.4*mentions + 0.3*importance）已是 0..1，外层直接传 closeness 即可。
    public static func from(closeness: Double) -> CGFloat {
        let clamped = max(0, min(1, closeness))
        return 18 + CGFloat(clamped) * 30
    }

    /// 中心 self 节点固定半径。
    public static let selfRadius: CGFloat = 36
}

// MARK: - 用户自身节点常量

public enum GraphSelf {
    /// 中心节点 id。EdgeDTO.fromPersonId 也用同样字符串。
    public static let id = "self"
    public static let displayName = "我"
}
