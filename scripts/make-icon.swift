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
    let s = CGFloat(size)
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

    let cream = NSColor(red: 0.941, green: 0.929, blue: 0.910, alpha: 1)
    let navy  = NSColor(red: 0.051, green: 0.082, blue: 0.149, alpha: 1)

    // Full canvas — macOS applies squircle mask at system level
    cream.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: s, height: s)).fill()

    navy.setFill()
    navy.setStroke()

    let strokeW: CGFloat = s * 0.044

    // Box — flat device body, centered
    let boxW    = s * 0.580
    let boxH    = s * 0.230
    let boxX    = (s - boxW) / 2
    let boxCY   = s * 0.500
    let boxY    = boxCY - boxH / 2
    let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)

    let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: s * 0.036, yRadius: s * 0.036)
    boxPath.lineWidth = strokeW
    boxPath.stroke()

    // Two port circles on the left side
    let portR   = s * 0.032
    let portCY  = boxCY
    let port1CX = boxX + boxW * 0.195
    let port2CX = boxX + boxW * 0.385

    for cx in [port1CX, port2CX] {
        NSBezierPath(ovalIn: CGRect(
            x: cx - portR, y: portCY - portR,
            width: portR * 2, height: portR * 2
        )).fill()
    }

    // Three vent slots on the right side
    let ventX  = boxX + boxW * 0.618
    let ventW  = boxW * 0.272
    let ventH  = s * 0.017
    let ventR  = ventH / 2
    let vGap   = s * 0.044

    for offset in [-vGap, 0, vGap] {
        let ventRect = CGRect(
            x: ventX,
            y: boxCY + offset - ventH / 2,
            width: ventW,
            height: ventH
        )
        NSBezierPath(roundedRect: ventRect, xRadius: ventR, yRadius: ventR).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}
