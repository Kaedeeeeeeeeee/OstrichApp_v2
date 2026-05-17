// EndpointPaths.swift
// INTERFACES.md §1 字面常量。修改前先改 INTERFACES.md。

import Foundation

public enum Endpoints {
    // 1.1 鉴权
    public static let signInWithApple = "/api/auth/signInWithApple"
    public static let signOut = "/api/auth/signOut"

    // 1.2 鸵鸟唤醒 + 状态
    public static let awaken = "/api/awaken"
    public static let ostrichSelf = "/api/ostrich/self"
    public static let callHome = "/api/ostrich/callHome"
    public static let allowToStay = "/api/ostrich/allowToStay"
    /// 进 wander tab 时调，把鸵鸟切到 wandering 并 fire-and-forget 触发首次 decideNextMove。
    public static let wanderStart = "/api/wander/start"

    // 1.2.1 鸵鸟内心独白（头顶气泡）
    /// POST：立刻建一行 ostrich_thoughts(streaming)，返回 thoughtId，后台流式填内容
    public static let think = "/api/ostrich/think"
    /// GET：轮询拿 content + status。后接 thoughtId。
    public static let thought = "/api/ostrich/thought/"

    // 1.3 传心
    public static let chatSend = "/api/chat/send"
    public static let chatRoom = "/api/chat/room/"           // + roomId
    public static let confirmAddPerson = "/api/chat/confirmAddPerson"

    // 1.4 关系图谱
    public static let graph = "/api/graph"
    public static let categorize = "/api/graph/categorize"
    public static let personRoom = "/api/graph/personRoom/"  // + personId

    // 1.5 日记
    public static let diary = "/api/diary"
    public static let requestUnlock = "/api/diary/requestUnlock"

    // 1.6 地图
    public static let mapGod = "/api/map/godView"
    public static let mapLocal = "/api/map/localView"

    // 1.7 设置 / 「如果有一天我不在了」
    public static let sealOstrichInEgg = "/api/settings/sealOstrichInEgg"
    public static let release = "/api/settings/release"
    public static let transfer = "/api/settings/transfer"
}
