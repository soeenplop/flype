import AppKit

// Canonical, editable artwork shared by the iOS asset catalog and macOS icon family.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("shared/Resources")
let catalog = resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let iconset = root.appendingPathComponent("build/Flype.iconset")
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int, mac: Bool, dark: Bool = false, destination: URL) throws {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = mac ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let tile = CGPath(roundedRect: rect, cornerWidth: mac ? 184 : 0, cornerHeight: mac ? 184 : 0, transform: nil)
    if mac {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: CGColor(gray: 0, alpha: 0.22))
        context.setFillColor(CGColor(red: 0.35, green: 0.22, blue: 0.55, alpha: 1))
        context.addPath(tile)
        context.fillPath()
        context.restoreGState()
    }
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let top: [CGFloat] = dark ? [0.24, 0.16, 0.36, 1.0] : [0.48, 0.34, 0.70, 1.0]
    let bottom: [CGFloat] = dark ? [0.13, 0.08, 0.22, 1.0] : [0.32, 0.20, 0.51, 1.0]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: top)!,
            CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: bottom)!,
        ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.minY), options: [])
    context.restoreGState()
    // Five round strokes echo the waveform used throughout the app.
    let scale: CGFloat = mac ? 0.805 : 1
    context.translateBy(x: 512, y: 512)
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(CGColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1))
    for (index, height) in [180.0, 340.0, 500.0, 340.0, 180.0].enumerated() {
        let bar = CGRect(x: CGFloat(index) * 110 - 256, y: -height / 2, width: 72, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 36, cornerHeight: 36, transform: nil))
        context.fillPath()
    }
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

try render(size: 1024, mac: false, destination: catalog.appendingPathComponent("AppIcon.png"))
try render(size: 1024, mac: false, dark: true, destination: catalog.appendingPathComponent("AppIcon-dark.png"))
for size in [16, 32, 128, 256, 512] {
    try render(size: size, mac: true, destination: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2, mac: true, destination: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let contents: [String: Any] = [
    "images": [
        ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        [
            "filename": "AppIcon-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
            "appearances": [["appearance": "luminosity", "value": "dark"]],
        ],
    ], "info": ["author": "xcode", "version": 1],
]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(
    to: catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(
    withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]
).write(to: resources.appendingPathComponent("Assets.xcassets/Contents.json"))
