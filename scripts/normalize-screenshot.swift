// Losslessly remove the alpha channel from a native simulator screenshot.
// Uses macOS ImageIO / CoreGraphics; no third-party dependencies are required.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

for argument in CommandLine.arguments.dropFirst() {
  let url = URL(fileURLWithPath: argument)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { fatalError("Cannot decode screenshot: \(argument)") }
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let output = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).normalized.png")
  guard let rgb = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fatalError("Cannot encode screenshot: \(argument)") }
  CGImageDestinationAddImage(destination, rgb, nil)
  guard CGImageDestinationFinalize(destination),
    let check = CGImageSourceCreateWithURL(output as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
    (properties[kCGImagePropertyHasAlpha] as? Bool) != true
  else { fatalError("Screenshot still has an alpha channel: \(argument)") }
  _ = try FileManager.default.replaceItemAt(url, withItemAt: output)
}
