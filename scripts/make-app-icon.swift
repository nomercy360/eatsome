#!/usr/bin/env swift
// Draws the app icon from the Wellie palette, so the mark is a script rather
// than a binary nobody can regenerate. Run after changing the colours:
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

let ink = rgb(5, 31, 68)
let blue = rgb(63, 138, 247)
let lime = rgb(196, 244, 52)
let plate = rgb(255, 255, 255)

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

// Background: brand blue deepening toward the navy the app uses for text.
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [blue, ink] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: []
)

// The plate.
let plateRadius = side * 0.30
let centre = CGPoint(x: side / 2, y: side / 2)
context.setFillColor(plate)
context.fillEllipse(in: CGRect(
    x: centre.x - plateRadius,
    y: centre.y - plateRadius,
    width: plateRadius * 2,
    height: plateRadius * 2
))

// A leaf on it: two arcs meeting at tip and stem, with a midrib. The app scores
// a Mediterranean diet, and this is the one mark that reads at 40 points.
let leafHeight = plateRadius * 1.32
let leafWidth = plateRadius * 0.78
let tip = CGPoint(x: centre.x, y: centre.y + leafHeight / 2)
let stem = CGPoint(x: centre.x, y: centre.y - leafHeight / 2)

// Tilted, and with the two sides curved differently: a symmetrical almond on a
// straight axis reads as an eye, not a leaf.
var tilt = CGAffineTransform(translationX: centre.x, y: centre.y)
    .rotated(by: -.pi / 9)
    .translatedBy(x: -centre.x, y: -centre.y)

let leaf = CGMutablePath()
leaf.move(to: tip)
leaf.addQuadCurve(
    to: stem,
    control: CGPoint(x: centre.x + leafWidth, y: centre.y - leafHeight * 0.10)
)
leaf.addQuadCurve(
    to: tip,
    control: CGPoint(x: centre.x - leafWidth * 0.82, y: centre.y + leafHeight * 0.02)
)
context.setFillColor(lime)
context.addPath(leaf.copy(using: &tilt)!)
context.fillPath()

// Midrib, in the background navy so it reads as a fold rather than a line. It
// follows the leaf's fuller side rather than splitting it down the middle.
let midrib = CGMutablePath()
midrib.move(to: CGPoint(x: stem.x, y: stem.y + leafHeight * 0.06))
midrib.addQuadCurve(
    to: CGPoint(x: tip.x, y: tip.y - leafHeight * 0.12),
    control: CGPoint(x: centre.x + leafWidth * 0.22, y: centre.y)
)
context.setStrokeColor(ink)
context.setLineWidth(side * 0.018)
context.setLineCap(.round)
context.addPath(midrib.copy(using: &tilt)!)
context.strokePath()

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
