// WanderView.swift
// Tab 4 「遛弯」入口。共享一个 MKMapView 实例，靠相机 pitch + distance 切两级视角。
// BLUEPRINT §10.3 + §13.3 + DEMO_SCRIPT 03:00-04:00。
//
// 架构（v4 · 纯后端模式，无 mock）：
//   - 底层：单个 OstrichMapView 实例。cameraMode 跟随 viewMode 变化，
//     MKMapView.setCamera(animated:) 自带过渡 = 从天上俯冲到鸵鸟头顶的电影感。
//   - 上层：两套 overlay（GodViewView / LocalViewView），按 viewMode 切显隐。
//   - 进 tab 调 POST /api/wander/start → 后端把鸵鸟切到 wandering 并 fire-and-forget 触发 decideNextMove。
//   - 每 2s GET /api/map/localView 轮询；拿到真路线就用 WalkingSimulator 接管，
//     speech bubble + god caption 显示鸵鸟的"想去 X 因为 Y"。
//   - 在拿到第一段真路线之前 isLoadingRoute=true，鸵鸟静止站在 currentLocation，
//     LocalView speech bubble 显示 spinner + "鸵鸟正在决定去哪儿…"。
//   - 续路完全由后端 decideNextMove 末尾的 ctx.scheduler.runAfter 链式负责，
//     前端只是被动消费 mapLocal 的新 startedAt 字符串来检测新一段路线。

import SwiftUI
import Combine
import CoreLocation

public enum WanderViewMode: Equatable {
    case god
    case local

    var cameraMode: OstrichMapCameraMode {
        switch self {
        case .god: return .god
        case .local: return .local
        }
    }
}

public struct WanderView: View {

    private let client: ConvexClientProtocol

    // MARK: - 模式

    @State private var viewMode: WanderViewMode = .god

    // MARK: - 地图共享状态

    /// 自己鸵鸟的坐标。在拿到真路线之前等于 fetchInitialOstrich 拿到的 currentLocation（静止）；
    /// 真路线就绪后被 WalkingSimulator 实时插值更新。
    @State private var ostrichCoord: CLLocationCoordinate2D = OstrichMapDefaults.shibuyaStation
    /// 周围鸵鸟坐标（god 模式来自 mapGod cells；local 模式暂时空）。
    @State private var nearbyCoords: [CLLocationCoordinate2D] = []
    /// 当前 sim 的 polyline，仅 local 模式作为橙线显示。
    @State private var route: [CLLocationCoordinate2D] = []

    // MARK: - 思考状态（鸵鸟当前想做啥）

    @State private var destinationName: String? = nil
    @State private var destinationCategory: String? = nil
    @State private var reason: String? = nil
    @State private var activityLabel: String = ""
    @State private var ostrichCount: Int = 24
    /// 鸵鸟正在跟另一只鸵鸟相遇聊天时填，LocalView speech bubble 切到 dialog 态。
    @State private var currentEncounterPartner: String? = nil
    /// 后端 walkingRoute.startedAt 的 ISO 字符串。
    /// 用来检测"是不是新一段路线到了"（不同的 startedAt → 重建 simulator）。
    @State private var lastRouteStartedAt: String? = nil
    /// 在拿到第一段真路线之前为 true，LocalView speech bubble 显示 spinner。
    @State private var isLoadingRoute: Bool = true

    // MARK: - Tasks / Subscriptions

    @State private var godPollTask: Task<Void, Never>?
    @State private var localPollTask: Task<Void, Never>?
    @State private var simulator: WalkingSimulator?
    @State private var simSubscription: AnyCancellable?

    @State private var showLookAround: Bool = false
    @State private var inFlightAction: Bool = false
    /// 右上角日记按钮触发 → sheet 弹 DiaryView。
    @State private var showDiary: Bool = false

    // MARK: - 鸵鸟头顶气泡 thought（仅 local 模式）

