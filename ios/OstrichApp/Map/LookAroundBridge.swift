// LookAroundBridge.swift
// MKLookAroundViewController 的 SwiftUI 包装。
// BLUEPRINT §10.4：鸵鸟到达 POI 时弹出 sheet，给用户「鸵鸟真的去过那里」的真实感。

import SwiftUI
import MapKit
import CoreLocation

/// 异步加载 Look Around 场景的 ViewModel。
@MainActor
public final class LookAroundLoader: ObservableObject {

    public enum State: Equatable {
        case idle
        case loading
        case available(MKLookAroundScene)
        case unavailable

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.unavailable, .unavailable):
                return true
            case (.available, .available):
                return true
            default:
                return false
            }
        }
    }

    @Published public private(set) var state: State = .idle

    public init() {}

    public func load(coordinate: CLLocationCoordinate2D) {
        state = .loading
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        Task { @MainActor in
            do {
                let scene = try await request.scene
                if let scene = scene {
                    self.state = .available(scene)
                } else {
                    self.state = .unavailable
                }
            } catch {
                self.state = .unavailable
            }
        }
    }
}

// MARK: - View

public struct LookAroundBridge: View {
    public let coordinate: CLLocationCoordinate2D
    public let onDismiss: () -> Void

    @StateObject private var loader = LookAroundLoader()

    public init(
        coordinate: CLLocationCoordinate2D,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.coordinate = coordinate
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            switch loader.state {
            case .idle, .loading:
                Color.black.ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            case .available(let scene):
                LookAroundViewControllerRepresentable(scene: scene)
                    .ignoresSafeArea()
            case .unavailable:
                Color.black.ignoresSafeArea()
                VStack(spacing: OstrichSpacing.s) {
                    Image(systemName: "binoculars")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("这里没有街景")
                        .font(OstrichTypography.body)
                        .foregroundStyle(.white)
                    Button("关闭", action: onDismiss)
                        .foregroundStyle(.white)
                        .padding(.top, OstrichSpacing.s)
                }
            }
        }
        .onAppear {
            loader.load(coordinate: coordinate)
        }
    }
}

// MARK: - MKLookAroundViewController wrapper

struct LookAroundViewControllerRepresentable: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let vc = MKLookAroundViewController(scene: scene)
        vc.isNavigationEnabled = true
        vc.showsRoadLabels = true
        return vc
    }

    func updateUIViewController(_ uiViewController: MKLookAroundViewController, context: Context) {
        uiViewController.scene = scene
    }
}
