// Build iOS and Android launcher assets from the supplied Halladín artwork.
// Run from the repository root: xcrun swift tools/make_ios_icons.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sourceURL = root.appendingPathComponent("app/src/main/assets/Lámpara mágica con lupa azul.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("No se pudo abrir la ilustración de Halladín")
}
func writeIcon(_ path: String, pixels: Int) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("No se pudo crear el icono") }
    context.interpolationQuality = .high
    context.setFillColor(CGColor(red: 1/255, green: 35/255, blue: 105/255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("No se pudo escribir \(path)") }
}
let iosFolder = "flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(iosFolder + "/Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: String]] {
    guard let file = item["filename"], let size = item["size"]?.split(separator: "x").first,
        let points = Double(size), let scaleText = item["scale"], let scale = Double(scaleText.dropLast()) else { continue }
    try writeIcon(iosFolder + "/" + file, pixels: Int((points * scale).rounded()))
}
for (density, pixels) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
    try writeIcon("app/src/main/res/mipmap-\(density)/ic_halladin.png",pixels:pixels)
    try writeIcon("flutter_app/android/app/src/main/res/mipmap-\(density)/ic_launcher.png",pixels:pixels)
}
try writeIcon("app/src/main/res/drawable-nodpi/ic_halladin_foreground.png",pixels:432)
print("Iconos iOS y Android generados desde Lámpara mágica con lupa azul.png")