    /// 当前显示的气泡态。nil = 没气泡（间隔期 / god 模式 / 流程异常）。
    @State private var thoughtBubbleState: ThoughtBubbleState? = nil
    /// 控制气泡 loop 的 task。进 local 启动；离开 local / WanderView 取消。
    @State private var thoughtLoopTask: Task<Void, Never>? = nil

    public init(client: ConvexClientProtocol) {
        self.client = client
    }

    public var body: some View {
        ZStack {
            // ── 底层：唯一 MKMapView 实例 ──
            OstrichMapView(
                ostrichCoord: ostrichCoord,
                nearbyCoords: nearbyCoords,
                route: viewMode == .local ? route : [],
                cameraMode: viewMode.cameraMode,
                followsOstrich: viewMode == .local
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            // ── 鸵鸟头顶 thought 气泡（local 模式独享）──
            // 位置：屏幕中心略上（≈ 鸵鸟 pin 上方 80pt）。
            // local 模式 followsOstrich=true，鸵鸟稳定在屏幕中心，气泡也跟着稳定。
            if viewMode == .local, let bubbleState = thoughtBubbleState {
                GeometryReader { geo in
                    ThoughtBubble(state: bubbleState)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height / 2 - 80
                        )
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            // ── 上层 overlay（按 viewMode 切显隐）──
            ZStack {
                if viewMode == .god {
                    GodViewView(
                        ostrichCount: ostrichCount,
                        destinationName: destinationName,
                        onRecall: enterLocal,
                        onOpenDiary: { showDiary = true }
                    )
                    .transition(.opacity)
                } else {
                    LocalViewView(
                        destinationName: destinationName,
                        destinationCategory: destinationCategory,
                        reason: reason,
                        activityLabel: activityLabel,
                        isLoadingRoute: isLoadingRoute,
                        inFlightAction: inFlightAction,
                        encounterPartner: currentEncounterPartner,
                        onBackToGod: enterGod,
                        onCallHome: { Task { await sendCallHome() } },
                        onAllowToStay: { Task { await sendAllowToStay() } },
                        onLookAround: { showLookAround = true }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewMode)
        }
        .animation(.easeInOut(duration: 0.28), value: thoughtBubbleState)
        .task {
            // 进入 tab 的启动序列：
            // 1. 通知后端"我要遛弯了"——切 state + fire-and-forget decideNextMove
            // 2. 拿一次 mapLocal 当 ostrichCoord 锚点（鸵鸟先静止显示）
            // 3. 开启 god 模式 cells 轮询 + local 模式真数据轮询
            await callWanderStart()
            await fetchInitialOstrich()
            startGodPolling()
            startLocalPolling()
        }
        .onDisappear {
            stopGodPolling()
            stopLocalPolling()
            stopSimulator()
            stopThoughtLoop()
        }
        .onChange(of: viewMode) { _, newMode in
            // 进 local → 启动头顶气泡 loop（立刻第一条 + 1-3min 随机间隔）
            // 离开 local → 停掉 loop 并立刻清气泡
            if newMode == .local {
                startThoughtLoop()
            } else {
                stopThoughtLoop()
            }
        }
        .sheet(isPresented: $showLookAround) {
            LookAroundBridge(coordinate: ostrichCoord) {
                showLookAround = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showDiary) {
            // DiaryView 用 timeline endpoint 拉聚合数据。WanderView 把 client 传下去。
            NavigationStack {
                DiaryView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showDiary = false }
                        }
                    }
            }
        }
    }

    // MARK: - 模式切换（不影响 simulator，只切镜头 + overlay）

    private func enterLocal() {
        withAnimation(.easeInOut(duration: 0.6)) {
            viewMode = .local
        }
    }

    private func enterGod() {
        withAnimation(.easeInOut(duration: 0.6)) {
            viewMode = .god
        }
    }

    // MARK: - 启动通知（鸵鸟开始遛弯）

    private func callWanderStart() async {
        print("[WanderView] callWanderStart: entering, token=\(client.sessionToken?.prefix(10) ?? "<nil>")")
        do {
            let _: OkResponseDTO = try await client.call(
                Endpoints.wanderStart,
                body: WanderEmptyBody()
            )
            print("[WanderView] callWanderStart: succeeded")
        } catch {
            print("[WanderView] callWanderStart: FAILED with \(error)")
        }
    }

    // MARK: - god 模式数据

    private func startGodPolling() {
        godPollTask?.cancel()
        godPollTask = Task { @MainActor in
            await loadGodView()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                if Task.isCancelled { return }
                await loadGodView()
            }
        }
    }

    private func stopGodPolling() {
        godPollTask?.cancel()
        godPollTask = nil
    }

    private func loadGodView() async {
        do {
            let response: MapGodViewResponseDTO = try await client.get(
                Endpoints.mapGod,
                query: [
                    URLQueryItem(name: "lat", value: "\(ostrichCoord.latitude)"),
                    URLQueryItem(name: "lng", value: "\(ostrichCoord.longitude)"),
                    URLQueryItem(name: "radius_m", value: "5000")
                ]
            )
            let totalCount = response.cells.reduce(0) { $0 + $1.ostrichCount }
            let coords = WanderMapHelpers.coordsFromCells(
                response.cells,
                fallbackCenter: ostrichCoord
            )
            await MainActor.run {
                self.nearbyCoords = coords
                self.ostrichCount = max(totalCount, coords.count, 1)
            }
        } catch {
            let mock = WanderMapHelpers.makeMockCoords(around: ostrichCoord, count: 24)
            await MainActor.run {
                self.nearbyCoords = mock
                self.ostrichCount = 24
            }
        }
    }

    // MARK: - local 模式数据（真路线 + 鸵鸟思考）

    /// 进 tab 时拉一次：拿 ostrich.lat/lng 当静止锚点 + activity 标签。
    private func fetchInitialOstrich() async {
        do {
            let response: MapLocalViewResponseDTO = try await client.get(Endpoints.mapLocal)
            let coord = CLLocationCoordinate2D(
                latitude: response.ostrich.lat,
                longitude: response.ostrich.lng
            )
            await MainActor.run {
                self.ostrichCoord = coord
                self.activityLabel = response.ostrich.activity
                // 若刚 fetch 就已经有 intention（可能上次 tab 没退出干净），先填上
                if let name = response.destinationName {
                    self.destinationName = name
                }
                if let cat = response.destinationCategory {
                    self.destinationCategory = cat
                }
                if let r = response.reason {
                    self.reason = r
                }
            }
        } catch {
            // 保留涩谷站默认。后续 polling 会重试感知。
        }
    }

    /// 每 2s 轮询 mapLocal：
    /// - 总是同步最新 destinationName / reason / activity
    /// - 拿到 route 且 startedAt 比 lastRouteStartedAt 新 → 重建 simulator
    /// - route 仍为 nil → 维持 isLoadingRoute=true，鸵鸟静止
    private func startLocalPolling() {
        localPollTask?.cancel()
        localPollTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshLocalView()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            }
        }
    }

    private func stopLocalPolling() {
        localPollTask?.cancel()
        localPollTask = nil
    }

    private func refreshLocalView() async {
        do {
            let response: MapLocalViewResponseDTO = try await client.get(Endpoints.mapLocal)
            await MainActor.run {
                self.destinationName = response.destinationName
                self.destinationCategory = response.destinationCategory
                self.reason = response.reason
                self.activityLabel = response.ostrich.activity
                // 相遇期间填 partnerName → LocalView speech bubble 切到 dialog 态
                self.currentEncounterPartner = response.currentEncounter?.partnerName
            }
            if let polyline = response.route {
                // 检测新一段路线：startedAt 变化 = 后端写了新的 walkingRoute
                if polyline.startedAt != lastRouteStartedAt {
                    if let sim = WalkingSimulator.fromPolyline(polyline) {
                        await MainActor.run {
                            self.lastRouteStartedAt = polyline.startedAt
                            self.route = sim.route
                            self.isLoadingRoute = false
                            bindSimulator(sim)
                        }
                        sim.start()
                    }
                }
            } else {
                // route 为 nil（鸵鸟到达后等下一次 decideNextMove，5-15 分钟空窗）
                await MainActor.run {
                    if self.simulator == nil {
                        self.isLoadingRoute = true
                    }
                }
            }
        } catch {
            // 静默继续。
        }
    }

    private func bindSimulator(_ sim: WalkingSimulator) {
        simSubscription?.cancel()
        simulator?.stop()
        simulator = sim
        simSubscription = sim.$currentCoord
            .receive(on: DispatchQueue.main)
            .sink { coord in
                self.ostrichCoord = coord
            }
        // 不再监听 progress >= 1 续路 —— 后端 scheduler 负责。
        // 走完后 mapLocal 会返回 route=nil，前端切回 loading 等下一段。
    }

    private func stopSimulator() {
        simulator?.stop()
        simulator = nil
        simSubscription?.cancel()
        simSubscription = nil
        route = []
    }

    // MARK: - 鸵鸟头顶 thought 气泡 loop
    //
    // 调度：进 local 立刻 fire 第 1 条；之后 1-3 min 随机间隔 fire 下一条。
    // 每条流程：
    //   1. 立刻 set 气泡为 .thinking（3 点跳）
    //   2. POST /api/ostrich/think → 拿 thoughtId
    //   3. 每 300ms GET /api/ostrich/thought/:id → 看 content 增长
    //      - status="streaming" → 更新到 .streaming(content)
    //      - status="done"      → .done(content)，跳出轮询
    //      - status="error"     → 清气泡
    //   4. done 后等 10s → 清气泡
    //   5. 等下一次间隔
    //
    // 切回 god / 离开 WanderView → 取消 task + 清气泡（thoughtId 不再轮询）。

    private static let thoughtMinIntervalMs: UInt64 = 30_000
    private static let thoughtMaxIntervalMs: UInt64 = 120_000
    private static let thoughtPollIntervalMs: UInt64 = 300
    private static let thoughtPollMaxAttempts: Int = 60        // 60 × 300ms = 18s 安全上限
    private static let thoughtDoneFadeDelayMs: UInt64 = 10_000

    private func startThoughtLoop() {
        thoughtLoopTask?.cancel()
        thoughtLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                await fireOneThought()
                if Task.isCancelled { return }
                let intervalMs = UInt64.random(
                    in: Self.thoughtMinIntervalMs...Self.thoughtMaxIntervalMs
                )
                try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
            }
        }
    }

    private func stopThoughtLoop() {
        thoughtLoopTask?.cancel()
        thoughtLoopTask = nil
        thoughtBubbleState = nil
    }

    private func fireOneThought() async {
        // 1. 立刻显示 thinking（点点点）
        await MainActor.run { self.thoughtBubbleState = .thinking }

        // 2. POST /api/ostrich/think → 拿 thoughtId
        let createResp: ThoughtCreateResponseDTO
        do {
            createResp = try await client.call(
                Endpoints.think,
                body: WanderEmptyBody()
            )
        } catch {
            print("[WanderView] /think failed: \(error)")
            await MainActor.run { self.thoughtBubbleState = nil }
            return
        }
        let thoughtId = createResp.thoughtId

        // 3. 300ms 轮询直到 status="done" / "error" 或超时
        var sawDone = false
        for _ in 0..<Self.thoughtPollMaxAttempts {
            try? await Task.sleep(nanoseconds: Self.thoughtPollIntervalMs * 1_000_000)
            if Task.isCancelled { return }
            do {
                let thought: ThoughtDTO = try await client.get(
                    Endpoints.thought + thoughtId
                )
                if thought.status == "error" {
                    await MainActor.run { self.thoughtBubbleState = nil }
                    return
                }
                let newState: ThoughtBubbleState = thought.status == "done"
                    ? .done(thought.content)
                    : .streaming(thought.content)
                await MainActor.run { self.thoughtBubbleState = newState }
                if thought.status == "done" {
                    sawDone = true
                    break
                }
            } catch {
                // 单次轮询失败静默重试；网络抖动期间继续等
            }
        }

        // 4. done 后等 10s 淡出；超时（没等到 done）也按相同节奏清掉
        if sawDone {
            try? await Task.sleep(
                nanoseconds: Self.thoughtDoneFadeDelayMs * 1_000_000
            )
        }
        if Task.isCancelled { return }
        await MainActor.run { self.thoughtBubbleState = nil }
    }

    // MARK: - local 按钮 action

    private func sendCallHome() async {
        guard !inFlightAction else { return }
        await MainActor.run { inFlightAction = true }
        defer { Task { @MainActor in inFlightAction = false } }
        do {
            let _: CallHomeResponseDTO = try await client.call(
                Endpoints.callHome,
                body: WanderEmptyBody()
            )
        } catch {
            // demo 阶段失败不阻塞
        }
        enterGod()
    }

    private func sendAllowToStay() async {
        guard !inFlightAction else { return }
        await MainActor.run { inFlightAction = true }
        defer { Task { @MainActor in inFlightAction = false } }
        do {
            let _: OkResponseDTO = try await client.call(
                Endpoints.allowToStay,
                body: WanderEmptyBody()
            )
        } catch {
            // 同上
        }
        enterGod()
    }
}

