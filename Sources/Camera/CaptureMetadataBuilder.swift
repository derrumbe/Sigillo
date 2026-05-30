import CoreLocation
import Foundation
import ImageIO
import UIKit

/// Builds the `stds.exif` assertion payload for a captured photo, including only
/// the categories enabled in ``MetadataOptions``.
///
/// Camera settings are read from the EXIF already embedded in the captured JPEG;
/// device info comes from the running device; GPS comes from CoreLocation.
/// The shape mirrors the C2PA EXIF assertion (JSON-LD with the `exif`
/// namespace), matching the c2pa-ios example app.
@MainActor
struct CaptureMetadataBuilder {
    let options: MetadataOptions

    private var data: [String: Any] = [
        "@context": ["exif": "http://ns.adobe.com/exif/1.0/"]
    ]

    init(options: MetadataOptions) {
        self.options = options
    }

    /// Returns the assertion data, or `nil` if nothing is enabled / available.
    mutating func build(jpeg: Data, location: CLLocation?) -> [String: Any]? {
        if options.deviceInfo {
            data["exif:Make"] = "Apple"
            data["exif:Model"] = Self.deviceModelIdentifier
            data["exif:Software"] = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        }

        if options.dateTime {
            let now = ISO8601DateFormatter().string(from: Date())
            data["exif:DateTimeOriginal"] = now
            data["exif:DateTimeDigitized"] = now
        }

        if options.cameraSettings {
            applyCameraSettings(from: jpeg)
        }

        if options.location {
            applyLocation(location)
        }

        // More than just the @context means we actually have something to embed.
        return data.count > 1 ? data : nil
    }

    // MARK: - Camera settings (from the captured JPEG's EXIF)

    private mutating func applyCameraSettings(from jpeg: Data) {
        guard
            let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return }

        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let mappings: [(CFString, String)] = [
                (kCGImagePropertyExifFocalLength, "exif:FocalLength"),
                (kCGImagePropertyExifFocalLenIn35mmFilm, "exif:FocalLengthIn35mmFilm"),
                (kCGImagePropertyExifFNumber, "exif:FNumber"),
                (kCGImagePropertyExifApertureValue, "exif:ApertureValue"),
                (kCGImagePropertyExifExposureTime, "exif:ExposureTime"),
                (kCGImagePropertyExifShutterSpeedValue, "exif:ShutterSpeedValue"),
                (kCGImagePropertyExifExposureBiasValue, "exif:ExposureBiasValue"),
                (kCGImagePropertyExifExposureProgram, "exif:ExposureProgram"),
                (kCGImagePropertyExifMeteringMode, "exif:MeteringMode"),
                (kCGImagePropertyExifWhiteBalance, "exif:WhiteBalance"),
                (kCGImagePropertyExifFlash, "exif:Flash"),
                (kCGImagePropertyExifLensModel, "exif:LensModel"),
                (kCGImagePropertyExifColorSpace, "exif:ColorSpace"),
            ]
            for (key, label) in mappings {
                if let value = exif[key as String] {
                    data[label] = "\(value)"
                }
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first {
                data["exif:ISOSpeedRatings"] = "\(iso)"
            }
        }

        if let width = properties[kCGImagePropertyPixelWidth as String] {
            data["exif:PixelXDimension"] = "\(width)"
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] {
            data["exif:PixelYDimension"] = "\(height)"
        }
    }

    // MARK: - GPS

    private mutating func applyLocation(_ location: CLLocation?) {
        guard let location, location.horizontalAccuracy >= 0 else { return }
        data["exif:GPSLatitude"] = "\(location.coordinate.latitude)"
        data["exif:GPSLongitude"] = "\(location.coordinate.longitude)"
        if location.verticalAccuracy >= 0 {
            data["exif:GPSAltitude"] = "\(location.altitude)"
        }
        data["exif:GPSTimeStamp"] = ISO8601DateFormatter().string(from: location.timestamp)
    }

    // MARK: - Device identifier (e.g. "iPhone16,2")

    static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) }
        }
        return machine ?? UIDevice.current.model
    }
}
