// OstrichMapView.swift
// MKMapView 的 UIViewRepresentable 包装。
// BLUEPRINT §10.3 改版：上帝视角 / 局域视角共用同一个 MKMapView，仅相机角度不同。
//
// - 统一 mapType: .standard + showsBuildings (图2 那种灰白 3D 建筑风格)
// - cameraMode = .god  → pitch 0°, distance ~3000m（俯视看大范围 + 街道 + POI 标签）
// - cameraMode = .local → pitch 60°, distance ~500m（贴近看 3D 立体建筑）
// - god 模式所有鸵鸟（含自己）统一渲染成小橙点，仅密度暗示活跃区域，不暴露身份
// - local 模式自己鸵鸟用 LiquidOstrichHeadView pin 突出，其他鸵鸟模糊小点
// - polyline 只在 local 模式有意义（god 模式 route 留空即可）

import SwiftUI
import MapKit

// MARK: - CameraMode

/// 地图相机预设。
/// 与 `WanderViewMode` 一一对应，但放在 Map 层让 OstrichMapView 不依赖 Features 层。
public enum OstrichMapCameraMode: Equatable {
    case god
    case local

    var pitch: CGFloat {
        switch self {
        case .god: return 0
        case .local: return 65
        }
    }

    /// 相机距地面距离（米）。
    /// - god 1500m：俯视看到周围十几个街区 + 主要街道名（不至于 zoom 太远丢失上下文）
    /// - local 250m：贴近建筑，能感受到 3D 立体感和街景细节
    var distance: CLLocationDistance {
        switch self {
        case .god: return 1500
        case .local: return 250
        }
    }
}

