// LocalViewView.swift
// 局域视角：3D 卫星地图 + 鸵鸟图标 annotation + 顶部对话气泡 + 底部两个按钮。
// BLUEPRINT §10.3 LocalView + DEMO_SCRIPT 03:00-04:00。
//
// - 进入时拉 .mapLocal 拿当前位置 + route + activity
// - 用 WalkingSimulator 沿 polyline 真实步行时间插值 currentCoord
// - 顶部鸵鸟对话气泡（OstrichCard 风格），demo mock 文案
// - 底部「让 ta 继续玩」(allowToStay) / 「已回家」(切回 god view)
// - 左上角「返回上帝视角」小按钮
// - 中下「想看看这里长什么样吗？」按钮 → Look Around sheet

import SwiftUI
import Combine
import CoreLocation
import MapKit

struct LocalViewView: View {

    let client: ConvexClientProtocol
    let onBackToGod: () -> Void

    @State private var localData: MapLocalViewResponseDTO?
    @State private var simulator: WalkingSimulator?
    @State private var ostrichCoord: CLLocationCoordinate2D = OstrichMapDefaults.shibuyaStation
    @State private var ostrichSpeechText: String = "我在表参道附近转转，碰到一只叫飒飒的鸵鸟，它主人是个音乐人……"
    @State private var showLookAround: Bool = false
    @State private var loadFailed: Bool = false
    @State private var inFlightAction: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, OstrichSpacing.l)
                    .padding(.top, OstrichSpacing.s)
                speechBubble
                    .padding(.horizontal, OstrichSpacing.l)
                    .padding(.top, OstrichSpacing.s)
                Spacer()
                lookAroundCallout
                    .padding(.bottom, OstrichSpacing.s)
                bottomBar
                    .padding(.horizontal, OstrichSpacing.l)
                    .padding(.bottom, OstrichSpacing.xl)
            }
        }
        .task {
            await loadLocalView()
        }
        .onDisappear {
            simulator?.stop()
        }
        .sheet(isPresented: $showLookAround) {
            LookAroundBridge(coordinate: ostrichCoord) {
                showLookAround = false
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Sections

    private var mapLayer: some View {
        let route = simulator?.route ?? []
        return OstrichMapView(
            ostrichCoord: ostrichCoord,
            nearbyCoords: (localData?.nearby ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
            route: route,
            followsOstrich: true
        )
        .ignoresSafeArea()
        .onReceive(simulatorPublisher) { coord in
            self.ostrichCoord = coord
        }
    }

    /// 兼容 nil simulator 的合并 publisher。
    private var simulatorPublisher: AnyPublisherWrapper<CLLocationCoordinate2D> {
        if let sim = simulator {
            return AnyPublisherWrapper(sim.$currentCoord.eraseToAnyPublisher())
        } else {
            // 永不发射，占位。
            return AnyPublisherWrapper(Empty<CLLocationCoordinate2D, Never>().eraseToAnyPublisher())
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBackToGod) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上帝视角")
                }
                .font(OstrichTypography.callout)
                .foregroundStyle(OstrichColors.ink)
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.xs)
                .background(
                    Capsule().fill(OstrichColors.cream.opacity(0.95))
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            Spacer()
            if let friendly = localData?.ostrich.activity, !friendly.isEmpty {
                Text(friendly)
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink)
                    .padding(.horizontal, OstrichSpacing.m)
                    .padding(.vertical, OstrichSpacing.xs)
                    .background(
                        Capsule().fill(OstrichColors.cream.opacity(0.95))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }

    private var speechBubble: some View {
        OstrichCard {
            VStack(alignment: .leading, spacing: OstrichSpacing.xs) {
                Text("鸵鸟在说")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
                Text(ostrichSpeechText)
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var lookAroundCallout: some View {
        Button {
            showLookAround = true
        } label: {
            HStack(spacing: OstrichSpacing.s) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("想看看这里长什么样吗？")
                    .font(OstrichTypography.callout)
            }
            .foregroundStyle(OstrichColors.ink)
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.vertical, OstrichSpacing.s)
            .background(
                Capsule().fill(OstrichColors.cream.opacity(0.95))
            )
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: OstrichSpacing.m) {
            Button {
                Task { await sendAllowToStay() }
            } label: {
                Text("让 ta 继续玩")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OstrichColors.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule().fill(OstrichColors.cream)
                    )
            }
            .disabled(inFlightAction)

            Button {
                Task { await sendCallHome() }
            } label: {
                Text("已回家")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OstrichColors.cream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule().fill(OstrichColors.ink)
                    )
            }
            .disabled(inFlightAction)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    // MARK: - Networking

    private func loadLocalView() async {
        do {
            let response: MapLocalViewResponseDTO = try await client.get(Endpoints.mapLocal)
            self.localData = response
            let coord = CLLocationCoordinate2D(
                latitude: response.ostrich.lat,
                longitude: response.ostrich.lng
            )
            self.ostrichCoord = coord
            if let route = response.route,
               let sim = WalkingSimulator.fromPolyline(route) {
                self.simulator = sim
                sim.start()
            } else {
                self.simulator = nil
            }
        } catch {
            // 后端没起也要 demo 可走 —— 给一段涩谷站短路线作为 fallback。
            self.loadFailed = true
            let fallback = WalkingSimulator(
                route: Self.fallbackRoute,
                startedAt: Date().addingTimeInterval(-30),
                expectedDuration: 300
            )
            self.simulator = fallback
            fallback.start()
            self.ostrichCoord = Self.fallbackRoute[0]
        }
    }

    private func sendCallHome() async {
        guard !inFlightAction else { return }
        inFlightAction = true
        defer { inFlightAction = false }
        do {
            let _: CallHomeResponseDTO = try await client.call(Endpoints.callHome, body: EmptyBody())
        } catch {
            // demo 阶段失败不阻塞，仍切回 god view。
        }
        onBackToGod()
    }

    private func sendAllowToStay() async {
        guard !inFlightAction else { return }
        inFlightAction = true
        defer { inFlightAction = false }
        do {
            let _: OkResponseDTO = try await client.call(Endpoints.allowToStay, body: EmptyBody())
        } catch {
            // 同上
        }
        onBackToGod()
    }

    // MARK: - Fallback

    /// 涩谷站 → 表参道方向的一段 mock 步行路线，确保后端不可用时仍有动效。
    static let fallbackRoute: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005),
        CLLocationCoordinate2D(latitude: 35.6610, longitude: 139.7025),
        CLLocationCoordinate2D(latitude: 35.6628, longitude: 139.7044),
        CLLocationCoordinate2D(latitude: 35.6648, longitude: 139.7062),
        CLLocationCoordinate2D(latitude: 35.6665, longitude: 139.7085)
    ]
}

// MARK: - Combine 兼容（避免在 View body 里直接 onReceive 一个可空 publisher）

struct AnyPublisherWrapper<Output>: Publisher {
    typealias Failure = Never

    private let upstream: AnyPublisher<Output, Never>

    init(_ upstream: AnyPublisher<Output, Never>) {
        self.upstream = upstream
    }

    func receive<S>(subscriber: S) where S: Subscriber, Never == S.Failure, Output == S.Input {
        upstream.receive(subscriber: subscriber)
    }
}

/// 空 body 占位（POST body 字段为 `{}`）。
private struct EmptyBody: Encodable {}

#Preview {
    LocalViewView(client: MockConvexClient(), onBackToGod: {})
}
