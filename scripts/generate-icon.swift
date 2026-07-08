#!/usr/bin/env swift
//
// generate-icon.swift — renders the nanobar app icon as PNGs.
//
// Run it from the repo root on your Mac:
//
//   swift scripts/generate-icon.swift
//
// It writes all ten sizes macOS wants straight into
// nanobar/Assets.xcassets/AppIcon.appiconset/, whose Contents.json already
// references these filenames — so after running it, just build in Xcode.
//
// The design is a custom take on the dock.rectangle symbol we use in the
// menu bar: the "dock" part becomes a white capsule bar holding three
// window chips in the classic traffic-light colors.

import AppKit

// MARK: - Design constants
//
// Everything is drawn in a single 1024x1024 "design space". Each output
// size is the same drawing scaled down, so if you want to tweak the look
// you only edit the numbers here once.

let canvas: CGFloat = 1024

// macOS app icons don't fill the whole canvas: Apple's template is an
// ~824pt rounded square centered in 1024, with a transparent margin
// around it (that margin is what makes icons sit nicely in the Dock).
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircleCornerRadius: CGFloat = 185

// Background gradient, light at the top -> deep blue at the bottom.
let gradientTop = NSColor(calibratedRed: 0.39, green: 0.63, blue: 0.97, alpha: 1)
let gradientBottom = NSColor(calibratedRed: 0.11, green: 0.31, blue: 0.75, alpha: 1)

// The window chips inside the bar.
let chipSize: CGFloat = 144
let chipCornerRadius: CGFloat = 32
let chipGap: CGFloat = 32
let chipColors: [NSColor] = [
    NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1), // red
    NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1), // yellow
    NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: 1), // green
]

let barPadding = 1.25 * chipGap
let w = chipSize * 3 + chipGap * 2 + barPadding * 2
let h = chipSize + chipGap * 2
let x = (1024 - w) / 2
let barCornerRadius = (2 * barPadding + chipSize) / chipSize * chipCornerRadius

// The bar: a white capsule in the lower third, echoing the dock in the
// dock.rectangle menu-bar symbol (and nanobar's own taskbar panel).
let barRect = CGRect(x: x, y: 192, width: w, height: h)

// MARK: - Drawing
//
// AppKit's coordinate system has the origin at the BOTTOM-left, so y grows
// upward — the opposite of what you might expect from web/iOS drawing.

func drawIcon(in ctx: NSGraphicsContext) {
    let squircle = NSBezierPath(
        roundedRect: squircleRect,
        xRadius: squircleCornerRadius,
        yRadius: squircleCornerRadius
    )

    // 1. Fill the squircle once in a flat color purely to cast a soft drop
    //    shadow (Apple's own icons bake a shadow into the artwork). Shadows
    //    apply to whatever is drawn while an NSShadow is "set", so we wrap
    //    this in save/restore to keep the shadow from leaking onto later
    //    drawing.
    ctx.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -12) // negative y = downward here
    shadow.shadowBlurRadius = 24
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    gradientBottom.setFill()
    squircle.fill()
    ctx.restoreGraphicsState()

    // 2. The gradient background. angle: 90 means the gradient runs from
    //    the starting color at the bottom to the ending color at the top.
    NSGradient(starting: gradientBottom, ending: gradientTop)?
        .draw(in: squircle, angle: 90)

    // 3. The white capsule bar, with its own softer shadow so it lifts off
    //    the background a little.
    let bar = NSBezierPath(
        roundedRect: barRect,
        xRadius: barCornerRadius,
        yRadius: barCornerRadius,
    )
    ctx.saveGraphicsState()
    let barShadow = NSShadow()
    barShadow.shadowOffset = NSSize(width: 0, height: -8)
    barShadow.shadowBlurRadius = 18
    barShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    barShadow.set()
    NSColor.white.setFill()
    bar.fill()
    ctx.restoreGraphicsState()

    // 4. Three window chips, centered as a group inside the bar.
    let groupWidth = chipSize * 3 + chipGap * 2
    var chipX = barRect.midX - groupWidth / 2
    let chipY = barRect.midY - chipSize / 2
    for color in chipColors {
        let chip = NSBezierPath(
            roundedRect: CGRect(x: chipX, y: chipY, width: chipSize, height: chipSize),
            xRadius: chipCornerRadius,
            yRadius: chipCornerRadius
        )
        color.setFill()
        chip.fill()
        chipX += chipSize + chipGap
    }
}

// MARK: - Rendering to a PNG at a given pixel size

func renderPNG(pixels: Int) -> Data {
    // NSBitmapImageRep is an offscreen pixel buffer we can point AppKit's
    // drawing machinery at — like an invisible canvas.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4, // RGBA
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    // Setting size == pixel size keeps the PNG at 72dpi so its point size
    // and pixel size match (otherwise Xcode complains about scale).
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    // Scale the context so our 1024-space drawing fills this output size.
    let scale = CGFloat(pixels) / canvas
    ctx.cgContext.scaleBy(x: scale, y: scale)

    drawIcon(in: ctx)

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Main

// The ten slots a macOS AppIcon set wants: 16/32/128/256/512 points, each
// at 1x and 2x. (A "@2x" file has twice the pixels of its point size.)
let slots: [(filename: String, pixels: Int)] = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024),
]

// Output directory: first command-line argument if given, otherwise the
// appiconset relative to wherever you ran the script from.
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "nanobar/Assets.xcassets/AppIcon.appiconset"
let outputDir = URL(fileURLWithPath: outputPath, isDirectory: true)

guard FileManager.default.fileExists(atPath: outputDir.path) else {
    print("error: \(outputDir.path) does not exist — run this from the repo root,")
    print("or pass an output directory: swift scripts/generate-icon.swift <dir>")
    exit(1)
}

for slot in slots {
    let url = outputDir.appendingPathComponent(slot.filename)
    try renderPNG(pixels: slot.pixels).write(to: url)
    print("wrote \(url.path) (\(slot.pixels)x\(slot.pixels))")
}
print("done — build in Xcode and the new icon should show up.")