// MARK: - 共享辅助

/// god 模式 cell 解析 + mock 点撒布。提取到自由函数，方便测试。
enum WanderMapHelpers {

    /// 从 cells 解析出每只鸵鸟的真实坐标。
    /// cellId 形如 "35.658:139.700"（lat:lng 各 3 位小数）。
    static func coordsFromCells(
        _ cells: [MapCellSummaryDTO],
        fallbackCenter: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        guard !cells.isEmpty else {
            return makeMockCoords(around: fallbackCenter, count: 24)
        }
        var rng = WanderSeededRNG(seed: 42)
        var out: [CLLocationCoordinate2D] = []
        for cell in cells {
            let center = cellCenter(cell: cell, fallback: fallbackCenter)
            let n = min(max(cell.ostrichCount, 1), 8)
            for _ in 0..<n {
                let jitterLat = (rng.nextDouble() - 0.5) * 0.0009   // ~100m
                let jitterLng = (rng.nextDouble() - 0.5) * 0.0009
                out.append(CLLocationCoordinate2D(
                    latitude: center.latitude + jitterLat,
                    longitude: center.longitude + jitterLng
                ))
            }
        }
        while out.count < 20 {
            let dLat = (rng.nextDouble() - 0.5) * 0.04
            let dLng = (rng.nextDouble() - 0.5) * 0.04
            out.append(CLLocationCoordinate2D(
                latitude: fallbackCenter.latitude + dLat,
                longitude: fallbackCenter.longitude + dLng
            ))
        }
        return out
    }

    private static func cellCenter(
        cell: MapCellSummaryDTO,
        fallback: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        if cell.centerLat != 0 || cell.centerLng != 0 {
            return CLLocationCoordinate2D(latitude: cell.centerLat, longitude: cell.centerLng)
        }
        let parts = cell.cellId.split(separator: ":")
        if parts.count == 2,
           let lat = Double(parts[0]),
           let lng = Double(parts[1]) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return fallback
    }

    static func makeMockCoords(
        around center: CLLocationCoordinate2D,
        count: Int
    ) -> [CLLocationCoordinate2D] {
        var rng = WanderSeededRNG(seed: 7)
        var out: [CLLocationCoordinate2D] = []
        for _ in 0..<count {
            let dLat = (rng.nextDouble() - 0.5) * 0.04
            let dLng = (rng.nextDouble() - 0.5) * 0.04
            out.append(CLLocationCoordinate2D(
                latitude: center.latitude + dLat,
                longitude: center.longitude + dLng
            ))
        }
        return out
    }
}

/// xorshift64* 可重复随机。
struct WanderSeededRNG {
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

/// 空 POST body 占位。
struct WanderEmptyBody: Encodable {}

#Preview {
    WanderView(client: MockConvexClient())
}