// MARK: - Annotation

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

    /// 自己鸵鸟当前坐标（god 模式下也突出显示）。
    public let ostrichCoord: CLLocationCoordinate2D
    /// 附近其他鸵鸟坐标。
    public let nearbyCoords: [CLLocationCoordinate2D]
    /// 已走 / 即将走的 polyline（仅 local 模式渲染）。
    public let route: [CLLocationCoordinate2D]
    /// 相机模式。
    public let cameraMode: OstrichMapCameraMode
    /// 是否让相机跟随鸵鸟（god 模式下建议关掉，避免相机被鸵鸟坐标拉走）。
    public let followsOstrich: Bool

    public init(
        ostrichCoord: CLLocationCoordinate2D,
        nearbyCoords: [CLLocationCoordinate2D] = [],
        route: [CLLocationCoordinate2D] = [],
        cameraMode: OstrichMapCameraMode = .local,
        followsOstrich: Bool = true
    ) {
        self.ostrichCoord = ostrichCoord
        self.nearbyCoords = nearbyCoords
        self.route = route
        self.cameraMode = cameraMode
        self.followsOstrich = followsOstrich
    }

    // MARK: UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsBuildings = true
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .includingAll
        map.isPitchEnabled = true
        map.isRotateEnabled = true

        // 加 3 个"探测"型手势识别器，仅用来检测"用户主动在操作地图"。
        // 它们和 MKMapView 内部的手势并行识别（不抢手势、不打断地图自身的 pan/pinch/rotate），
        // 只在 .began/.changed 时把 followSuppressedUntil 推后 30s，
        // 让用户能自由浏览，期间 simulator 位置更新不再 setCenter 把镜头拉回鸵鸟。
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleUserGesture(_:))
        )
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleUserGesture(_:))
        )
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)

        let rotation = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleUserGesture(_:))
        )
        rotation.delegate = context.coordinator
        map.addGestureRecognizer(rotation)

        let camera = MKMapCamera(
            lookingAtCenter: ostrichCoord,
            fromDistance: cameraMode.distance,
            pitch: cameraMode.pitch,
            heading: 0
        )
        map.setCamera(camera, animated: false)
        context.coordinator.lastCameraMode = cameraMode
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        // ── self annotation 复用（关键：让 KVO 触发 MKMapView 的内置平滑过渡）──
        // 不再每帧 remove + add（之前那样 MKMapView 看到的是"老 annotation 消失 + 新出现"，
        // 没有过渡，所以每次 sim 更新视觉上是瞬移）。
        // 改成：第一次创建 + addAnnotation，后续只改 .coordinate（dynamic 属性）触发 KVO，
        // MKMapView 自动以 ~0.25s 动画把 pin 滑到新位置。配合 sim 100ms 一次 tick → 鸵鸟持续平滑漂。
        if let existing = context.coordinator.selfAnnotation {
            if existing.coordinate.latitude != ostrichCoord.latitude
                || existing.coordinate.longitude != ostrichCoord.longitude
            {
                existing.coordinate = ostrichCoord
            }
        } else {
            let selfAnnotation = OstrichAnnotation(
                coordinate: ostrichCoord,
                isSelf: true,
                displayName: "我的鸵鸟"
            )
            context.coordinator.selfAnnotation = selfAnnotation
            map.addAnnotation(selfAnnotation)
        }

        // ── nearby annotations 整体替换（god 模式 10s 一次刷新，频率低，重建可接受）──
        let oldNearby = map.annotations.filter { ann in
            ann !== context.coordinator.selfAnnotation && !(ann is MKUserLocation)
        }
        map.removeAnnotations(oldNearby)
        for coord in nearbyCoords {
            map.addAnnotation(
                OstrichAnnotation(coordinate: coord, isSelf: false, displayName: "")
            )
        }

        // ── overlays（每次重建，polyline 数量小）──
        map.removeOverlays(map.overlays)
        if cameraMode == .local, route.count >= 2 {
            let polyline = MKPolyline(coordinates: route, count: route.count)
            map.addOverlay(polyline)
        }

        // 把 cameraMode 透给 coordinator → annotation view 才知道按哪种风格渲染
        context.coordinator.cameraMode = cameraMode

        // ── camera ──
        // - cameraMode 变化：完整 setCamera (pitch + distance + center)。
        //   就是 god ↔ local 那个"从天上俯冲下来对着鸵鸟头顶"的电影感镜头。
        // - 模式没变但 followsOstrich：只 setCenter（保留 pitch/distance），
        //   避免 simulator 每 2s 的位置更新触发完整 setCamera 打断 dive-in 动画。
        let modeChanged = context.coordinator.lastCameraMode != cameraMode
        if modeChanged {
            let camera = MKMapCamera(
                lookingAtCenter: ostrichCoord,
                fromDistance: cameraMode.distance,
                pitch: cameraMode.pitch,
                heading: map.camera.heading
            )
            map.setCamera(camera, animated: true)
            context.coordinator.lastCameraMode = cameraMode
            // 模式切换是用户主动行为 → 清掉手势 suppression，让 follow 立刻接管。
            context.coordinator.followSuppressedUntil = .distantPast
        } else if followsOstrich && Date() >= context.coordinator.followSuppressedUntil {
            // 30s 内用户拖过 / 缩过 / 转过地图 → 暂不强制 re-center，让用户自由浏览。
            //
            // animated: false 而不是 true：sim 现在 100ms 一 tick，每次鸵鸟移动 ~0.13m，
            // 如果每次都跑 setCenter 的 ~0.3s 动画会互相打断、相机抖。瞬时 setCenter
            // 配合 annotation 自身的 KVO 平滑过渡，视觉上是连续平滑的跟拍。
            map.setCenter(ostrichCoord, animated: false)
        }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        /// 上次的 cameraMode，用于检测变化触发动画过渡。
        var lastCameraMode: OstrichMapCameraMode = .local
        /// 当前 cameraMode，annotation view 根据它选择渲染风格。
        var cameraMode: OstrichMapCameraMode = .local
        /// 在此时间点之前，followsOstrich 不会主动 setCenter（让用户的手势浏览不被打断）。
        /// 用户每次 pan/pinch/rotate 都会把它推后 30s。
        var followSuppressedUntil: Date = .distantPast
        /// 自己鸵鸟的 annotation 实例。跨多次 updateUIView 复用，
        /// 改 .coordinate 时 MKMapView 会自动用 KVO 做 ~0.25s 平滑过渡 ——
        /// 这是鸵鸟从"瞬移一抽"变成"持续漂动"的关键。
        var selfAnnotation: OstrichAnnotation?

        // MARK: - UIGestureRecognizerDelegate

        /// 让我们的"探测"手势和 MKMapView 内部的 pan/pinch/rotate 并行识别 —— 不抢手势。
        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        // MARK: - 用户手势 → 暂停 follow

        @objc func handleUserGesture(_ gr: UIGestureRecognizer) {
            switch gr.state {
            case .began, .changed:
                followSuppressedUntil = Date().addingTimeInterval(30)
            default:
                break
            }
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ostrich = annotation as? OstrichAnnotation else {
                return nil
            }
            // identifier 把 cameraMode 编进去，避免 dequeue 时拿到错风格的复用 view。
            let modeKey = cameraMode == .god ? "god" : "local"
            let kindKey = ostrich.isSelf ? "self" : "other"
            let identifier = "OstrichPin-\(modeKey)-\(kindKey)"
            let view: MKAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) {
                dequeued.annotation = annotation
                view = dequeued
            } else {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            view.canShowCallout = false

            switch cameraMode {
            case .god:
                // 上帝视角：所有鸵鸟都是匿名小橙点，自己稍大 + 一圈外晕。
                if ostrich.isSelf {
                    view.image = Self.godSelfPinImage
                    view.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
                    view.alpha = 1.0
                } else {
                    view.image = Self.godOtherPinImage
                    view.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
                    view.alpha = 0.85
                }
            case .local:
                // 局域视角：自己用液态鸵鸟头 pin 突出，其他鸵鸟模糊小点。
                if ostrich.isSelf {
                    view.image = Self.localSelfPinImage
                    view.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
                    view.alpha = 1.0
                } else {
                    view.image = Self.localOtherPinImage
                    view.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
                    view.alpha = 0.6
                }
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

        private static let localSelfPinImage: UIImage = {
            renderOstrichPin(size: CGSize(width: 56, height: 56))
        }()

        private static let localOtherPinImage: UIImage = {
            renderDotPin(size: CGSize(width: 18, height: 18), color: UIColor.systemOrange)
        }()

        /// god 模式自己：橙色实心 + 浅光晕一圈。
        private static let godSelfPinImage: UIImage = {
            renderGodPin(size: CGSize(width: 22, height: 22), isSelf: true)
        }()

        /// god 模式其他鸵鸟：纯小橙点。
        private static let godOtherPinImage: UIImage = {
            renderGodPin(size: CGSize(width: 12, height: 12), isSelf: false)
        }()

        /// 用 SwiftUI ImageRenderer 把 LiquidOstrichHeadView 渲染成 UIImage。
        /// iOS 17+ ✓
        ///
        /// 没有奶油圆圈背景 —— 鸵鸟直接站在街上，融入街景。
        /// 鸵鸟自身缩到 size 的 85%，剩 ~3pt 边距给 drop shadow 落地（不被裁掉）。
        private static func renderOstrichPin(size: CGSize) -> UIImage {
            let inner = size.width * 0.85
            let renderer = ImageRenderer(content:
                LiquidOstrichHeadView(size: inner)
                    .frame(width: inner, height: inner)
                    .shadow(color: .black.opacity(0.28), radius: 2.5, y: 2)
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

        /// god 模式 pin：核心实心橙点 + 半透明光晕。
        private static func renderGodPin(size: CGSize, isSelf: Bool) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let cg = ctx.cgContext
                let bounds = CGRect(origin: .zero, size: size)
                let coreColor = UIColor(
                    red: 0xFC / 255.0,
                    green: 0x8B / 255.0,
                    blue: 0x40 / 255.0,
                    alpha: 1.0
                )

                if isSelf {
                    // 外晕
                    coreColor.withAlphaComponent(0.25).setFill()
                    cg.fillEllipse(in: bounds)
                    // 核心
                    coreColor.setFill()
                    cg.fillEllipse(in: bounds.insetBy(dx: size.width * 0.32, dy: size.height * 0.32))
                    // 白细描边
                    UIColor.white.withAlphaComponent(0.8).setStroke()
                    cg.setLineWidth(1.2)
                    cg.strokeEllipse(in: bounds.insetBy(dx: size.width * 0.32, dy: size.height * 0.32))
                } else {
                    coreColor.withAlphaComponent(0.92).setFill()
                    cg.fillEllipse(in: bounds)
                    UIColor.white.withAlphaComponent(0.5).setStroke()
                    cg.setLineWidth(1.0)
                    cg.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
                }
            }
        }
    }
}

// MARK: - 默认坐标

public enum OstrichMapDefaults {
    /// 涩谷站 (BLUEPRINT demo 路径)。
    public static let shibuyaStation = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
}
