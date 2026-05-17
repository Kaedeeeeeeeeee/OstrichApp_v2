// GodViewView.swift
// 上帝视角：暗色背景 + 闪烁鸵鸟密度点 + 「召回我的鸵鸟」按钮。
// BLUEPRINT §10.3 GodView：
//   - 不渲染真实地图，只一片暗色背景 + 闪烁的点
//   - 点的密度 = 该区域鸵鸟数（来自 map_cells 聚合）
//   - 不暴露任何具体身份 / 坐标

import SwiftUI

struct GodViewView: View {

    let client: ConvexClientProtocol
    let onRecall: () -> Void

    @State private var points: [GodViewPoint] = GodViewPoint.makeFallback(seed: 1)
    @State private var ostrichCount: Int = 24
    @State private var t: Double = 0
    @State private var pollTask: Task<Void, Never>?

    // 深色「上帝视角」专用背景 #1A1714（不用 OstrichColors.bodyBackground）。
    private let darkBackground = Color(
        red: 0x1A / 255.0,
        green: 0x17 / 255.0,
        blue: 0x14 / 255.0
    )

    var body: some View {
        ZStack {
            darkBackground.ignoresSafeArea()

            // 闪烁点 Canvas。
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                Canvas { ctx, size in
                    let now = context.date.timeIntervalSinceReferenceDate
                    for p in points {
                        let cx = p.x * size.width
                        let cy = p.y * size.height
                        // 用 sin/cos 制造低频呼吸 + 个体相位差，无须 simplex 噪声开销。
                        let phase = now * (0.4 + p.speed) + p.phase
                        let osc = 0.5 + 0.5 * sin(phase)
                        let alpha = 0.18 + 0.55 * osc * (p.isSelf ? 1.0 : 0.7)
                        let radius = (p.isSelf ? 6.5 : 2.4) + (p.isSelf ? 2.5 : 1.2) * osc
                        let color = p.isSelf
                            ? Color(red: 0xFC / 255.0, green: 0x8B / 255.0, blue: 0x40 / 255.0).opacity(alpha)
                            : Color(red: 0xF5 / 255.0, green: 0xEA / 255.0, blue: 0xB8 / 255.0).opacity(alpha)
                        let rect = CGRect(
                            x: cx - radius,
                            y: cy - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                        if p.isSelf {
                            // 自己的鸵鸟外加一圈光晕。
                            let halo = CGRect(
                                x: cx - radius - 8,
                                y: cy - radius - 8,
                                width: (radius + 8) * 2,
                                height: (radius + 8) * 2
                            )
                            ctx.fill(
                                Path(ellipseIn: halo),
                                with: .color(
                                    Color(red: 0xFC / 255.0, green: 0x8B / 255.0, blue: 0x40 / 255.0)
                                        .opacity(0.08 + 0.08 * osc)
                                )
                            )
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack {
                topCaption
                    .padding(.top, OstrichSpacing.xl)
                Spacer()
                recallButton
                    .padding(.horizontal, OstrichSpacing.xxl)
                    .padding(.bottom, OstrichSpacing.xxl + 8)
            }
        }
        .task {
            await loadGodView()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Sections

    private var topCaption: some View {
        VStack(spacing: OstrichSpacing.xs) {
            Text("附近有 \(ostrichCount) 只鸵鸟在活动")
                .font(OstrichTypography.callout)
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
            Text("上帝视角")
                .font(OstrichTypography.caption)
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    private var recallButton: some View {
        OstrichButton("召回我的鸵鸟") {
            onRecall()
        }
    }

    // MARK: - Networking

    private func loadGodView() async {
        do {
            let response: MapGodViewResponseDTO = try await client.get(
                Endpoints.mapGod,
                query: [
                    URLQueryItem(name: "lat", value: "35.6595"),
                    URLQueryItem(name: "lng", value: "139.7005"),
                    URLQueryItem(name: "radius_m", value: "5000")
                ]
            )
            let totalCount = response.cells.reduce(0) { $0 + $1.ostrichCount }
            self.ostrichCount = max(totalCount, 1)
            self.points = GodViewPoint.fromCells(response.cells)
        } catch {
            // 失败回落到 mock（demo 阶段确保 wow，不阻塞）。
            self.ostrichCount = 24
            self.points = GodViewPoint.makeFallback(seed: 1)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                if Task.isCancelled { return }
                await loadGodView()
            }
        }
    }
}

// MARK: - Point model

struct GodViewPoint: Identifiable {
    let id = UUID()
    /// 0..1 屏幕 x
    let x: Double
    /// 0..1 屏幕 y
    let y: Double
    let isSelf: Bool
    let speed: Double   // 闪烁频率附加项 0..1
    let phase: Double   // 相位 0..2π

    static func makeFallback(seed: UInt64, count: Int = 56) -> [GodViewPoint] {
        var rng = SeededRandom(seed: seed)
        var pts: [GodViewPoint] = []
        for i in 0..<count {
            pts.append(GodViewPoint(
                x: rng.nextDouble(),
                y: rng.nextDouble(),
                isSelf: i == 0,
                speed: rng.nextDouble(),
                phase: rng.nextDouble() * .pi * 2
            ))
        }
        return pts
    }

    /// 把 cells 投影到 0..1 屏幕坐标 + 按 ostrichCount 扩出多个点。
    static func fromCells(_ cells: [MapCellSummaryDTO]) -> [GodViewPoint] {
        guard !cells.isEmpty else {
            return makeFallback(seed: 7)
        }
        let lats = cells.map(\.centerLat)
        let lngs = cells.map(\.centerLng)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 1
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 1
        let latRange = max(maxLat - minLat, 0.0001)
        let lngRange = max(maxLng - minLng, 0.0001)

        var pts: [GodViewPoint] = []
        var rng = SeededRandom(seed: 42)
        for (idx, cell) in cells.enumerated() {
            // 每个 cell 按 ostrichCount 撒点，cap 限制总数。
            let cx = (cell.centerLng - minLng) / lngRange
            let cy = 1 - (cell.centerLat - minLat) / latRange   // 北上南下
            let n = min(max(cell.ostrichCount, 1), 8)
            for j in 0..<n {
                let jitterX = (rng.nextDouble() - 0.5) * 0.08
                let jitterY = (rng.nextDouble() - 0.5) * 0.08
                pts.append(GodViewPoint(
                    x: min(max(cx + jitterX, 0.02), 0.98),
                    y: min(max(cy + jitterY, 0.08), 0.88),
                    isSelf: idx == 0 && j == 0,
                    speed: rng.nextDouble(),
                    phase: rng.nextDouble() * .pi * 2
                ))
            }
        }
        // 至少 30 个点保证视觉密度。
        while pts.count < 30 {
            pts.append(GodViewPoint(
                x: rng.nextDouble(),
                y: rng.nextDouble(),
                isSelf: false,
                speed: rng.nextDouble(),
                phase: rng.nextDouble() * .pi * 2
            ))
        }
        return pts
    }
}

/// 极简可重复随机源（xorshift64*），避免依赖 SimplexNoise 的字符串 seed。
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

#Preview {
    GodViewView(client: MockConvexClient(), onRecall: {})
}
