import CoreGraphics

/// 间距 token (pt)。
public enum OstrichSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 28
}

/// 圆角 token (pt)。pill = 999 表示完全圆角胶囊 (对齐 v4 `.cta`)。
public enum OstrichRadius {
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 14
    public static let large: CGFloat = 18
    public static let pill: CGFloat = 999
}
