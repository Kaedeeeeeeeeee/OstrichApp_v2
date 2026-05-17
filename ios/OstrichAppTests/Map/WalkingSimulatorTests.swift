// WalkingSimulatorTests.swift
// 验证 polyline 插值正确：端点 + 中点 + 到达后停在终点。

import Testing
import Foundation
import CoreLocation
@testable import OstrichApp

@MainActor
struct WalkingSimulatorTests {

    private func makeRoute() -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005),
            CLLocationCoordinate2D(latitude: 35.6610, longitude: 139.7025),
            CLLocationCoordinate2D(latitude: 35.6628, longitude: 139.7044),
            CLLocationCoordinate2D(latitude: 35.6648, longitude: 139.7062),
            CLLocationCoordinate2D(latitude: 35.6665, longitude: 139.7085)
        ]
    }

    @Test func startEndpointReturnsFirstCoord() {
        let route = makeRoute()
        let now = Date(timeIntervalSince1970: 1000)
        let sim = WalkingSimulator(
            route: route,
            startedAt: now,
            expectedDuration: 60,
            clock: { now } // elapsed == 0
        )
        let coord = sim.recompute()
        #expect(abs(coord.latitude - route[0].latitude) < 1e-9)
        #expect(abs(coord.longitude - route[0].longitude) < 1e-9)
    }

    @Test func endpointAfterExpectedDuration() {
        let route = makeRoute()
        let start = Date(timeIntervalSince1970: 1000)
        let after = start.addingTimeInterval(120) // > expectedDuration
        let sim = WalkingSimulator(
            route: route,
            startedAt: start,
            expectedDuration: 60,
            clock: { after }
        )
        let coord = sim.recompute()
        let end = route[route.count - 1]
        #expect(abs(coord.latitude - end.latitude) < 1e-9)
        #expect(abs(coord.longitude - end.longitude) < 1e-9)
        #expect(sim.progress >= 0.999)
    }

    @Test func midpointInterpolation() {
        // 等距两点：progress 0.5 应落在精确中点。
        let route: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ]
        let start = Date(timeIntervalSince1970: 0)
        let mid = Date(timeIntervalSince1970: 30)
        let sim = WalkingSimulator(
            route: route,
            startedAt: start,
            expectedDuration: 60,
            clock: { mid }
        )
        let coord = sim.recompute()
        #expect(abs(coord.latitude - 0) < 1e-9)
        #expect(abs(coord.longitude - 0.005) < 1e-9)
        #expect(abs(sim.progress - 0.5) < 1e-9)
    }

    @Test func multiSegmentMidpointTracksArcLength() {
        // 多段不等长：用解析方法验证插值按弧长比例。
        let route: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ]
        // 总长 ≈ |0.001| + |0.009| 的 lng 距离 = 0.01。
        // progress 0.5 落在 0.005 lng 处，仍在第二段（起点 0.001，长 0.009），
        // local = (0.005 - 0.001) / 0.009 ≈ 0.4444
        // 期望 coord.longitude = 0.001 + 0.009 * 0.4444 = 0.005
        let start = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 30)
        let sim = WalkingSimulator(
            route: route,
            startedAt: start,
            expectedDuration: 60,
            clock: { now }
        )
        let coord = sim.recompute()
        #expect(abs(coord.longitude - 0.005) < 1e-6)
    }

    @Test func clampsProgressBeforeStart() {
        let route = makeRoute()
        let start = Date(timeIntervalSince1970: 1000)
        let before = Date(timeIntervalSince1970: 500)
        let sim = WalkingSimulator(
            route: route,
            startedAt: start,
            expectedDuration: 60,
            clock: { before }
        )
        let coord = sim.recompute()
        #expect(abs(coord.latitude - route[0].latitude) < 1e-9)
        #expect(sim.progress == 0)
    }

    @Test func fromPolylineParsesISO8601() {
        let dto = PolylineDTO(
            coords: [[35.6595, 139.7005], [35.6628, 139.7044]],
            expectedDurationSec: 60,
            startedAt: "2026-05-16T12:00:00Z"
        )
        let sim = WalkingSimulator.fromPolyline(dto)
        #expect(sim != nil)
        #expect(sim?.route.count == 2)
        #expect(sim?.expectedDuration == 60)
    }

    @Test func staticCoordinateAtBoundaries() {
        let route: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1)
        ]
        let lengths = [WalkingSimulator.distance(route[0], route[1])]
        let total = lengths.reduce(0, +)
        let zero = WalkingSimulator.coordinate(at: 0, route: route, segmentLengths: lengths, total: total)
        let one = WalkingSimulator.coordinate(at: 1, route: route, segmentLengths: lengths, total: total)
        #expect(zero.longitude == 0)
        #expect(one.longitude == 1)
    }
}
