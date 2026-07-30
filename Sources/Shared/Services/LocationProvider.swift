import CoreLocation
import Combine
import Foundation

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLocating = false

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() {
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Доступ к геопозиции выключен. Можно выбрать точку на карте вручную."
        @unknown default:
            isLocating = false
            errorMessage = "Не удалось определить статус доступа к геопозиции."
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = status
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                isLocating = true
                self.manager.requestLocation()
            case .denied, .restricted:
                isLocating = false
                errorMessage = "Доступ к геопозиции выключен. Можно выбрать точку на карте вручную."
            case .notDetermined:
                break
            @unknown default:
                isLocating = false
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newest = locations.last else { return }
        let latitude = newest.coordinate.latitude
        let longitude = newest.coordinate.longitude
        let altitude = newest.altitude
        let horizontalAccuracy = newest.horizontalAccuracy
        let verticalAccuracy = newest.verticalAccuracy
        let timestamp = newest.timestamp
        Task { @MainActor [weak self] in
            self?.location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                timestamp: timestamp
            )
            self?.isLocating = false
            self?.errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.isLocating = false
            self?.errorMessage = "Не удалось получить текущую геопозицию: \(description)"
        }
    }
}
