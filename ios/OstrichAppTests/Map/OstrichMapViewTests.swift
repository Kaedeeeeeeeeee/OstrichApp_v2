// OstrichMapViewTests.swift
// Smoke：OstrichMapView / OstrichAnnotation / LookAroundBridge 实例化不崩。

import Testing
import SwiftUI
import CoreLocation
import MapKit
@testable import OstrichApp

@MainActor
struct OstrichMapViewTests {

    @Test func ostrichMapViewInstantiates() {
        let view = OstrichMapView(
            ostrichCoord: OstrichMapDefaults.shibuyaStation,
            nearbyCoords: [],
            route: [],
            followsOstrich: true
        )
        // body 是 UIViewRepresentable 自动合成；至少调用 makeCoordinator 不崩。
        _ = view.makeCoordinator()
    }

    @Test func ostrichAnnotationIsSelfFlag() {
        let ann = OstrichAnnotation(
            coordinate: CLLocationCoordinate2D(latitude: 35.66, longitude: 139.70),
            isSelf: true,
            displayName: "Test"
        )
        #expect(ann.isSelf == true)
        #expect(ann.displayName == "Test")
        #expect(ann.coordinate.latitude == 35.66)
    }

    @Test func lookAroundBridgeInstantiates() {
        let view = LookAroundBridge(
            coordinate: OstrichMapDefaults.shibuyaStation,
            onDismiss: {}
        )
        _ = view.body
    }

    @Test func lookAroundLoaderStartsIdle() async {
        let loader = LookAroundLoader()
        #expect(loader.state == .idle)
    }

    @Test func shibuyaStationDefault() {
        let coord = OstrichMapDefaults.shibuyaStation
        #expect(abs(coord.latitude - 35.6595) < 1e-6)
        #expect(abs(coord.longitude - 139.7005) < 1e-6)
    }
}
