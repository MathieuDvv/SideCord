#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let canvasWidth = 960
let canvasHeight = 540
let frameCount = 56
let frameDelay = 0.1
let colorSpace = CGColorSpaceCreateDeviceRGB()

let outputDirectory = URL(fileURLWithPath: "docs/assets", isDirectory: true)
let gifURL = outputDirectory.appendingPathComponent("sidecord-demo.gif")
let posterURL = outputDirectory.appendingPathComponent("sidecord-demo-still.png")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xff) / 255,
            CGFloat((hex >> 8) & 0xff) / 255,
            CGFloat(hex & 0xff) / 255,
            alpha
        ]
    )!
}

func clamp(_ value: CGFloat, _ lower: CGFloat = 0, _ upper: CGFloat = 1) -> CGFloat {
    min(max(value, lower), upper)
}

func phase(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
    clamp((value - start) / (end - start))
}

func easeOut(_ value: CGFloat) -> CGFloat {
    1 - pow(1 - clamp(value), 3)
}

func easeInOut(_ value: CGFloat) -> CGFloat {
    let t = clamp(value)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

func fillRoundedRect(
    _ context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    fill: CGColor
) {
    context.addPath(roundedRect(rect, radius: radius))
    context.setFillColor(fill)
    context.fillPath()
}

func strokeRoundedRect(
    _ context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    stroke: CGColor,
    width: CGFloat
) {
    context.addPath(roundedRect(rect, radius: radius))
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.strokePath()
}

func drawText(
    _ context: CGContext,
    _ text: String,
    at point: CGPoint,
    size: CGFloat,
    weight: CTFontUIFontType = .system,
    fill: CGColor
) {
    let font = CTFontCreateUIFontForLanguage(weight, size, nil)
        ?? CTFontCreateWithName("SF Pro Display" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes)
    )
    context.textPosition = point
    CTLineDraw(line, context)
}

func drawGlow(_ context: CGContext, progress: CGFloat, strength: CGFloat) {
    guard strength > 0.001 else { return }
    let center = CGPoint(x: CGFloat(canvasWidth), y: CGFloat(canvasHeight) * 0.5)
    let radius = 75 + 185 * clamp(progress)
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0x8877ff, alpha: 0.90 * strength),
            color(0x6757eb, alpha: 0.42 * strength),
            color(0x5b7cfa, alpha: 0.10 * strength),
            color(0x5b7cfa, alpha: 0)
        ] as CFArray,
        locations: [0, 0.18, 0.52, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )

    context.saveGState()
    context.clip(to: CGRect(x: canvasWidth - 3, y: 64, width: 3, height: canvasHeight - 128))
    let core = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0x8f82ff, alpha: 0),
            color(0x8f82ff, alpha: 0.95 * strength),
            color(0x8f82ff, alpha: 0)
        ] as CFArray,
        locations: [0, 0.5, 1]
    )!
    context.drawLinearGradient(
        core,
        start: CGPoint(x: 0, y: 64),
        end: CGPoint(x: 0, y: canvasHeight - 64),
        options: []
    )
    context.restoreGState()
}

func drawCursor(_ context: CGContext, position: CGPoint, alpha: CGFloat) {
    guard alpha > 0.001 else { return }
    context.saveGState()
    context.translateBy(x: position.x, y: position.y)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 24))
    path.addLine(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: 17, y: 17))
    path.addLine(to: CGPoint(x: 9, y: 18))
    path.addLine(to: CGPoint(x: 14, y: 29))
    path.addLine(to: CGPoint(x: 9, y: 31))
    path.addLine(to: CGPoint(x: 4, y: 20))
    path.closeSubpath()
    context.addPath(path)
    context.setFillColor(color(0xffffff, alpha: 0.95 * alpha))
    context.fillPath()
    context.addPath(path)
    context.setStrokeColor(color(0x0c0d13, alpha: 0.9 * alpha))
    context.setLineWidth(1.5)
    context.strokePath()
    context.restoreGState()
}

