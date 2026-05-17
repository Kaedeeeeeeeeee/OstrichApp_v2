// LocalActivityVerb.swift
// Apple Maps POI category → 中文活动动词的映射。
//
// 后端 `currentIntention.destinationCategory` 透传 Apple Maps Server API 的
// poiCategory 原文（如 "Cafe" / "Park" / "Bookstore"）。当鸵鸟到达 resting 时，
// iOS 端把它转成一个简短的中文动词（"喝咖啡" / "歇会儿" / "翻翻书"），拼成
// "在 X [verb]..." 显示在 LocalView speech bubble 上。
//
// 不试图穷举 Apple Maps 上百个 category：用关键词包含匹配 + default 兜底。
// 顺序敏感（先匹配的优先），coffee/cafe 放前面避免被 "store" 截胡。

import Foundation

public enum LocalActivityVerb {

    /// 把 POI category 转成中文动词。
    /// - Parameter category: Apple Maps poiCategory 原文。可为 nil 或空串。
    /// - Returns: 简短动词（2-4 字）。未知 / 缺失 → "待着"。
    public static func verb(for category: String?) -> String {
        guard let raw = category?.lowercased(), !raw.isEmpty else {
            return "待着"
        }
        for rule in rules where rule.matches(raw) {
            return rule.verb
        }
        return "待着"
    }

    // MARK: - Rules

    private struct Rule {
        let keywords: [String]
        let verb: String
        func matches(_ lower: String) -> Bool {
            keywords.contains { lower.contains($0) }
        }
    }

    /// 顺序敏感 —— 先匹配的优先。
    /// 决定动词时优先考虑"消费/体验"动作而非"购物"动作（咖啡 vs 商店）。
    private static let rules: [Rule] = [
        Rule(keywords: ["cafe", "coffee"], verb: "喝咖啡"),
        Rule(keywords: ["bakery", "bread"], verb: "买面包"),
        Rule(keywords: ["restaurant", "food", "dining", "eatery", "ramen", "sushi", "izakaya"],
             verb: "吃东西"),
        Rule(keywords: ["bar", "pub", "nightlife", "brewery", "winery"], verb: "喝一杯"),
        Rule(keywords: ["park", "garden"], verb: "歇会儿"),
        Rule(keywords: ["beach"], verb: "看海"),
        Rule(keywords: ["book", "library"], verb: "翻翻书"),
        Rule(keywords: ["museum", "gallery", "art"], verb: "看展"),
        Rule(keywords: ["theater", "movie", "cinema"], verb: "看戏"),
        Rule(keywords: ["shrine", "temple", "religious", "church"], verb: "拜拜"),
        Rule(keywords: ["spa", "salon", "beauty"], verb: "放松"),
        Rule(keywords: ["hotel", "lodging", "resort"], verb: "歇脚"),
        Rule(keywords: ["aquarium", "zoo"], verb: "看动物"),
        Rule(keywords: ["amusement", "themepark"], verb: "玩玩"),
        Rule(keywords: ["historical", "tourist", "attraction", "landmark"], verb: "转一转"),
        Rule(keywords: ["station", "transit", "airport"], verb: "等车"),
        Rule(keywords: ["market", "grocery", "supermarket", "convenience"], verb: "买东西"),
        Rule(keywords: ["clothing", "store", "shop", "mall"], verb: "逛逛"),
    ]
}
