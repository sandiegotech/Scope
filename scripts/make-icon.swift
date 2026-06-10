#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let supportURL = rootURL.appendingPathComponent("Support", isDirectory: true)
let iconsetURL = supportURL.appendingPathComponent("Scope.iconset", isDirectory: true)
let previewURL = supportURL.appendingPathComponent("ScopeIconPreview.png")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconImage {
    let name: String
    let size: Int
}

let images = [
    IconImage(name: "icon_16x16.png", size: 16),
    IconImage(name: "icon_16x16@2x.png", size: 32),
    IconImage(name: "icon_32x32.png", size: 32),
    IconImage(name: "icon_32x32@2x.png", size: 64),
    IconImage(name: "icon_128x128.png", size: 128),
    IconImage(name: "icon_128x128@2x.png", size: 256),
    IconImage(name: "icon_256x256.png", size: 256),
    IconImage(name: "icon_256x256@2x.png", size: 512),
    IconImage(name: "icon_512x512.png", size: 512),
    IconImage(name: "icon_512x512@2x.png", size: 1024)
]

for image in images {
    let data = drawIcon(size: image.size)
    try data.write(to: iconsetURL.appendingPathComponent(image.name))
}

try drawIcon(size: 1024).write(to: previewURL)

func drawIcon(size: Int) -> Data {
    let scale = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: scale, height: scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    rect.fill()

    let iconRect = rect.insetBy(dx: scale * 0.08, dy: scale * 0.08)
    let corner = scale * 0.21
    let basePath = NSBezierPath(roundedRect: iconRect, xRadius: corner, yRadius: corner)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = scale * 0.045
    shadow.shadowOffset = CGSize(width: 0, height: -scale * 0.018)
    shadow.set()

    NSColor(red: 0.94, green: 0.96, blue: 0.95, alpha: 1).setFill()
    basePath.fill()

    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    let gradient = NSGradient(colors: [
        NSColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1),
        NSColor(red: 0.86, green: 0.93, blue: 0.91, alpha: 1)
    ])!
    gradient.draw(in: basePath, angle: -35)

    let diskFrame = CGRect(
        x: scale * 0.265,
        y: scale * 0.275,
        width: scale * 0.47,
        height: scale * 0.47
    )

    let diskPath = NSBezierPath(ovalIn: diskFrame)
    NSColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1).setFill()
    diskPath.fill()

    let innerFrame = diskFrame.insetBy(dx: scale * 0.115, dy: scale * 0.115)
    let innerPath = NSBezierPath(ovalIn: innerFrame)
    NSColor(red: 0.94, green: 0.96, blue: 0.95, alpha: 1).setFill()
    innerPath.fill()

    let hubFrame = diskFrame.insetBy(dx: scale * 0.205, dy: scale * 0.205)
    NSColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(ovalIn: hubFrame).fill()

    let accentFrame = CGRect(
        x: scale * 0.62,
        y: scale * 0.61,
        width: scale * 0.11,
        height: scale * 0.11
    )
    NSColor(red: 0.00, green: 0.63, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(ovalIn: accentFrame).fill()

    let footerFrame = CGRect(
        x: scale * 0.34,
        y: scale * 0.22,
        width: scale * 0.32,
        height: scale * 0.035
    )
    let footerPath = NSBezierPath(roundedRect: footerFrame, xRadius: scale * 0.018, yRadius: scale * 0.018)
    NSColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 0.22).setFill()
    footerPath.fill()

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}