func drawPanel(_ context: CGContext, openAmount: CGFloat) {
    guard openAmount > 0.001 else { return }
    let width: CGFloat = 350
    let height: CGFloat = 458
    let visibleX = CGFloat(canvasWidth) - width - 24
    let hiddenX = CGFloat(canvasWidth) + 28
    let x = hiddenX + (visibleX - hiddenX) * easeOut(openAmount)
    let y: CGFloat = 36
    let panelRect = CGRect(x: x, y: y, width: width, height: height)

    for index in stride(from: 4, through: 1, by: -1) {
        let spread = CGFloat(index) * 5
        fillRoundedRect(
            context,
            rect: panelRect.insetBy(dx: -spread, dy: -spread).offsetBy(dx: -2, dy: -5),
            radius: 27 + spread,
            fill: color(0x05050b, alpha: 0.035 * CGFloat(5 - index) * openAmount)
        )
    }

    fillRoundedRect(context, rect: panelRect, radius: 25, fill: color(0x151721, alpha: 0.97))
    strokeRoundedRect(
        context,
        rect: panelRect.insetBy(dx: 0.5, dy: 0.5),
        radius: 25,
        stroke: color(0xffffff, alpha: 0.15),
        width: 1
    )

    let railRect = CGRect(x: x + 12, y: y + 12, width: 56, height: height - 24)
    fillRoundedRect(context, rect: railRect, radius: 21, fill: color(0x0d0f17, alpha: 0.96))
    let railColors: [UInt32] = [0x6757eb, 0x36b5ff, 0xff6f91, 0x43d17a, 0xffa84b]
    for (index, railColor) in railColors.enumerated() {
        let cy = railRect.maxY - 41 - CGFloat(index) * 58
        context.setFillColor(color(railColor, alpha: index == 0 ? 1 : 0.74))
        context.fillEllipse(in: CGRect(x: railRect.midX - 17, y: cy - 17, width: 34, height: 34))
        if index == 0 {
            context.setStrokeColor(color(0xffffff, alpha: 0.8))
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: railRect.midX - 12, y: cy - 8, width: 24, height: 16))
        }
    }

    let contentX = railRect.maxX + 14
    let contentWidth = panelRect.maxX - contentX - 14
    drawText(
        context,
        "SideCord",
        at: CGPoint(x: contentX + 4, y: panelRect.maxY - 43),
        size: 18,
        weight: .emphasizedSystem,
        fill: color(0xffffff, alpha: 0.94)
    )
    drawText(
        context,
        "Discord, one edge away",
        at: CGPoint(x: contentX + 4, y: panelRect.maxY - 64),
        size: 10.5,
        fill: color(0xb9bdca, alpha: 0.8)
    )

    let pill = CGRect(x: panelRect.maxX - 115, y: panelRect.maxY - 48, width: 88, height: 30)
    fillRoundedRect(context, rect: pill, radius: 15, fill: color(0xffffff, alpha: 0.10))
    context.setStrokeColor(color(0xdedaff, alpha: 0.9))
    context.setLineWidth(1.4)
    context.strokeEllipse(in: CGRect(x: pill.minX + 15, y: pill.midY - 5, width: 10, height: 10))
    for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
        let cx = pill.minX + 20
        let cy = pill.midY
        context.move(to: CGPoint(x: cx + cos(angle) * 7, y: cy + sin(angle) * 7))
        context.addLine(to: CGPoint(x: cx + cos(angle) * 9, y: cy + sin(angle) * 9))
    }
    context.strokePath()
    fillRoundedRect(
        context,
        rect: CGRect(x: pill.maxX - 34, y: pill.midY - 7, width: 25, height: 14),
        radius: 7,
        fill: color(0x6757eb)
    )
    context.setFillColor(color(0xffffff))
    context.fillEllipse(in: CGRect(x: pill.maxX - 21, y: pill.midY - 5, width: 10, height: 10))

    let headerY = panelRect.maxY - 96
    fillRoundedRect(
        context,
        rect: CGRect(x: contentX + 4, y: headerY, width: contentWidth * 0.62, height: 11),
        radius: 5.5,
        fill: color(0xffffff, alpha: 0.18)
    )
    fillRoundedRect(
        context,
        rect: CGRect(x: contentX + 4, y: headerY - 19, width: contentWidth * 0.37, height: 7),
        radius: 3.5,
        fill: color(0xffffff, alpha: 0.09)
    )

    let messageColors: [UInt32] = [0x6757eb, 0x36b5ff, 0xff6f91, 0x43d17a]
    for index in 0 ..< 4 {
        let rowY = headerY - 65 - CGFloat(index) * 70
        context.setFillColor(color(messageColors[index], alpha: 0.8))
        context.fillEllipse(in: CGRect(x: contentX + 4, y: rowY, width: 28, height: 28))
        fillRoundedRect(
            context,
            rect: CGRect(x: contentX + 43, y: rowY + 17, width: contentWidth * (index == 1 ? 0.53 : 0.68), height: 7),
            radius: 3.5,
            fill: color(0xffffff, alpha: 0.16)
        )
        fillRoundedRect(
            context,
            rect: CGRect(x: contentX + 43, y: rowY + 3, width: contentWidth * (index == 2 ? 0.42 : 0.76), height: 7),
            radius: 3.5,
            fill: color(0xffffff, alpha: 0.08)
        )
    }

    let composer = CGRect(x: contentX + 4, y: y + 18, width: contentWidth - 8, height: 38)
    fillRoundedRect(context, rect: composer, radius: 13, fill: color(0xffffff, alpha: 0.08))
    fillRoundedRect(
        context,
        rect: CGRect(x: composer.minX + 15, y: composer.midY - 3, width: composer.width * 0.47, height: 6),
        radius: 3,
        fill: color(0xffffff, alpha: 0.12)
    )
}

