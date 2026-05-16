import SwiftUI

/// 鸵鸟 v4 视觉色板。
/// hex 来源：shared/reference/v4_liquid_ostrich.html 的 :root CSS variables。
public enum OstrichColors {
    /// #FCFEE8 — 主奶油 (按钮文字 / 卡片底)
    public static let cream = Color(
        red: 0xFC / 255.0,
        green: 0xFE / 255.0,
        blue: 0xE8 / 255.0
    )

    /// #F5EAB8 — 深奶油 (强调底色 / 蛋纹)
    public static let creamDeep = Color(
        red: 0xF5 / 255.0,
        green: 0xEA / 255.0,
        blue: 0xB8 / 255.0
    )

    /// #FC8B40 — 主橙 (高亮 / 心情活跃)
    public static let orange = Color(
        red: 0xFC / 255.0,
        green: 0x8B / 255.0,
        blue: 0x40 / 255.0
    )

    /// #CD4A0F — 深橙 (强调文字 splash / 重点)
    public static let orangeDeep = Color(
        red: 0xCD / 255.0,
        green: 0x4A / 255.0,
        blue: 0x0F / 255.0
    )

    /// #27281D — 墨色 (主文字 / 按钮底)
    public static let ink = Color(
        red: 0x27 / 255.0,
        green: 0x28 / 255.0,
        blue: 0x1D / 255.0
    )

    /// #DBD3B8 — body 背景 (整体奶油浅褐)
    public static let bodyBackground = Color(
        red: 0xDB / 255.0,
        green: 0xD3 / 255.0,
        blue: 0xB8 / 255.0
    )
}
