// OstrichMapView.swift
// MKMapView 的 UIViewRepresentable 包装。
// BLUEPRINT §10.3 LocalView：3D 卫星 + 鸵鸟图标 annotation + 路线 polyline。
//
// - mapType: .satelliteFlyover (3D 卫星 + 立体建筑)
// - camera: pitch 60°, distance 500m
// - annotation: 用 LiquidOstrichHeadView 渲染成 UIImage（rasterize 后赋给 MKAnnotationView.image）
// - polyline: 当前行走路线

import SwiftUI
import MapKit

// MARK: - Coordinate3D wrapper

/// 简单可识别的鸵鸟 annotation。MKAnnotation 必须是 class。
final class OstrichAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let isSelf: Bool
    let displayName: String

    init(coordinate: CLLocationCoordinate2D, isSelf: Bool, displayName: String) {
        self.coordinate = coordinate
        self.isSelf = isSelf
        self.displayName = displayName
        super.init()
    }
}

// MARK: - UIViewRepresentable

public struct OstrichMapView: UIViewRepresentable {

    // MARK: Inputs

    /// 自己鸵鸟当前坐标。
    public let ostrichCoord: CLLocationCoordinate2D
    /// 附近其他鸵鸟坐标（模糊小点）。
    public let nearbyCoords: [CLLocationCoordinate2D]
    /// 已走 / 即将走的 polyline。
    public let route: [CLLocationCoordinate2D]
    /// 是否让相机跟随鸵鸟。
    public let followsOstrich: Bool

    public init(
        ostrichCoord: CLLocationCoordinate2D,
        nearbyCoords: [CLLocationCoordinate2D] = [],
        route: [CLLocationCoordinate2D] = [],
        followsOstrich: Bool = true
    ) {
        self.ostrichCoord = ostrichCoord
        self.nearbyCoords = nearbyCoords
        self.route = route
        self.followsOstrich = followsOstrich
    }

    // MARK: UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .satelliteFlyover
        map.showsBuildings = true
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .includingAll
        map.isPitchEnabled = true
        map.isRotateEnabled = true

        let camera = MKMapCamera(
            lookingAtCenter: ostrichCoord,
            fromDistance: 500,
            pitch: 60,
            heading: 0
        )
        map.setCamera(camera, animated: false)
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        // 重建 annotations / overlays（数量小，直接重建简单可靠）。
        let oldAnnotations = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(oldAnnotations)
        map.removeOverlays(map.overlays)

        let selfAnnotation = OstrichAnnotation(
            coordinate: ostrichCoord,
            isSelf: true,
            displayName: "我的鸵鸟"
        )
        map.addAnnotation(selfAnnotation)
        for coord in nearbyCoords {
            map.addAnnotation(
                OstrichAnnotation(coordinate: coord, isSelf: false, displayName: "")
            )
        }

        if route.count >= 2 {
            let polyline = MKPolyline(coordinates: route, count: route.count)
            map.addOverlay(polyline)
        }

        if followsOstrich {
            zoomToShowOstrich(map: map)
        }
    }

    // MARK: - Public helpers

    /// 让相机移动到鸵鸟当前位置 (pitch 60° / distance 500m)。
    public func zoomToShowOstrich(map: MKMapView) {
        let camera = MKMapCamera(
            lookingAtCenter: ostrichCoord,
            fromDistance: 500,
            pitch: 60,
            heading: map.camera.heading
        )
        map.setCamera(camera, animated: true)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, MKMapViewDelegate {

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ostrich = annotation as? OstrichAnnotation else {
                return nil
            }
            let identifier = ostrich.isSelf ? "OstrichSelfPin" : "OstrichOtherPin"
            let view: MKAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) {
                dequeued.annotation = annotation
                view = dequeued
            } else {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            if ostrich.isSelf {
                view.image = Self.selfPinImage
                view.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
                view.canShowCallout = false
            } else {
                view.image = Self.otherPinImage
                view.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
                view.alpha = 0.6
                view.canShowCallout = false
            }
            return view
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.9)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Rasterized pin images

        private static let selfPinImage: UIImage = {
            let size = CGSize(width: 48, height: 48)
            return renderOstrichPin(size: size)
        }()

        private static let otherPinImage: UIImage = {
            let size = CGSize(width: 18, height: 18)
            return renderDotPin(size: size, color: UIColor.systemOrange)
        }()

        /// 用 SwiftUI ImageRenderer 把 LiquidOstrichHeadView 渲染成 UIImage。
        /// iOS 17+ ✓
        private static func renderOstrichPin(size: CGSize) -> UIImage {
            let renderer = ImageRenderer(content:
                ZStack {
                    Circle()
                        .fill(Color(red: 0xFC / 255.0, green: 0xFE / 255.0, blue: 0xE8 / 255.0))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    LiquidOstrichHeadView(size: size.width * 0.78)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
            )
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage ?? UIImage()
        }

        private static func renderDotPin(size: CGSize, color: UIColor) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                color.withAlphaComponent(0.85).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                UIColor.white.withAlphaComponent(0.6).setStroke()
                ctx.cgContext.setLineWidth(1.5)
                ctx.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75))
            }
        }
    }
}

// MARK: - 涩谷站默认坐标常量

public enum OstrichMapDefaults {
    /// 涩谷站 (BLUEPRINT demo 路径)。
    public static let shibuyaStation = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
}
