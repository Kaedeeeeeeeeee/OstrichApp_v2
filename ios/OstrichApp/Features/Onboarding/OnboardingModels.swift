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
    /// 颜色按 archetype 性格调性选，覆盖红/橙/黄/绿/蓝/紫/灰/棕 8 个色相，
    /// 相邻两蛋色相差距足够大，盲盒陈列时一眼能区分。
    /// 选中态描边走 ink，所以 primary 都避开纯黑。
    public static let all: [EggArchetype] = [
        EggArchetype(eggType: 1, archetype: "STEADFAST", displayName: "守望者",
                     primary: Color(red: 0.29, green: 0.34, blue: 0.46),   // 深蓝灰
                     secondary: Color(red: 0.78, green: 0.82, blue: 0.87)), // 雾银
        EggArchetype(eggType: 2, archetype: "POET", displayName: "诗人",
                     primary: Color(red: 0.61, green: 0.48, blue: 0.72),   // 薰衣紫
                     secondary: Color(red: 0.86, green: 0.78, blue: 0.91)), // 浅紫
        EggArchetype(eggType: 3, archetype: "STRAIGHTSHOOTER", displayName: "直心客",
                     primary: Color(red: 0.85, green: 0.33, blue: 0.31),   // 朱砂红
                     secondary: Color(red: 0.97, green: 0.89, blue: 0.76)), // 奶
        EggArchetype(eggType: 4, archetype: "CUDDLER", displayName: "甜心",
                     primary: Color(red: 0.95, green: 0.65, blue: 0.75),   // 樱花粉
                     secondary: Color(red: 1.00, green: 0.85, blue: 0.75)), // 蜜桃
        EggArchetype(eggType: 5, archetype: "WORLDLY", displayName: "老炮儿",
                     primary: Color(red: 0.55, green: 0.44, blue: 0.30),   // 烟褐
                     secondary: Color(red: 0.83, green: 0.71, blue: 0.50)), // 沙金
        EggArchetype(eggType: 6, archetype: "MAVERICK", displayName: "鬼才",
                     primary: Color(red: 0.91, green: 0.83, blue: 0.23),   // 电柠檬黄
                     secondary: Color(red: 0.15, green: 0.15, blue: 0.18)), // 墨黑
        EggArchetype(eggType: 7, archetype: "STOIC", displayName: "冷哲",
                     primary: Color(red: 0.44, green: 0.48, blue: 0.52),   // 钢冷灰
                     secondary: Color(red: 0.93, green: 0.94, blue: 0.96)), // 雪白
        EggArchetype(eggType: 8, archetype: "WATCHER", displayName: "观察者",
                     primary: Color(red: 0.36, green: 0.50, blue: 0.35),   // 苔森绿
                     secondary: Color(red: 0.75, green: 0.85, blue: 0.65)), // 嫩绿
        EggArchetype(eggType: 9, archetype: "HEDONIST", displayName: "美食家",
                     primary: Color(red: 0.88, green: 0.64, blue: 0.23),   // 蜂蜜金
                     secondary: Color(red: 0.95, green: 0.78, blue: 0.40)), // 橙金
        EggArchetype(eggType: 10, archetype: "INNOCENT", displayName: "童心",
                     primary: Color(red: 0.48, green: 0.72, blue: 0.90),   // 晴空蓝
                     secondary: Color(red: 0.92, green: 0.96, blue: 0.99)), // 云白
        EggArchetype(eggType: 11, archetype: "PROTECTOR", displayName: "仗义客",
                     primary: Color(red: 0.42, green: 0.48, blue: 0.24),   // 橄榄军绿
                     secondary: Color(red: 0.78, green: 0.74, blue: 0.50)), // 卡其
        EggArchetype(eggType: 12, archetype: "ELDER", displayName: "长者",
                     primary: Color(red: 0.55, green: 0.42, blue: 0.30),   // 老茶棕
                     secondary: Color(red: 0.92, green: 0.85, blue: 0.72)), // 米杏
        EggArchetype(eggType: 13, archetype: "MYSTIC", displayName: "玄学家",
                     primary: Color(red: 0.37, green: 0.24, blue: 0.61),   // 靛紫
                     secondary: Color(red: 0.85, green: 0.78, blue: 0.95)), // 星辉
        EggArchetype(eggType: 14, archetype: "RATIONALIST", displayName: "工程师",
                     primary: Color(red: 0.30, green: 0.49, blue: 0.69),   // 钢蓝
                     secondary: Color(red: 0.78, green: 0.85, blue: 0.92)), // 银
        EggArchetype(eggType: 15, archetype: "NIGHTOWL", displayName: "守夜人",
                     primary: Color(red: 0.16, green: 0.23, blue: 0.36),   // 午夜蓝
                     secondary: Color(red: 0.96, green: 0.86, blue: 0.45)), // 星黄
        EggArchetype(eggType: 16, archetype: "SUNSHINE", displayName: "乐天派",
                     primary: Color(red: 0.96, green: 0.63, blue: 0.25),   // 暖橙
                     secondary: Color(red: 1.00, green: 0.87, blue: 0.50)) // 阳光黄
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
