// OnboardingModels.swift
// Onboarding 用的本地枚举（MBTI / 星座 / 蛋 archetype）以及 Awaken / Chat send 请求体。
// INTERFACES.md §1.2 awaken 入参；§1.3 chat/send 入参。

import Foundation
import SwiftUI

// MARK: - Step

/// Onboarding 流程顺序（demo 试跑后调整）：
/// 1. 欢迎（液态鸵鸟 hero + "唤醒" CTA）
/// 2. 选蛋盲盒
/// 3. 破壳 — 鸵鸟出现
/// 4. 鸵鸟问"你叫什么名字"，用户输入自己名字
/// 5. 用户给鸵鸟起名字（"我叫你 XX"）
/// 6. MBTI 选择
/// 7. 星座选择
/// 8. 唤醒（调 /api/awaken）+ 直接跳 Chat
public enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome = 1
    case eggBlindBox
    case eggHatch
    case userNameAsk
    case ostrichNameInput
    case mbti
    case zodiac
    case awakening
}

// MARK: - MBTI

public enum MBTI: String, CaseIterable, Identifiable {
    case INTJ, INTP, ENTJ, ENTP
    case INFJ, INFP, ENFJ, ENFP
    case ISTJ, ISFJ, ESTJ, ESFJ
    case ISTP, ISFP, ESTP, ESFP

    public var id: String { rawValue }
}

// MARK: - 星座

public enum Zodiac: String, CaseIterable, Identifiable {
    case aries = "白羊座"
    case taurus = "金牛座"
    case gemini = "双子座"
    case cancer = "巨蟹座"
    case leo = "狮子座"
    case virgo = "处女座"
    case libra = "天秤座"
    case scorpio = "天蝎座"
    case sagittarius = "射手座"
    case capricorn = "摩羯座"
    case aquarius = "水瓶座"
    case pisces = "双鱼座"

    public var id: String { rawValue }

    /// 后端期望的英文 key（与 INTERFACES.md userZodiac string 对齐）。
    public var apiKey: String {
        switch self {
        case .aries: return "aries"
        case .taurus: return "taurus"
        case .gemini: return "gemini"
        case .cancer: return "cancer"
        case .leo: return "leo"
        case .virgo: return "virgo"
        case .libra: return "libra"
        case .scorpio: return "scorpio"
        case .sagittarius: return "sagittarius"
        case .capricorn: return "capricorn"
        case .aquarius: return "aquarius"
        case .pisces: return "pisces"
        }
    }
}

// MARK: - 16 蛋

/// 蛋视觉档案：eggType (1..16) + archetype 代号 + 中文显示名 + 一对色调。
public struct EggArchetype: Identifiable, Equatable {
    public let eggType: Int
    public let archetype: String
    public let displayName: String
    public let primary: Color
    public let secondary: Color
    public var id: Int { eggType }
}

public enum EggCatalog {
    /// 与 shared/eggs/ 文件名顺序一致（eggId 01..16）。
    public static let all: [EggArchetype] = [
        EggArchetype(eggType: 1, archetype: "STEADFAST", displayName: "守望者",
                     primary: OstrichColors.cream, secondary: OstrichColors.creamDeep),
        EggArchetype(eggType: 2, archetype: "POET", displayName: "诗人",
                     primary: OstrichColors.orange.opacity(0.85),
                     secondary: OstrichColors.orangeDeep),
        EggArchetype(eggType: 3, archetype: "STRAIGHTSHOOTER", displayName: "直心客",
                     primary: OstrichColors.orange,
                     secondary: OstrichColors.cream),
        EggArchetype(eggType: 4, archetype: "CUDDLER", displayName: "甜心",
                     primary: OstrichColors.cream,
                     secondary: OstrichColors.orange.opacity(0.6)),
        EggArchetype(eggType: 5, archetype: "WORLDLY", displayName: "老炮儿",
                     primary: OstrichColors.creamDeep,
                     secondary: OstrichColors.ink.opacity(0.7)),
        EggArchetype(eggType: 6, archetype: "MAVERICK", displayName: "鬼才",
                     primary: OstrichColors.orangeDeep,
                     secondary: OstrichColors.cream),
        EggArchetype(eggType: 7, archetype: "STOIC", displayName: "冷哲",
                     primary: OstrichColors.ink.opacity(0.55),
                     secondary: OstrichColors.creamDeep),
        EggArchetype(eggType: 8, archetype: "WATCHER", displayName: "观察者",
                     primary: OstrichColors.creamDeep,
                     secondary: OstrichColors.ink.opacity(0.4)),
        EggArchetype(eggType: 9, archetype: "HEDONIST", displayName: "美食家",
                     primary: OstrichColors.orange,
                     secondary: OstrichColors.creamDeep),
        EggArchetype(eggType: 10, archetype: "INNOCENT", displayName: "童心",
                     primary: OstrichColors.cream,
                     secondary: OstrichColors.orange.opacity(0.45)),
        EggArchetype(eggType: 11, archetype: "PROTECTOR", displayName: "仗义客",
                     primary: OstrichColors.orangeDeep,
                     secondary: OstrichColors.creamDeep),
        EggArchetype(eggType: 12, archetype: "ELDER", displayName: "长者",
                     primary: OstrichColors.creamDeep,
                     secondary: OstrichColors.orangeDeep.opacity(0.7)),
        EggArchetype(eggType: 13, archetype: "MYSTIC", displayName: "玄学家",
                     primary: OstrichColors.ink.opacity(0.45),
                     secondary: OstrichColors.cream),
        EggArchetype(eggType: 14, archetype: "RATIONALIST", displayName: "工程师",
                     primary: OstrichColors.cream,
                     secondary: OstrichColors.ink.opacity(0.55)),
        EggArchetype(eggType: 15, archetype: "NIGHTOWL", displayName: "守夜人",
                     primary: OstrichColors.ink.opacity(0.6),
                     secondary: OstrichColors.orange),
        EggArchetype(eggType: 16, archetype: "SUNSHINE", displayName: "乐天派",
                     primary: OstrichColors.orange,
                     secondary: OstrichColors.cream)
    ]
}

// MARK: - 请求体

/// `/api/awaken` body（INTERFACES.md §1.2）。
public struct AwakenRequest: Encodable {
    public let eggType: Int
    public let name: String
    public let userMbti: String
    public let userZodiac: String
    /// 新流程在 Step4 收集用户自己的名字，后端可选用。
    public let userName: String?

    public init(
        eggType: Int,
        name: String,
        userMbti: String,
        userZodiac: String,
        userName: String? = nil
    ) {
        self.eggType = eggType
        self.name = name
        self.userMbti = userMbti
        self.userZodiac = userZodiac
        self.userName = userName
    }
}

/// `/api/chat/send` body（INTERFACES.md §1.3）。
public struct SendMessageRequest: Encodable {
    public let roomId: String
    public let content: String

    public init(roomId: String, content: String) {
        self.roomId = roomId
        self.content = content
    }
}