func makeFrame(index: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let progress = CGFloat(index) / CGFloat(frameCount)
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x101322), color(0x17152a), color(0x090b12)] as CFArray,
        locations: [0, 0.53, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 0, y: canvasHeight),
        end: CGPoint(x: canvasWidth, y: 0),
        options: []
    )

    let orb = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x6757eb, alpha: 0.18), color(0x6757eb, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        orb,
        startCenter: CGPoint(x: 220, y: 430),
        startRadius: 0,
        endCenter: CGPoint(x: 220, y: 430),
        endRadius: 360,
        options: []
    )

    fillRoundedRect(
        context,
        rect: CGRect(x: 20, y: canvasHeight - 38, width: canvasWidth - 40, height: 24),
        radius: 12,
        fill: color(0xffffff, alpha: 0.055)
    )
    context.setFillColor(color(0xffffff, alpha: 0.7))
    for index in 0 ..< 3 {
        context.fillEllipse(in: CGRect(
            x: 37 + CGFloat(index) * 15,
            y: CGFloat(canvasHeight) - 30,
            width: 7,
            height: 7
        ))
    }

    let glowIn = easeOut(phase(progress, from: 0.12, to: 0.25))
    let glowOut = 1 - easeInOut(phase(progress, from: 0.42, to: 0.58))
    let breath = 0.72 + 0.22 * sin(progress * .pi * 10)
    let glowStrength = glowIn * glowOut * breath
    drawGlow(context, progress: glowIn, strength: glowStrength)

    let notificationAlpha = glowIn * (1 - phase(progress, from: 0.34, to: 0.47))
    let activityPill = CGRect(
        x: CGFloat(canvasWidth) - 205,
        y: CGFloat(canvasHeight) * 0.5 + 90,
        width: 160,
        height: 44
    )
    if notificationAlpha > 0.001 {
        fillRoundedRect(
            context,
            rect: activityPill,
            radius: 18,
            fill: color(0x191b27, alpha: 0.92 * notificationAlpha)
        )
        strokeRoundedRect(
            context,
            rect: activityPill.insetBy(dx: 0.5, dy: 0.5),
            radius: 18,
            stroke: color(0x9186ff, alpha: 0.55 * notificationAlpha),
            width: 1
        )
        context.setFillColor(color(0x8174ff, alpha: notificationAlpha))
        context.fillEllipse(in: CGRect(x: activityPill.minX + 14, y: activityPill.midY - 9, width: 18, height: 18))
        drawText(
            context,
            "Discord activity",
            at: CGPoint(x: activityPill.minX + 44, y: activityPill.midY - 5),
            size: 12,
            weight: .emphasizedSystem,
            fill: color(0xffffff, alpha: 0.9 * notificationAlpha)
        )
    }

    let openAmount: CGFloat
    if progress < 0.34 {
        openAmount = 0
    } else if progress < 0.52 {
        openAmount = easeInOut(phase(progress, from: 0.34, to: 0.52))
    } else if progress < 0.75 {
        openAmount = 1
    } else {
        openAmount = 1 - easeInOut(phase(progress, from: 0.75, to: 0.93))
    }
    drawPanel(context, openAmount: openAmount)

    let cursorTravel = easeInOut(phase(progress, from: 0.24, to: 0.42))
    let cursorRetreat = phase(progress, from: 0.70, to: 0.90)
    let cursor = CGPoint(
        x: 720 + 220 * cursorTravel - 90 * cursorRetreat,
        y: 210 + 50 * cursorTravel - 25 * cursorRetreat
    )
    let cursorAlpha = phase(progress, from: 0.20, to: 0.27)
        * (1 - phase(progress, from: 0.83, to: 0.94))
    drawCursor(context, position: cursor, alpha: cursorAlpha)

    return context.makeImage()!
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

guard let destination = CGImageDestinationCreateWithURL(
    gifURL as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    fatalError("Could not create GIF destination")
}
CGImageDestinationSetProperties(
    destination,
    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
)

var poster: CGImage?
for index in 0 ..< frameCount {
    autoreleasepool {
        let frame = makeFrame(index: index)
        if index == 27 { poster = frame }
        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay
            ]
        ]
        CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
    }
}
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not finalize GIF")
}

guard let poster,
      let posterDestination = CGImageDestinationCreateWithURL(
        posterURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
else {
    fatalError("Could not create poster destination")
}
CGImageDestinationAddImage(posterDestination, poster, nil)
guard CGImageDestinationFinalize(posterDestination) else {
    fatalError("Could not finalize poster")
}

let gifSize = try FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? NSNumber
print("Created \(gifURL.path) (\(gifSize?.intValue ?? 0) bytes)")
print("Created \(posterURL.path)")
