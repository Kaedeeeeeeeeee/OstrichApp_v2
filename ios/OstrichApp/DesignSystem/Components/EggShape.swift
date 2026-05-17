import SwiftUI

/// 真正的蛋型 SwiftUI Shape —— 上窄下宽，左右对称。
/// 用 4 段 cubic Bezier 拼接 4 个象限，控制点经验值校准成"鸡蛋"轮廓。
///
/// 用于 Onboarding 选蛋页 (Step4EggBlindBoxView) 和 Step5 破壳动画。
/// 不要用 `RoundedRectangle` 当蛋，那是药丸不是蛋。
public struct EggShape: Shape {

    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let topY = rect.minY
        let bottomY = rect.maxY

        // 最宽线在距顶 60% 处（egg 下半部更胖）
        let middleY = topY + h * 0.60
        let halfW = w / 2

        // 控制点经验值：
        // - 底部圆润 → bottom 端 horizontal-tangent control 占 halfW 的 0.55
        // - 顶部尖一些 → top 端 horizontal-tangent control 占 halfW 的 0.42
        // - middle 处 vertical-tangent 控制点离中线越远 + 离 middleY 越远 → 椭球感越强
        let bottomHorizCtrl: CGFloat = halfW * 0.55
        let topHorizCtrl: CGFloat = halfW * 0.42
        let bottomVertCtrl: CGFloat = h * 0.22  // middle 控制点向下推
        let topVertCtrl: CGFloat = h * 0.28     // middle 控制点向上拉

        // 起点：底部正中
        path.move(to: CGPoint(x: cx, y: bottomY))

        // 1. 右下：bottom → middle-right
        path.addCurve(
            to: CGPoint(x: cx + halfW, y: middleY),
            control1: CGPoint(x: cx + bottomHorizCtrl, y: bottomY),
            control2: CGPoint(x: cx + halfW, y: middleY + bottomVertCtrl)
        )

        // 2. 右上：middle-right → top（窄一点）
        path.addCurve(
            to: CGPoint(x: cx, y: topY),
            control1: CGPoint(x: cx + halfW, y: middleY - topVertCtrl),
            control2: CGPoint(x: cx + topHorizCtrl, y: topY)
        )

        // 3. 左上：top → middle-left（镜像）
        path.addCurve(
            to: CGPoint(x: cx - halfW, y: middleY),
            control1: CGPoint(x: cx - topHorizCtrl, y: topY),
            control2: CGPoint(x: cx - halfW, y: middleY - topVertCtrl)
        )

        // 4. 左下：middle-left → bottom
        path.addCurve(
            to: CGPoint(x: cx, y: bottomY),
            control1: CGPoint(x: cx - halfW, y: middleY + bottomVertCtrl),
            control2: CGPoint(x: cx - bottomHorizCtrl, y: bottomY)
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        EggShape()
            .fill(OstrichColors.orange)
            .frame(width: 80, height: 110)
        EggShape()
            .fill(OstrichColors.cream)
            .overlay(
                EggShape()
                    .stroke(OstrichColors.ink.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 80, height: 110)
        EggShape()
            .fill(OstrichColors.ink)
            .frame(width: 80, height: 110)
    }
    .padding()
    .background(OstrichColors.bodyBackground)
}
