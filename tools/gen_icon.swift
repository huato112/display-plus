#!/usr/bin/env swift
// Generates the DisplayPlus app icon set + a monochrome menu-bar template glyph.
// Dependency-free (AppKit). Run from the repo root:  swift tools/gen_icon.swift
import AppKit

let appIconDir = "DisplayPlus/Assets.xcassets/AppIcon.appiconset"
let scriptsDir = "scripts"
let menuBarDir = "DisplayPlus/Assets.xcassets/MenuBarIcon.imageset"
let iconSizes  = [16, 32, 64, 128, 256, 512, 1024]

let fm = FileManager.default

func writePNG(_ data: Data, to path: String) {
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Draws the "D+" monogram centered in a square of side `s`, in `color`.
/// `D` is heavy; `+` is smaller and raised toward the top-right.
func drawMonogram(side s: CGFloat, color: NSColor) {
    let d = NSAttributedString(string: "D", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.54, weight: .heavy),
        .foregroundColor: color,
    ])
    let plus = NSAttributedString(string: "+", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.30, weight: .heavy),
        .foregroundColor: color,
        .baselineOffset: s * 0.18,
    ])
    let combined = NSMutableAttributedString()
    combined.append(d)
    combined.append(plus)
    let textSize = combined.size()
    let origin = NSPoint(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2)
    combined.draw(at: origin)
}

/// Renders into a fresh bitmap context of the given pixel size and returns PNG data.
func renderPNG(size: Int, _ body: (CGFloat) -> Void) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))
    body(s)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// --- App icon: squircle + indigo→violet gradient + white D+ ---
func appIcon(size: Int) -> Data {
    renderPNG(size: size) { s in
        let rect = NSRect(x: 0, y: 0, width: s, height: s)
        let radius = s * 0.225
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()
        let start = NSColor(srgbRed: 0x5B/255.0, green: 0x5B/255.0, blue: 0xD6/255.0, alpha: 1)
        let end   = NSColor(srgbRed: 0x7C/255.0, green: 0x4D/255.0, blue: 0xFF/255.0, alpha: 1)
        NSGradient(starting: start, ending: end)!.draw(in: rect, angle: -45)
        drawMonogram(side: s, color: .white)
    }
}

// --- Menu-bar template: transparent bg + black D+ (tinted by the system) ---
func menuBarGlyph(size: Int) -> Data {
    renderPNG(size: size) { s in
        drawMonogram(side: s, color: .black)
    }
}

// Write app icons (AppIcon set + scripts/ mirror).
try? fm.createDirectory(atPath: appIconDir, withIntermediateDirectories: true)
for size in iconSizes {
    let data = appIcon(size: size)
    writePNG(data, to: "\(appIconDir)/icon_\(size).png")
    writePNG(data, to: "\(scriptsDir)/icon_\(size).png")
}

// Write menu-bar template imageset (1x = 18pt, 2x = 36px).
try? fm.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)
writePNG(menuBarGlyph(size: 18), to: "\(menuBarDir)/menubar_18.png")
writePNG(menuBarGlyph(size: 36), to: "\(menuBarDir)/menubar_36.png")
let contents = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "filename" : "menubar_18.png" },
    { "idiom" : "mac", "scale" : "2x", "filename" : "menubar_36.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""
writePNG(contents.data(using: .utf8)!, to: "\(menuBarDir)/Contents.json")
print("done")
