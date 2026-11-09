import Foundation
import ImageIO

/// Immutable shutter-time metadata, safe to pass to the capture queue. Never
/// geotag later from wherever the phone happens to be during development.
struct MobileCaptureLocation: Sendable, Equatable {
    static let preferenceKey = "mobile.camera.recordLocation"
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
    let timestamp: Date

    func isUsable(at date: Date) -> Bool {
        let age = date.timeIntervalSince(timestamp)
        return latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 &&
            accuracy.isFinite && accuracy >= 0 && age >= -5 && age <= 60
    }

    var gps: [String: Any] {
        var result: [String: Any] = [
            kCGImagePropertyGPSVersion as String: [2, 3, 0, 0],
            kCGImagePropertyGPSLatitude as String: abs(latitude),
            kCGImagePropertyGPSLatitudeRef as String: latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude as String: abs(longitude),
            kCGImagePropertyGPSLongitudeRef as String: longitude < 0 ? "W" : "E",
            kCGImagePropertyGPSHPositioningError as String: accuracy,
        ]
        if let altitude, altitude.isFinite {
            result[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            result[kCGImagePropertyGPSAltitudeRef as String] = altitude < 0 ? 1 : 0
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: timestamp)
        result[kCGImagePropertyGPSDateStamp as String] = String(format: "%04d:%02d:%02d", parts.year!, parts.month!, parts.day!)
        result[kCGImagePropertyGPSTimeStamp as String] = String(format: "%02d:%02d:%06.3f", parts.hour!, parts.minute!,
            Double(parts.second!) + Double(parts.nanosecond ?? 0) / 1_000_000_000)
        return result
    }

    static func snapshot(_ value: Self?, enabled: Bool, at date: Date = .now) -> Self? {
        enabled && value?.isUsable(at: date) == true ? value : nil
    }
}

#if SILVERPHASE_APP
import CoreLocation
import Observation

/// Foreground camera use only. No background entitlement or persistent track.
@MainActor @Observable final class MobileCameraLocation: NSObject, CLLocationManagerDelegate {
    static let shared = MobileCameraLocation()
    private let manager = CLLocationManager()
    private var cameraActive = false
    private var enabled = false
    private var requested = false
    private var updating = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var latest: MobileCaptureLocation?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        authorization = manager.authorizationStatus
    }
    var denied: Bool { authorization == .denied || authorization == .restricted }

    func setEnabled(_ value: Bool, requestPermission: Bool = false) {
        enabled = value
        if value && requestPermission { requestAuthorization() }
        update()
    }
    func setCameraActive(_ value: Bool, enabled: Bool) {
        cameraActive = value; self.enabled = enabled
        update()
    }
    func snapshot(enabled: Bool, at date: Date = .now) -> MobileCaptureLocation? {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { return nil }
        return MobileCaptureLocation.snapshot(latest, enabled: enabled && cameraActive, at: date)
    }
    private func requestAuthorization() {
        guard authorization == .notDetermined, !requested else { return }
        requested = true
        manager.requestWhenInUseAuthorization()
    }
    private func update() {
        guard enabled && cameraActive else {
            manager.stopUpdatingLocation(); updating = false; latest = nil; return
        }
        if authorization == .notDetermined { requestAuthorization() }
        let authorized = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        if authorized && !updating { manager.startUpdatingLocation(); updating = true }
        if !authorized { manager.stopUpdatingLocation(); updating = false; latest = nil }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = self.manager.authorizationStatus
            self.update()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.enabled, self.cameraActive,
                  let location = locations.last else { return }
            let value = MobileCaptureLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
            if value.isUsable(at: .now) { self.latest = value }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient missing fix must not block the shutter or reuse an old fix.
        Task { @MainActor [weak self] in self?.latest = nil }
    }
}
#endif
