import Foundation

struct GeoLocation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let uncertainty: Double?

    init?(latitude: Double, longitude: Double, uncertainty: Double? = nil) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        if let uncertainty, (!uncertainty.isFinite || uncertainty < 0) {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
        self.uncertainty = uncertainty
    }

    init?(uri: String) {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("geo:") else { return nil }
        let payload = trimmed.dropFirst(4)
        let components = payload.split(separator: ";", omittingEmptySubsequences: false)
        guard let coordinatePart = components.first else { return nil }
        let coordinates = coordinatePart.split(separator: ",", omittingEmptySubsequences: false)
        guard coordinates.count == 2 || coordinates.count == 3,
              let latitude = Double(coordinates[0]),
              let longitude = Double(coordinates[1]) else { return nil }

        if coordinates.count == 3, Double(coordinates[2]) == nil {
            return nil
        }
        var uncertainty: Double?
        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            if pair[0].lowercased() == "u" {
                guard let value = Double(pair[1]) else { return nil }
                uncertainty = value
            }
        }
        self.init(latitude: latitude, longitude: longitude, uncertainty: uncertainty)
    }

    var uriString: String {
        let coordinates = String(
            format: "geo:%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            latitude,
            longitude
        )
        guard let uncertainty else { return coordinates }
        return coordinates + String(
            format: ";u=%.0f",
            locale: Locale(identifier: "en_US_POSIX"),
            uncertainty
        )
    }
}
