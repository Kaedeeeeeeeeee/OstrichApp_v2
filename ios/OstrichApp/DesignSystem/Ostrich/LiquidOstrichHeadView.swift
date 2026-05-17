import SwiftUI
import os

/// 液态鸵鸟头 —— v4 HTML React 版本的 SwiftUI 移植。
///
/// 性能要求：30fps 锁帧（Phase 1 §16.1 R1）。
/// 渲染策略：
/// - 静态层（腿/身体/眼/喙/闪光）在每帧的 Canvas 内重绘，但 path 预解析；
/// - 动态层（HEAD / DRIP）每帧用 simplex-noise 重建顶点；
/// - 脖子（NECK）用程序化 bezier tube 而非原 path，根据 head 偏移柔性变形。
///
/// 来源：`shared/reference/v4_liquid_ostrich.html` `Ostrich` 组件。
public struct LiquidOstrichHeadView: View {

    // MARK: - Public API

    /// 心情 0..1（保留接口，目前未用于渲染差异化）。
    public var mood: Double

    /// 视图尺寸（正方形）。`nil` = 填满父容器（推荐用于 Onboarding/Home 全屏 hero，
    /// 按 v4 HTML `.stage { position: absolute; inset: 0 }` 的语义铺满）。
    /// 数值 = 强制方形 size×size（适合 inline 小尺寸用法）。
    public var size: CGFloat?

    public init(mood: Double = 0.5, size: CGFloat? = nil) {
        self.mood = mood
        self.size = size
    }

    // MARK: - State

    /// 拖拽偏移 —— SwiftUI 默认坐标。在 Canvas 内会换算到 v4 viewBox 空间。
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // MARK: - Precomputed paths

    private static let headParsed = PathParser.parse(OstrichPaths.HEAD)
    private static let dripParsed = PathParser.parse(OstrichPaths.DRIP)

