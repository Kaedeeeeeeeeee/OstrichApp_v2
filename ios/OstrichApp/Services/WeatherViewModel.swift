import Foundation
import SwiftUI

/// HomeView topBar 用的天气状态：loading / 成功 / 失败 / 拒绝授权。
public enum WeatherUIState: Equatable {
    case idle
    case loading
    case loaded(WeatherSnapshot)
    case denied
    case failed
}

/// 包装 WeatherFetcher 给 SwiftUI 用。HomeView 第一次 onAppear 时 trigger
/// 一次 refresh()；失败/拒绝时静默退化，HomeView 显示 mock 字符串占位。
@MainActor
public final class WeatherViewModel: ObservableObject {
    @Published public private(set) var state: WeatherUIState = .idle

    private let fetcher: WeatherFetcher

    public init(fetcher: WeatherFetcher? = nil) {
        self.fetcher = fetcher ?? WeatherFetcher()
    }

    public func refresh() async {
        // 已经在加载或已成功就跳过（避免 onAppear 重复调）。
        if case .loading = state { return }
        if case .loaded = state { return }
        state = .loading
        do {
            let snapshot = try await fetcher.fetch()
            state = .loaded(snapshot)
        } catch WeatherFetcherError.locationDenied {
            state = .denied
        } catch {
            state = .failed
        }
    }

    /// HomeView 直接绑这个字符串显示。失败/未授权时给一个友好占位。
    public var displayString: String {
        switch state {
        case .idle, .loading: return "正在看今天的天气…"
        case .loaded(let snap): return snap.displayString
        case .denied: return "（鸵鸟看不到你这里的天气）"
        case .failed: return "（天气没拿到）"
        }
    }
}
