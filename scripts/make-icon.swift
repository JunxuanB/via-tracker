import AppKit
let path=CommandLine.arguments[1]
let size=NSSize(width:1024,height:1024)
let image=NSImage(size:size)
image.lockFocus()
NSColor(red:1,green:0.8,blue:0,alpha:1).setFill()
NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
if let symbol=NSImage(systemSymbolName:"tram.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:610,weight:.medium)) {
    let rect=NSRect(x:230,y:190,width:564,height:644)
    symbol.draw(in:rect)
}
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
