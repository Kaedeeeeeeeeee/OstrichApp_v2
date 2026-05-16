import SwiftUI

/// 鸵鸟字体层级。SF Rounded，主体偏重 (700-800)，对齐 v4 HTML `.copy-block h1` 等定义。
public enum OstrichTypography {
    /// 36pt heavy — 主标题 (对齐 v4 `.copy-block h1`)
    public static let largeTitle: Font = .system(size: 36, weight: .heavy, design: .rounded)

    /// 24pt bold — 二级标题
    public static let title: Font = .system(size: 24, weight: .bold, design: .rounded)

    /// 20pt bold — 段头 / headline
    public static let headline: Font = .system(size: 20, weight: .bold, design: .rounded)

    /// 15pt medium — 正文 (对齐 v4 `.copy-block p`)
    public static let body: Font = .system(size: 15, weight: .medium, design: .rounded)

    /// 13pt medium — 辅助说明 / hint (对齐 v4 `.grab-hint`)
    public static let callout: Font = .system(size: 13, weight: .medium, design: .rounded)

    /// 11pt regular — 极小注释
    public static let caption: Font = .system(size: 11, weight: .regular, design: .rounded)
}
