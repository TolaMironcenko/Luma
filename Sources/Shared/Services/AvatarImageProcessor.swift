import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AvatarImageProcessor {
    static func pngData(from sourceData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512
                ] as CFDictionary
              ) else {
            throw AvatarImageError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AvatarImageError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AvatarImageError.encodingFailed
        }
        return output as Data
    }
}

private enum AvatarImageError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Не удалось прочитать выбранное изображение."
        case .encodingFailed:
            return "Не удалось подготовить аватар в формате PNG."
        }
    }
}
