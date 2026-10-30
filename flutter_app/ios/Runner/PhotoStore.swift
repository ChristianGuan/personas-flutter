import Foundation
import Photos
import ImageIO
import UIKit
import UniformTypeIdentifiers
import CryptoKit

struct PhotoPixels { let data: Data; let width: Int; let height: Int }
final class PhotoStore {
    static let maxBytes = 64 * 1024 * 1024
    let directory: URL
    private let io = DispatchQueue(label: "personas.photos.io", qos: .userInitiated, attributes: .concurrent)
    init() throws {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PersonasSession", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    var access: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "full"
        case .limited: return "limited"
        default: return "none"
        }
    }
    func catalog() -> [String: Any] {
        guard access != "none" else { return ["access": "none", "albums": []] }
        var output: [[String: Any]] = []
        for type in [PHAssetCollectionType.smartAlbum, .album] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
                let assets = self.assets(collection: collection)
                if let cover = assets.firstObject, assets.count > 0 {
                    output.append(["id": collection.localIdentifier, "name": collection.localizedTitle ?? "Sin nombre", "cover": "ph:" + cover.localIdentifier, "count": assets.count])
                }
            }
        }
        return ["access": access, "albums": output]
    }
    private func assets(collection: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: options)
    }
    func albumPhotos(_ id: String) throws -> [String] {
        guard access != "none", let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw photoError("No tenemos acceso a este álbum. Revisa el permiso o elige fotos individuales.")
        }
        var result: [String] = []; assets(collection: collection).enumerateObjects { asset, _, _ in result.append("ph:" + asset.localIdentifier) }; return result
    }
    func ownedURL(_ id: String) throws -> URL {
        guard let url = URL(string: id), url.isFileURL,
              url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") else { throw photoError("La foto ya no está disponible. Vuelve a elegirla.") }
        return url
    }
    func copyOriginal(_ url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maxBytes else { throw photoError("Esta imagen supera el tamaño admitido. Elige una copia más pequeña.") }
        // Re-selecting an identical provider file must not add another candidate.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent(digest).appendingPathExtension("image")
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: url, to: destination) }
        return destination.absoluteString
    }
    func load(_ id: String, operation: PhotoOperation? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
        if id.hasPrefix("ph:") {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [String(id.dropFirst(3))], options: nil).firstObject,
                  asset.mediaType == .image else { completion(.failure(photoError("No tenemos acceso a esta foto. Vuelve a elegirla."))); return }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
                completion(.failure(photoError("No se pudo leer el original de esta foto."))); return
            }
            let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
            let accumulator = AssetData()
            let manager = PHAssetResourceManager.default()
            let request = manager.requestData(for: resource, options: options, dataReceivedHandler: { chunk in
                accumulator.append(chunk)
            }, completionHandler: { error in completion(accumulator.finish(error)) })
            accumulator.setRequest(request)
            operation?.onCancel { manager.cancelDataRequest(request) }
        } else {
            io.async {
                do {
                    guard operation?.cancelled != true else { throw photoError("Acción cancelada.") }
                    let url = try self.ownedURL(id)
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.maxBytes else { throw photoError("La imagen supera el tamaño admitido.") }
                    completion(.success(try Data(contentsOf: url, options: .mappedIfSafe)))
                } catch { completion(.failure(error)) }
            }
        }
    }
    static func decode(_ bytes: Data, edge: Int) throws -> PhotoPixels {
        guard bytes.count <= maxBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.int64Value > 0, height.int64Value > 0,
              width.int64Value <= 100_000_000 / height.int64Value else {
            throw photoError("No pudimos leer esta imagen. Puede estar incompleta o usar un formato no compatible.")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(64, min(3200, edge)),
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw photoError("No pudimos decodificar la imagen. Vuelve a descargar el original.") }
        var output = Data(count: image.width * image.height * 4)
        let success = output.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard success else { throw photoError("No se pudo preparar el color de la imagen.") }
        return PhotoPixels(data: output, width: image.width, height: image.height)
    }
    static func preview(_ bytes: Data, edge: Int, crop: [Double]?) throws -> Data {
        // Decode enough source detail before extracting a small face region.
        var sourceEdge = edge
        if let crop = crop, crop.count == 4 {
            let fraction = min(crop[2], crop[3])
            if fraction.isFinite && fraction > 0 {
                sourceEdge = min(3200, max(edge, Int(Double(edge) / max(0.01, fraction))))
            }
        }
        let pixels = try decode(bytes, edge: sourceEdge)
        let provider = CGDataProvider(data: pixels.data as CFData)!
        guard var image = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw photoError("No se pudo ampliar la foto.") }
        if let crop = crop, crop.count == 4 {
            let bounds = CGRect(x: crop[0] * Double(pixels.width), y: crop[1] * Double(pixels.height), width: crop[2] * Double(pixels.width), height: crop[3] * Double(pixels.height))
            let expanded = bounds.insetBy(dx: -bounds.width * 0.18, dy: -bounds.height * 0.18).intersection(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)).integral
            if let cropped = image.cropping(to: expanded), !expanded.isEmpty { image = cropped }
        }
        guard let output = UIImage(cgImage: image).jpegData(compressionQuality: 0.94) else { throw photoError("No se pudo mostrar la foto.") }; return output
    }
    func shareFile(_ data: Data) throws -> URL {
        var ext = "image"
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source),
           let value = UTType(type as String)?.preferredFilenameExtension { ext = value }
        let url = directory.appendingPathComponent("share-" + UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: url, options: .atomic); return url
    }
    func clear() throws { try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
}

private final class AssetData {
    private let lock = NSLock()
    private var bytes = Data()
    private var overflow = false
    private var request: PHAssetResourceDataRequestID?
    func setRequest(_ id: PHAssetResourceDataRequestID) {
        let stop = lock.withLock { request = id; return overflow }; if stop { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func append(_ data: Data) {
        let cancel = lock.withLock { () -> PHAssetResourceDataRequestID? in
            if overflow { return nil }; if bytes.count + data.count > PhotoStore.maxBytes { overflow = true; return request }
            bytes.append(data); return nil
        }; if let id = cancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func finish(_ error: Error?) -> Result<Data, Error> { lock.withLock {
        if overflow { return .failure(photoError("La imagen supera el tamaño admitido.")) }
        if let error = error { return .failure(error) }; return .success(bytes)
    }}
}
