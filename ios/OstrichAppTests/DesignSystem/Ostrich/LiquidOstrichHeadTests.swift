import Testing
import CoreGraphics
@testable import OstrichApp

/// 液态鸵鸟头单测。
///
/// 重点验证：
/// - SimplexNoise 与 simplex-noise.js 2.4.0 (`new SimplexNoise(string)`) 输出一致；
/// - PathParser 把 16 个 v4 path 解析出与 JS `parsePath` 等价的顶点数；
/// - LiquidOstrichHeadView 实例化不崩溃。
///
/// 对照值在 Node 端用以下脚本生成（保留作为可复现说明）：
/// ```
/// npm install simplex-noise@2.4.0
/// node -e "const S = require('simplex-noise'); const x = new S('ostrich-x'); console.log(x.noise3D(...))"
/// ```
struct LiquidOstrichHeadTests {

    // MARK: - SimplexNoise vs JS reference

    /// 3D noise 输出对照 —— 误差应 < 1e-6（实际通常 < 1e-12）。
    @Test func simplexNoise3DMatchesJSReference_X() {
        let s = SimplexNoise(seed: "ostrich-x")
        // 数据来自 Node simplex-noise@2.4.0 + seed "ostrich-x" + noise3D。
        let fixtures: [(x: Double, y: Double, z: Double, expected: Double)] = [
            (0, 0, 0, 0.0),
            (0.5, 0.5, 0.5, 0.0),
            (1.2, -3.4, 7.8, -0.323761360329218),
            (10, 20, 30, 0.0),
            (100.1, -50.2, 0.001, -0.342680410177441),
            (-7.7, 7.7, -7.7, -0.008642016395059),
            (293 * 0.030, 360 * 0.030, 0.0, -0.150577545800324),
            (293 * 0.030, 360 * 0.030, 1.0, 0.451797602380983),
            (293 * 0.030, 360 * 0.030, 10.0, 0.029133923307859),
            (318.47 * 0.030, 240.62 * 0.030, 5.5, 0.610026789120110)
        ]
        for f in fixtures {
            let got = s.noise3D(f.x, f.y, f.z)
            #expect(
                abs(got - f.expected) < 1e-6,
                "noise3D(\(f.x), \(f.y), \(f.z)) = \(got), expected \(f.expected)"
            )
        }
    }

    @Test func simplexNoise3DMatchesJSReference_Y() {
        let s = SimplexNoise(seed: "ostrich-y")
        let fixtures: [(x: Double, y: Double, z: Double, expected: Double)] = [
            (0, 0, 0, 0.0),
            (0.5, 0.5, 0.5, 0.0),
            (1.2, -3.4, 7.8, 0.050139314041150),
            (10, 20, 30, 0.0),
            (100.1, -50.2, 0.001, 0.220788977942945),
            (-7.7, 7.7, -7.7, -0.641355390419756),
            (293 * 0.030, 360 * 0.030, 0.0, 0.427570081997428),
            (293 * 0.030, 360 * 0.030, 1.0, 0.452240552777956),
            (293 * 0.030, 360 * 0.030, 10.0, 0.471536282540530),
            (318.47 * 0.030, 240.62 * 0.030, 5.5, 0.744869496647072)
        ]
        for f in fixtures {
            let got = s.noise3D(f.x, f.y, f.z)
            #expect(
                abs(got - f.expected) < 1e-6,
                "noise3D(\(f.x), \(f.y), \(f.z)) = \(got), expected \(f.expected)"
            )
        }
    }

    @Test func simplexNoise2DMatchesJSReference() {
        let s = SimplexNoise(seed: "ostrich-x")
        let fixtures: [(x: Double, y: Double, expected: Double)] = [
            (0, 0, 0.0),
            (0.5, 0.5, -0.307156513627216),
            (1.2, -3.4, -0.545488446349310),
            (10, 20, 0.048497275917192),
            (100.1, -50.2, -0.621847429458101),
            (-7.7, 7.7, 0.581294340901520),
            (293 * 0.030, 360 * 0.030, 0.064984395751269),
            (318.47 * 0.030, 240.62 * 0.030, 0.044384805082565)
        ]
        for f in fixtures {
            let got = s.noise2D(f.x, f.y)
            #expect(
                abs(got - f.expected) < 1e-6,
                "noise2D(\(f.x), \(f.y)) = \(got), expected \(f.expected)"
            )
        }
    }

    /// 不同 seed 必须产生不同序列。
    @Test func simplexNoiseDifferentSeedsDiffer() {
        let sx = SimplexNoise(seed: "ostrich-x")
        let sy = SimplexNoise(seed: "ostrich-y")
        // 整数 lattice 上 simplex 噪声常落在 0；用非整数点对照。
        #expect(sx.noise3D(1.2, -3.4, 7.8) != sy.noise3D(1.2, -3.4, 7.8))
    }

    /// 同 seed 必须严格可复现。
    @Test func simplexNoiseDeterministic() {
        let a = SimplexNoise(seed: "ostrich-x")
        let b = SimplexNoise(seed: "ostrich-x")
        for i in 0..<50 {
            let v = Double(i) * 0.137
            #expect(a.noise3D(v, v * 2, v * 3) == b.noise3D(v, v * 2, v * 3))
        }
    }

    // MARK: - PathParser

    /// HEAD path 是抖动主体 —— 顶点数必须正确解析。
    /// v4 HEAD = 1×M + 41×C => 1 + 41*3 = 124 个顶点。
    /// 校对：`re.findall(r'[A-Za-z]|-?\d+\.?\d*', d).count('C')` 对 v4 HEAD 得 41。
    @Test func parseHeadPathPointCount() {
        let parsed = PathParser.parse(OstrichPaths.HEAD)
        let moveCount = parsed.segments.filter { $0.cmd == .moveTo }.count
        let curveCount = parsed.segments.filter { $0.cmd == .curveTo }.count
        #expect(moveCount == 1)
        #expect(curveCount == 41)
        #expect(parsed.allPoints.count == moveCount + curveCount * 3)
        #expect(parsed.allPoints.count == 124)
    }

    /// DRIP 是单一闭合曲线 —— 1 个 M + 4 个 C。
    @Test func parseDripPathPointCount() {
        let parsed = PathParser.parse(OstrichPaths.DRIP)
        let moveCount = parsed.segments.filter { $0.cmd == .moveTo }.count
        let curveCount = parsed.segments.filter { $0.cmd == .curveTo }.count
        #expect(moveCount == 1)
        #expect(curveCount == 4)
        #expect(parsed.allPoints.count == 13)
    }

    /// BEAK 是唯一含 L 和 Z 的 path —— 确保 LineTo / Close 命令被识别。
    @Test func parseBeakPathHandlesLineAndClose() {
        let parsed = PathParser.parse(OstrichPaths.BEAK)
        let lineCount = parsed.segments.filter { $0.cmd == .lineTo }.count
        let closeCount = parsed.segments.filter { $0.cmd == .close }.count
        #expect(lineCount >= 1)
        #expect(closeCount >= 1)
    }

    /// 所有 16 个 path 都应解析为非空段列表。
    @Test func allPathsParseNonEmpty() {
        let allPaths: [(String, String)] = [
            ("LEG_RIGHT", OstrichPaths.LEG_RIGHT),
            ("LEG_LEFT", OstrichPaths.LEG_LEFT),
            ("KNEE_DETAIL", OstrichPaths.KNEE_DETAIL),
            ("BODY", OstrichPaths.BODY),
            ("HEAD", OstrichPaths.HEAD),
            ("RUFF", OstrichPaths.RUFF),
            ("NECK_LOWER", OstrichPaths.NECK_LOWER),
            ("NECK_MID", OstrichPaths.NECK_MID),
            ("EYE_WHITES", OstrichPaths.EYE_WHITES),
            ("PUPIL_R", OstrichPaths.PUPIL_R),
            ("PUPIL_L", OstrichPaths.PUPIL_L),
            ("BEAK", OstrichPaths.BEAK),
            ("BEAK_DOT", OstrichPaths.BEAK_DOT),
            ("DRIP", OstrichPaths.DRIP),
            ("SPARKLE_R", OstrichPaths.SPARKLE_R),
            ("SPARKLE_L", OstrichPaths.SPARKLE_L)
        ]
        #expect(allPaths.count == 16)
        for (name, d) in allPaths {
            let parsed = PathParser.parse(d)
            #expect(!parsed.segments.isEmpty, "\(name) parsed to empty segments")
            #expect(parsed.segments.first?.cmd == .moveTo, "\(name) does not start with M")
        }
    }

    // MARK: - Tokenizer edge cases

    @Test func tokenizeHandlesNegativeAndDecimal() {
        let tokens = PathParser.tokenize("M -1.5 2.25 C 0 -.5 .75 1 -.123 .456")
        #expect(tokens.contains("M"))
        #expect(tokens.contains("-1.5"))
        #expect(tokens.contains("2.25"))
        #expect(tokens.contains("C"))
    }

    // MARK: - View construction

    @Test func liquidOstrichHeadViewInstantiates() {
        // 仅验证不崩 —— 视图渲染由 TimelineView 驱动，单测里不跑 RunLoop。
        let view = LiquidOstrichHeadView(mood: 0.5, size: 320)
        #expect(view.size == 320)
        #expect(view.mood == 0.5)
    }

    @Test func buildWobblePathProducesNonEmptyPath() {
        let parsed = PathParser.parse(OstrichPaths.HEAD)
        let path = PathParser.buildWobblePath(parsed: parsed) { _, p in p }
        #expect(!path.isEmpty)
        // bounding box 应该落在 HEAD 的大致区域 (x∈[240,350], y∈[245,475])
        let bb = path.boundingBoxOfPath
        #expect(bb.minX > 200 && bb.maxX < 400)
        #expect(bb.minY > 200 && bb.maxY < 500)
    }
}
