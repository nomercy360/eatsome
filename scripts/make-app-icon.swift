#!/usr/bin/env swift
// Draws the opaque fallback/marketing icon that accompanies AppIcon.icon.
// The Icon Composer bundle is the adaptive Liquid Glass source used by Xcode;
// keep this fallback visually aligned with its SVG layers.
//
//   swift scripts/make-app-icon.swift
//
// Output has no alpha channel — the App Store rejects icons that carry one.
import AppKit
import CoreGraphics
import Foundation

let size = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let navy = rgb(11, 53, 107)
let blue = rgb(63, 138, 247)
let plate = rgb(255, 244, 223)
let almond = rgb(217, 135, 50)
let crease = rgb(117, 55, 20)

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create the drawing context") }

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let side = CGFloat(size)

// Background fill matches the Icon Composer gradient.
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [blue, navy] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: []
)

// The plate.
let plateRadius = side * 0.322
let centre = CGPoint(x: side / 2, y: side / 2)
context.setFillColor(plate)
context.fillEllipse(in: CGRect(
    x: centre.x - plateRadius,
    y: centre.y - plateRadius,
    width: plateRadius * 2,
    height: plateRadius * 2
))

// A warm, slightly asymmetric kernel. Its broad shoulder, rounded base and
// curved crease keep it legible as an almond instead of a generic leaf.
// The SVG artwork uses a top-left origin; flip only the kernel drawing so the
// fallback keeps the same orientation as Icon Composer.
context.saveGState()
context.translateBy(x: 0, y: side)
context.scaleBy(x: 1, y: -1)
var tilt = CGAffineTransform(translationX: centre.x, y: centre.y)
    .rotated(by: -.pi / 10)
    .translatedBy(x: -centre.x, y: -centre.y)

let kernel = CGMutablePath()
kernel.move(to: CGPoint(x: 512, y: 266))
kernel.addCurve(
    to: CGPoint(x: 659, y: 587),
    control1: CGPoint(x: 624, y: 337),
    control2: CGPoint(x: 684, y: 464)
)
kernel.addCurve(
    to: CGPoint(x: 482, y: 767),
    control1: CGPoint(x: 634, y: 708),
    control2: CGPoint(x: 553, y: 782)
)
kernel.addCurve(
    to: CGPoint(x: 383, y: 531),
    control1: CGPoint(x: 405, y: 751),
    control2: CGPoint(x: 359, y: 652)
)
kernel.addCurve(
    to: CGPoint(x: 512, y: 266),
    control1: CGPoint(x: 407, y: 411),
    control2: CGPoint(x: 466, y: 305)
)
kernel.closeSubpath()
context.setFillColor(almond)
context.addPath(kernel.copy(using: &tilt)!)
context.fillPath()

let kernelCrease = CGMutablePath()
kernelCrease.move(to: CGPoint(x: 500, y: 333))
kernelCrease.addCurve(
    to: CGPoint(x: 493, y: 707),
    control1: CGPoint(x: 549, y: 447),
    control2: CGPoint(x: 550, y: 588)
)
context.setStrokeColor(crease)
context.setLineWidth(24)
context.setLineCap(.round)
context.addPath(kernelCrease.copy(using: &tilt)!)
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else { fatalError("could not render") }
let output = iconSet.appendingPathComponent("icon-1024.png")
let destination = CGImageDestinationCreateWithURL(
    output as CFURL, "public.png" as CFString, 1, nil
)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }

// Single-size asset catalogs have been the format since Xcode 14; the sizes
// below 1024 are generated at build time.
let contents = """
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(
    to: iconSet.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("wrote \(output.path)")
