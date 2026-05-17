// WalkingSimulator.swift
// 鸵鸟沿 polyline + 真实步行时间的线性插值。
// BLUEPRINT §10.1 「不是真物理引擎，是 '每分钟插值移动一格'」。
//
// 设计：
// - route: [(lat, lng)] 步行路线（来自后端 MKDirections）
// - startedAt + expectedDuration: 决定当前进度 progress ∈ [0,1]
// - 每 tickInterval (默认 2s) 重新插值 currentCoord
// - progress 用累积弧长（haversine 近似平面欧氏）确保速度恒定，
//   而不是按 route 段数均分（拐点处会瞬移）。

import Foundation
import CoreLocation

@MainActor
public final class WalkingSimulator: ObservableObject {

    // MARK: - Output

    @Published public private(set) var currentCoord: CLLocationCoordinate2D
    @Published public private(set) var progress: Double = 0

    // MARK: - Inputs

    public let route: [CLLocationCoordinate2D]
    public let startedAt: Date
    public let expectedDuration: TimeInterval
    public let tickInterval: TimeInterval

    // MARK: - State

    private var timer: Timer?
    private let segmentLengths: [Double]
    private let totalLength: Double

    /// 当前用于测算 now 的时钟（便于测试注入）。
    private let clock: () -> Date

    // MARK: - Init

    public init(
        route: [CLLocationCoordinate2D],
        startedAt: Date,
        expectedDuration: TimeInterval,
        tickInterval: TimeInterval = 0.1,
        clock: @escaping () -> Date = { Date() }
    ) {
        precondition(!route.isEmpty, "route 不能为空")
        precondition(expectedDuration > 0, "expectedDuration 必须为正")

        self.route = route
        self.startedAt = startedAt
        self.expectedDuration = expectedDuration
        self.tickInterval = tickInterval
        self.clock = clock

        // 预计算每段弧长 + 总长。
        var lengths: [Double] = []
        if route.count >= 2 {
            for i in 0..<(route.count - 1) {
                lengths.append(Self.distance(route[i], route[i + 1]))
            }
        }
        self.segmentLengths = lengths
        self.totalLength = lengths.reduce(0, +)

        // 初始位置 = route 起点（即便 startedAt 已过去也先放起点，等 start() 调用后插值）。
        self.currentCoord = route[0]

        // 立刻把 currentCoord 修到 now 对应的位置（无需先 start）。
        recompute()
    }

    // MARK: - Public API

    /// 启动周期插值；幂等。
    public func start() {
        stop()
        // 立刻同步一次。
        recompute()
        let interval = tickInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recompute()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 当前应处于路线上的位置（不依赖 timer 触发）。
    @discardableResult
    public func recompute() -> CLLocationCoordinate2D {
        let now = clock()
        let elapsed = now.timeIntervalSince(startedAt)
        let p = max(0, min(1, elapsed / expectedDuration))
        self.progress = p
        self.currentCoord = Self.coordinate(at: p, route: route, segmentLengths: segmentLengths, total: totalLength)
        return currentCoord
    }

    // MARK: - Static helpers (pure)

    /// 沿 route 在给定 progress (0..1) 时返回坐标。按弧长比例线性插值。
    public static func coordinate(
        at progress: Double,
        route: [CLLocationCoordinate2D],
        segmentLengths: [Double],
        total: Double
    ) -> CLLocationCoordinate2D {
        guard let first = route.first else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        if route.count == 1 || total <= 0 {
            return first
        }
        let clamped = max(0, min(1, progress))
        if clamped >= 1 {
            return route[route.count - 1]
        }
        let target = clamped * total
        var acc: Double = 0
        for i in 0..<segmentLengths.count {
            let segLen = segmentLengths[i]
            if acc + segLen >= target {
                let local = segLen > 0 ? (target - acc) / segLen : 0
                let a = route[i]
                let b = route[i + 1]
                return CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * local,
                    longitude: a.longitude + (b.longitude - a.longitude) * local
                )
            }
            acc += segLen
        }
        return route[route.count - 1]
    }

    /// 平面欧氏距离，按本地米近似（lat 1° ≈ 111_000 m，lng 按 cos(lat) 缩）。
    /// 涩谷量级 (~500m) 内偏差 <1%，对插值无影响。
    public static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let meanLat = (a.latitude + b.latitude) * 0.5 * .pi / 180
        let dLat = (b.latitude - a.latitude) * 111_000
        let dLng = (b.longitude - a.longitude) * 111_000 * cos(meanLat)
        return (dLat * dLat + dLng * dLng).squareRoot()
    }
}

// MARK: - DTO bridge

public extension WalkingSimulator {

    /// 从 PolylineDTO 构造，使用 ISO-8601 时间字符串解析 startedAt。
    /// 解析失败时回落到 now。
    static func fromPolyline(_ dto: PolylineDTO, now: Date = Date()) -> WalkingSimulator? {
        let coords: [CLLocationCoordinate2D] = dto.coords.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        guard !coords.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let started = formatter.date(from: dto.startedAt)
            ?? ISO8601DateFormatter().date(from: dto.startedAt)
            ?? now
        return WalkingSimulator(
            route: coords,
            startedAt: started,
            expectedDuration: TimeInterval(max(dto.expectedDurationSec, 1))
        )
    }
}
