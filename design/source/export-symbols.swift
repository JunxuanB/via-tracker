import AppKit
let names = ["tram.fill", "plus", "minus", "chevron.left", "chevron.right", "arrow.up.right", "arrow.right", "arrow.triangle.2.circlepath", "magnifyingglass", "calendar", "clock", "clock.fill", "location.fill", "location", "wifi.slash", "wifi", "checkmark", "checkmark.circle.fill", "exclamationmark.triangle", "bell", "bell.slash", "gearshape", "ellipsis", "xmark", "square.and.arrow.up", "figure.walk", "arrow.triangle.branch", "map", "list.bullet", "house", "house.fill", "sun.max", "moon", "circle", "circle.fill", "stop.circle", "info.circle", "antenna.radiowaves.left.and.right", "bolt.fill", "battery.100", "wifi.exclamationmark", "arrow.down", "mappin.and.ellipse", "arrow.clockwise", "hand.tap", "slider.horizontal.3"]
let dest = CommandLine.arguments[1]
for name in names {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)) else { continue }
    let size = NSSize(width: 64, height: 64)
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    NSColor.black.set()
    let rect = NSRect(x: (64-image.size.width)/2, y: (64-image.size.height)/2, width: image.size.width, height: image.size.height)
    image.draw(in: rect)
    canvas.unlockFocus()
    if let data = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: dest).appendingPathComponent(name + ".png"))
    }
}
print("Exported SF Symbols to \(dest)")
