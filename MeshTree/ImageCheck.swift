import Foundation
import ImageIO
import Accelerate

//took a long time to figure out why it wasn't detecting blurry pictures

enum ImageFlag: Equatable {
    case none
    case blurry
    case lowResolution
    case unreadable

    var lable: String {
        switch self {
        case .none: return ""
        case .blurry: return "Blurry"
        case .lowResolution: return "Low resolution"
        case .unreadable: return "Unreadable"
        }
    }
}

struct CaptureImage: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var flag: ImageFlag = .none
    var isFlagged: Bool { flag != .none }
}

enum ImageCheck {
    static let minDimension = 300
    static let blurVarianceThreshold: Double = 45

    static func analyze(url: URL) -> ImageFlag {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .unreadable
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .unreadable
        }

        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0

        if width == 0 || height == 0 {
            return .unreadable
        }
        if width < minDimension || height < minDimension {
            return .lowResolution
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return .unreadable
        }

        guard let variance = laplacianVariance(of: thumbnail) else {
            return .unreadable
        }


        return variance < blurVarianceThreshold ? .blurry : .none
    }

    // laplacian variance blur check, standard 3x3 kernel for this
    private static func laplacianVariance(of cgImage: CGImage) -> Double? {
        guard let format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            renderingIntent: .defaultIntent
        ) else {
            return nil
        }
        var mutFormat = format

        guard var grayBuffer = try? vImage_Buffer(width: cgImage.width, height: cgImage.height, bitsPerPixel: 8) else {
            return nil
        }
        defer { grayBuffer.free() }

        let initResult = vImageBuffer_InitWithCGImage(&grayBuffer, &mutFormat, nil, cgImage, vImage_Flags(kvImageNoFlags))
        if initResult != kvImageNoError {
            return nil
        }

        guard var outBuffer = try? vImage_Buffer(width: cgImage.width, height: cgImage.height, bitsPerPixel: 8) else {
            return nil
        }
        defer { outBuffer.free() }

        var kernel: [Int16] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        vImageConvolve_Planar8(&grayBuffer, &outBuffer, nil, 0, 0, &kernel, 3, 3, 1, 128, vImage_Flags(kvImageEdgeExtend))

        let w = Int(outBuffer.width)
        let h = Int(outBuffer.height)
        let rowBytes = outBuffer.rowBytes
        let pixels = outBuffer.data.bindMemory(to: UInt8.self, capacity: rowBytes * h)

        var sum: Double = 0
        var sumSq: Double = 0

        for y in 0..<h {
            let row = y * rowBytes
            for x in 0..<w {
                let v = Double(pixels[row + x]) - 128.0
                sum += v
                sumSq += v * v
            }
        }

        let n = Double(w * h)
        let mean = sum / n
        return (sumSq / n) - (mean * mean)
    }
}
