// Render the existing Android ic_personas vector as iOS icon assets.
// Run from the repository root: xcrun swift tools/make_ios_icons.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: "flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: String]] {
    guard let file = item["filename"], let size = item["size"]?.split(separator: "x").first,
          let points = Double(size), let scale = Double(item["scale"]!.dropLast()) else { continue }
    let pixels = Int(points * scale)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 48, y: CGFloat(pixels) / 48)
    context.translateBy(x: 0, y: 48); context.scaleBy(x: 1, y: -1)
    context.setFillColor(CGColor(red: 32/255, green: 92/255, blue: 84/255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 16, y: 8, width: 16, height: 16))
    context.move(to: CGPoint(x: 10, y: 40))
    context.addCurve(to: CGPoint(x: 38, y: 40), control1: CGPoint(x: 10, y: 25), control2: CGPoint(x: 38, y: 25))
    context.closePath(); context.fillPath()
    let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(file) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("No se pudo escribir el icono") }
}
print("Iconos iOS generados con el símbolo de Personas existente.")
