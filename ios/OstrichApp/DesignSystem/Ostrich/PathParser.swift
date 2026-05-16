import CoreGraphics
import Foundation

/// SVG path 解析 —— 1:1 复刻 v4 HTML `parsePath(d)`。
///
/// 只支持 v4 PATHS 实际用到的命令：
/// - `M x y`            起始点
/// - `C x1 y1 x2 y2 x3 y3`  三阶贝塞尔
/// - `L x y`            直线（仅 BEAK 用了 `L` 和 `Z`，需要支持）
/// - `Z`                闭合（不消耗点）
///
/// 解析输出是 `[(cmd, points)]` 形式，每条命令携带相邻的控制点列表 ——
/// 与 JS 端 `cmds + points` 双数组等价，只是在 Swift 里合成更易用。
public struct ParsedPath: Equatable {
    public enum Command: Equatable { case moveTo, curveTo, lineTo, close }

    public struct Segment: Equatable {
        public let cmd: Command
        public let points: [CGPoint]   // moveTo/lineTo = 1, curveTo = 3, close = 0
    }

    public let segments: [Segment]

    /// 所有按出现顺序展开的顶点 —— buildWobbleD 会按这个顺序扰动。
    public var allPoints: [CGPoint] { segments.flatMap { $0.points } }
}

public enum PathParser {

    /// 解析 SVG path。token 化与 v4 JS 一致：
    /// `d.match(/[A-Za-z]|-?\d+\.?\d*/g)`。
    public static func parse(_ d: String) -> ParsedPath {
        let tokens = tokenize(d)
        var segments: [ParsedPath.Segment] = []
        var i = 0
        while i < tokens.count {
            let c = tokens[i]; i += 1
            switch c {
            case "M":
                let x = Double(tokens[i]) ?? 0; i += 1
                let y = Double(tokens[i]) ?? 0; i += 1
                segments.append(.init(cmd: .moveTo, points: [CGPoint(x: x, y: y)]))
            case "C":
                var pts: [CGPoint] = []
                for _ in 0..<3 {
                    let x = Double(tokens[i]) ?? 0; i += 1
                    let y = Double(tokens[i]) ?? 0; i += 1
                    pts.append(CGPoint(x: x, y: y))
                }
                segments.append(.init(cmd: .curveTo, points: pts))
            case "L":
                let x = Double(tokens[i]) ?? 0; i += 1
                let y = Double(tokens[i]) ?? 0; i += 1
                segments.append(.init(cmd: .lineTo, points: [CGPoint(x: x, y: y)]))
            case "Z", "z":
                segments.append(.init(cmd: .close, points: []))
            default:
                // 未识别 token —— 跳过
                continue
            }
        }
        return ParsedPath(segments: segments)
    }

    /// 等价 JS 正则 `/[A-Za-z]|-?\d+\.?\d*/g`。
    static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isLetter {
                out.append(String(ch))
                i += 1
            } else if ch == "-" || ch.isNumber || ch == "." {
                var j = i
                if chars[j] == "-" { j += 1 }
                while j < chars.count && chars[j].isNumber { j += 1 }
                if j < chars.count && chars[j] == "." {
                    j += 1
                    while j < chars.count && chars[j].isNumber { j += 1 }
                }
                if j > i {
                    out.append(String(chars[i..<j]))
                    i = j
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return out
    }

    /// 给定原始 path 和当前的扰动函数 (idx, point) -> CGPoint，重建一个新的
    /// SwiftUI `Path`。等价于 v4 HTML 的 `buildWobbleD(parsed, t, amp)`。
    public static func buildWobblePath(
        parsed: ParsedPath,
        wobble: (Int, CGPoint) -> CGPoint
    ) -> CGPath {
        let path = CGMutablePath()
        var pointIndex = 0
        var currentPoint: CGPoint = .zero
        for seg in parsed.segments {
            switch seg.cmd {
            case .moveTo:
                let p = wobble(pointIndex, seg.points[0])
                pointIndex += 1
                path.move(to: p)
                currentPoint = p
            case .curveTo:
                let p1 = wobble(pointIndex, seg.points[0]); pointIndex += 1
                let p2 = wobble(pointIndex, seg.points[1]); pointIndex += 1
                let p3 = wobble(pointIndex, seg.points[2]); pointIndex += 1
                path.addCurve(to: p3, control1: p1, control2: p2)
                currentPoint = p3
            case .lineTo:
                let p = wobble(pointIndex, seg.points[0])
                pointIndex += 1
                path.addLine(to: p)
                currentPoint = p
            case .close:
                path.closeSubpath()
            }
            _ = currentPoint
        }
        return path
    }

    /// 不带扰动的静态 path —— legs/body/eyes 这类需要原样渲染的形状。
    public static func staticPath(parsed: ParsedPath) -> CGPath {
        buildWobblePath(parsed: parsed) { _, p in p }
    }
}