    private static let legLeftPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.LEG_LEFT))
    private static let legRightPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.LEG_RIGHT))
    private static let kneeDetailPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.KNEE_DETAIL))
    private static let bodyPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.BODY))
    private static let ruffPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.RUFF))
    private static let eyeWhitesPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.EYE_WHITES))
    private static let pupilLPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.PUPIL_L))
    private static let pupilRPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.PUPIL_R))
    private static let beakPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.BEAK))
    private static let beakDotPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.BEAK_DOT))
    private static let sparkleRPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.SPARKLE_R))
    private static let sparkleLPath = PathParser.staticPath(parsed: PathParser.parse(OstrichPaths.SPARKLE_L))

    // MARK: - Simplex generators (seed 与 v4 HTML 完全一致)

    private static let simplexX = SimplexNoise(seed: "ostrich-x")
    private static let simplexY = SimplexNoise(seed: "ostrich-y")

    /// v4 默认空间频率 —— 不能改，改了 wobble 视觉就走样。
    private static let SPACE_SCALE: Double = 0.030

    // MARK: - viewBox constants (与 HTML svg viewBox="125 135 330 720" 一致)

    private static let viewBoxOrigin = CGPoint(x: 125, y: 135)
    private static let viewBoxSize = CGSize(width: 330, height: 720)

    /// head 静止位置（HOME） —— 用作 head/drip 平移基准。
    private static let HOME = CGPoint(x: 293, y: 360)
    /// 衣领锚点（COLLAR） —— 脖子起点。
    private static let COLLAR = CGPoint(x: 293, y: 600)
    private static let NECK_OVERLAP: CGFloat = 30

    // MARK: - Body

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: false)) { context in
            Canvas { ctx, canvasSize in
                let now = context.date
                Self.recordFrame(now: now)
                let t = now.timeIntervalSinceReferenceDate

                // 计算 viewBox -> canvas 的缩放和偏移（保持 aspect ratio，xMidYMid meet）
                let scaleX = canvasSize.width / Self.viewBoxSize.width
                let scaleY = canvasSize.height / Self.viewBoxSize.height
                let scale = min(scaleX, scaleY)
                let drawnW = Self.viewBoxSize.width * scale
                let drawnH = Self.viewBoxSize.height * scale
                let offsetX = (canvasSize.width - drawnW) / 2 - Self.viewBoxOrigin.x * scale
                let offsetY = (canvasSize.height - drawnH) / 2 - Self.viewBoxOrigin.y * scale

                // 把 viewBox 坐标系叠在 canvas 上
                ctx.translateBy(x: offsetX, y: offsetY)
                ctx.scaleBy(x: scale, y: scale)

                // 拖拽偏移（用户在 canvas 像素空间拖动，需要除以 scale 进入 viewBox 空间）
                let dragVbDX = dragOffset.width / scale
                let dragVbDY = dragOffset.height / scale

                // head 当前位置（HOME + drag）
                let headX = Self.HOME.x + dragVbDX
                // 允许向下推但不能穿过身体（v4 中 540 是 ty 的下限）
                let rawHeadY = Self.HOME.y + dragVbDY
                let headY: CGFloat = min(540, rawHeadY)

                // ─── 1. 腿（最底层，静态） ───────────────────────────
                ctx.fill(Path(Self.legLeftPath), with: .color(OstrichColor.leg))
                ctx.fill(Path(Self.legRightPath), with: .color(OstrichColor.leg))
                ctx.fill(Path(Self.kneeDetailPath), with: .color(OstrichColor.knee))

                // ─── 2. 程序化脖子（在身体之前画，body 会盖住根部） ───
                let neckPath = Self.buildNeckPath(
                    headX: headX, headY: headY,
                    velocityX: 0, velocityY: 0  // 简化：不用速度反馈
                )
                ctx.fill(Path(neckPath), with: .color(OstrichColor.orange))

                // ─── 3. 身体（覆盖脖子根部） ───────────────────────
                ctx.fill(Path(Self.bodyPath), with: .color(OstrichColor.body))

                // ─── 4. 颈毛（白色） ───────────────────────────────
                ctx.fill(Path(Self.ruffPath), with: .color(OstrichColor.ruff))

                // ─── 5. 头（液态扰动） ────────────────────────────
                // head/features 整体平移（tilt 简化，不旋转避免 Canvas 旋转开销）
                let tdx = headX - Self.HOME.x
                let tdy = headY - Self.HOME.y

                var headCtx = ctx
                headCtx.translateBy(x: tdx, y: tdy)

                // wobble 幅度 —— 拖拽时增大
                let speed = sqrt(dragVbDX * dragVbDX + dragVbDY * dragVbDY) * 0.05
                let headAmp = 6.0 + min(10.0, speed)

                let headPath = PathParser.buildWobblePath(parsed: Self.headParsed) { _, p in
                    Self.wobblePoint(p, t: t * 0.55, amp: headAmp)
                }

                // 头部 clip：准确复刻 v4 HTML 的 headClip
                // (`<rect x="0" y="0" width="595" height="360"/>`)。
                // 在 head group 平移后的坐标系内，保留 y ≤ 360 的区域，
                // 砍掉 HEAD path 底部的"肩膀/翅膀状"延伸（v4 SVG 设计里这部分
                // 由 body/procedural neck 视觉覆盖，但我们用程序化 bezier neck
                // 时会裸露出来）。x 范围用 0..595 全宽保险，反正 HEAD path
                // x ∈ [245, 350] 都在内。
                var headClipCtx = headCtx
                headClipCtx.clip(to: Path(CGRect(x: 0, y: 0, width: 595, height: 360)))
                headClipCtx.fill(Path(headPath), with: .color(OstrichColor.orange))

                // 滴液（独立 wobble，不 clip）
                let dripPath = PathParser.buildWobblePath(parsed: Self.dripParsed) { _, p in
                    Self.wobblePoint(p, t: t * 0.75, amp: 1.2)
                }
                headCtx.fill(Path(dripPath), with: .color(OstrichColor.orange))

                // ─── 6. 眼睛 + 瞳孔（不抖动，跟随头平移） ────────────
                headCtx.fill(Path(Self.eyeWhitesPath), with: .color(OstrichColor.eyeWhites))
                headCtx.fill(Path(Self.pupilLPath), with: .color(OstrichColor.pupil))
                headCtx.fill(Path(Self.pupilRPath), with: .color(OstrichColor.pupil))

                // ─── 7. 喙 ───────────────────────────────────────
                headCtx.fill(Path(Self.beakPath), with: .color(OstrichColor.beak))
                headCtx.fill(Path(Self.beakDotPath), with: .color(OstrichColor.beakDot))

                // ─── 8. 闪光（头本地坐标） ────────────────────────
                headCtx.fill(Path(Self.sparkleRPath), with: .color(OstrichColor.beakDot))
                headCtx.fill(Path(Self.sparkleLPath), with: .color(OstrichColor.beakDot))
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        isDragging = true
                    }
                    .onEnded { _ in
                        isDragging = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            dragOffset = .zero
                        }
                    }
            )
        }
        .modifier(SizingModifier(size: size))
    }

    /// 按 size 决定固定方形或填满父容器。
    private struct SizingModifier: ViewModifier {
        let size: CGFloat?
        func body(content: Content) -> some View {
            if let size {
                content.frame(width: size, height: size)
            } else {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - FPS instrumentation (Phase 1 §16.1 R1)

    /// 简单 FPS 计数 —— 每 ~1s 通过 os_log 打一次。
    /// 用 `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.ostrich.liquid"'` 抓取。
    private static let fpsLogger = Logger(subsystem: "com.ostrich.liquid", category: "fps")
    private static var frameTimesLock = os_unfair_lock()
    nonisolated(unsafe) private static var frameCount: Int = 0
    nonisolated(unsafe) private static var windowStart: Date = .init()

    private static func recordFrame(now: Date) {
        os_unfair_lock_lock(&frameTimesLock)
        defer { os_unfair_lock_unlock(&frameTimesLock) }
        if frameCount == 0 { windowStart = now }
        frameCount += 1
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            fpsLogger.log("liquid-ostrich fps=\(String(format: "%.1f", fps), privacy: .public)")
            // 也用 print 让 stdout 抓得到
            print("[LiquidOstrich] fps=\(String(format: "%.1f", fps))")
            frameCount = 0
            windowStart = now
        }
    }

    // MARK: - Wobble

    /// 等价 v4 `buildWobbleD` 内部循环：对单个顶点用 simplex noise 偏移。
    private static func wobblePoint(_ p: CGPoint, t: Double, amp: Double) -> CGPoint {
        let dx = simplexX.noise3D(Double(p.x) * SPACE_SCALE, Double(p.y) * SPACE_SCALE, t) * amp
        let dy = simplexY.noise3D(Double(p.x) * SPACE_SCALE, Double(p.y) * SPACE_SCALE, t) * amp
        return CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy))
    }

    // MARK: - Procedural neck

    /// 沿 COLLAR -> headTop 的二次贝塞尔 + 法线 offset 生成的 tapered tube。
    /// 简化版的 v4 `sampleBezier` 逻辑。
    private static func buildNeckPath(
        headX: CGFloat, headY: CGFloat,
        velocityX: CGFloat, velocityY: CGFloat
    ) -> CGPath {
        let neckTopX = headX
        let neckTopY = headY - NECK_OVERLAP
        let cpX = (COLLAR.x + neckTopX) / 2 - velocityX * 18 * 0.4
        let cpY = (COLLAR.y + neckTopY) / 2 + 8 + abs(velocityY) * 1.2

        struct SamplePoint { var x: CGFloat; var y: CGFloat; var nx: CGFloat; var ny: CGFloat }

        func sample(_ t: CGFloat) -> SamplePoint {
            let u = 1 - t
            let x = u*u*COLLAR.x + 2*u*t*cpX + t*t*neckTopX
            let y = u*u*COLLAR.y + 2*u*t*cpY + t*t*neckTopY
            let dx = 2*u*(cpX - COLLAR.x) + 2*t*(neckTopX - cpX)
            let dy = 2*u*(cpY - COLLAR.y) + 2*t*(neckTopY - cpY)
            let len = max(sqrt(dx*dx + dy*dy), 1)
            return SamplePoint(x: x, y: y, nx: -dy/len, ny: dx/len)
        }

        let wBase: CGFloat = 30
        let wTip: CGFloat = 23
        let segs = 14
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...segs {
            let tt = CGFloat(i) / CGFloat(segs)
            let tEase = tt * tt * (3 - 2 * tt)  // smoothstep
            let w = wBase * (1 - tEase) + wTip * tEase
            let p = sample(tt)
            left.append(CGPoint(x: p.x + p.nx * w, y: p.y + p.ny * w))
            right.append(CGPoint(x: p.x - p.nx * w, y: p.y - p.ny * w))
        }

        let path = CGMutablePath()
        path.move(to: left[0])
        for i in 1..<left.count { path.addLine(to: left[i]) }
        for i in stride(from: right.count - 1, through: 0, by: -1) {
            path.addLine(to: right[i])
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        LiquidOstrichHeadView(size: 360)
    }
}
