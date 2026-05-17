import Foundation
import CoreLocation
import WeatherKit

/// 用户当前天气的简洁快照，给 HomeView topBar 显示。
public struct WeatherSnapshot: Equatable, Sendable {
    /// 城市友好名（"东京"、"涩谷"…）。来自 CLGeocoder 反向编码。
    public let city: String
    /// 中文天气描述（"晴"/"多云"/"雨"…）。
    public let condition: String
    /// 摄氏度整数。
    public let temperatureCelsius: Int

    /// 给 HomeView 显示用：「今天 东京 晴 23°」。
    public var displayString: String {
        "今天\(city) \(condition) \(temperatureCelsius)°"
    }
}

/// 一次性拉取用户位置 + WeatherKit 天气 + 反向编码城市名。
/// 不持有任何长生命周期资源；调用方 (WeatherViewModel) 决定何时调用 / 缓存。
@MainActor
public final class WeatherFetcher: NSObject {

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer  // 城市级精度够了
    }

    /// 异步获取用户当前位置（请求权限 → 一次性定位）。
    public func currentLocation() async throws -> CLLocation {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // 后续 didChangeAuthorization 触发 requestLocation()
        case .restricted, .denied:
            throw WeatherFetcherError.locationDenied
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        @unknown default:
            throw WeatherFetcherError.locationDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
        }
    }

    /// 一站式：定位 → 拉天气 → 反向编码 → 返回 snapshot。
    public func fetch() async throws -> WeatherSnapshot {
        let location = try await currentLocation()
        async let weather = weatherService.weather(for: location)
        async let placemarks = geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: "zh_CN")
        )

        let current = try await weather.currentWeather
        let placemark = try await placemarks.first
        let city = placemark?.locality
            ?? placemark?.subLocality
            ?? placemark?.administrativeArea
            ?? ""
        let tempC = Int(current.temperature.converted(to: .celsius).value.rounded())
        return WeatherSnapshot(
            city: city,
            condition: Self.chineseCondition(current.condition),
            temperatureCelsius: tempC
        )
    }

    /// WeatherKit `WeatherCondition` 枚举 → 中文短描述。
    /// 覆盖常见值；陌生值回退到通用"天气"。
    private static func chineseCondition(_ c: WeatherCondition) -> String {
        switch c {
        case .clear, .mostlyClear: return "晴"
        case .partlyCloudy: return "多云"
        case .mostlyCloudy, .cloudy: return "阴"
        case .foggy, .haze, .smoky: return "雾"
        case .breezy, .windy: return "有风"
        case .drizzle: return "毛毛雨"
        case .rain, .sunShowers: return "雨"
        case .heavyRain: return "大雨"
        case .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .thunderstorms: return "雷雨"
        case .flurries, .snow, .sunFlurries, .wintryMix: return "雪"
        case .blizzard, .blowingSnow, .heavySnow: return "大雪"
        case .freezingDrizzle, .freezingRain, .sleet: return "冻雨"
        case .hail: return "冰雹"
        case .hot: return "炎热"
        case .frigid: return "严寒"
        case .tropicalStorm, .hurricane: return "暴风雨"
        case .blowingDust: return "扬尘"
        default: return "天气"
        }
    }
}

public enum WeatherFetcherError: Error {
    case locationDenied
    case locationFailed(underlying: Error)
}

extension WeatherFetcher: CLLocationManagerDelegate {

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                locationContinuation?.resume(throwing: WeatherFetcherError.locationDenied)
                locationContinuation = nil
            default:
                break
            }
        }
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard let loc = locations.last else { return }
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
        }
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: WeatherFetcherError.locationFailed(underlying: error))
            locationContinuation = nil
        }
    }
}
