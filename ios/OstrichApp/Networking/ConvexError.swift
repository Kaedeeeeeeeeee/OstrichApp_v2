// ConvexError.swift
// INTERFACES.md §7 错误码 → 用户可读 Swift error。

import Foundation

public enum ConvexError: Error, LocalizedError, Equatable {
    case authRequired
    case authInvalid
    case ostrichNotFound
    case ostrichSleeping
    case ostrichWandering
    case rateLimited
    case claudeUnavailable
    case mapsUnavailable
    case decoding(String)        // 用 String 容纳底层 error，便于 Equatable
    case transport(String)
    case internalError(message: String)

    /// 把 INTERFACES §7 的 7 个 ErrorCode + INTERNAL 字符串映射到枚举。
    public static func fromCode(_ code: String, message: String) -> ConvexError {
        switch code {
        case "AUTH_REQUIRED":      return .authRequired
        case "AUTH_INVALID":       return .authInvalid
        case "OSTRICH_NOT_FOUND":  return .ostrichNotFound
        case "OSTRICH_SLEEPING":   return .ostrichSleeping
        case "OSTRICH_WANDERING":  return .ostrichWandering
        case "RATE_LIMITED":       return .rateLimited
        case "CLAUDE_UNAVAILABLE": return .claudeUnavailable
        case "MAPS_UNAVAILABLE":   return .mapsUnavailable
        default:                   return .internalError(message: message)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .authRequired:
            return "请先登录，才能找到你的鸵鸟"
        case .authInvalid:
            return "登录过期了，重新进来一下"
        case .ostrichNotFound:
            return "还没有鸵鸟。打开蛋柜挑一个吧"
        case .ostrichSleeping:
            return "鸵鸟在蛋里睡着，先唤醒它"
        case .ostrichWandering:
            return "鸵鸟现在不在家，想跟它说话？召唤一下吧"
        case .rateLimited:
            return "说得太快了，鸵鸟没跟上，喘口气再聊"
        case .claudeUnavailable:
            return "鸵鸟脑袋有点晕，过一会儿再来"
        case .mapsUnavailable:
            return "地图暂时取不到，等等再看遛弯路线"
        case .decoding:
            return "收到的数据看不懂，待会儿再试"
        case .transport:
            return "网络断了，鸵鸟也联系不上"
        case .internalError(let message):
            return "出了点意外：\(message)"
        }
    }
}
