#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let canvasWidth = 960
let canvasHeight = 540
let frameCount = 72
let frameDelay = 0.075
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
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
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

func drawLine(
    _ context: CGContext,
    from start: CGPoint,
    to end: CGPoint,
    stroke: CGColor,
    width: CGFloat = 1
) {
    context.beginPath()
    context.move(to: start)
    context.addLine(to: end)
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.strokePath()
}

func drawAppKitImage(
    _ context: CGContext,
    image: NSImage,
    in rect: CGRect,
    alpha: CGFloat = 1
) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: alpha,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

func drawSystemSymbol(
    _ context: CGContext,
    name: String,
    center: CGPoint,
    pointSize: CGFloat,
    tint: CGColor,
    weight: NSFont.Weight = .medium
) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let nsTint = NSColor(cgColor: tint)
    else { return }
    let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [nsTint])
    let configured = base.withSymbolConfiguration(sizeConfiguration.applying(colorConfiguration)) ?? base
    let ratio = configured.size.width / max(configured.size.height, 1)
    let height = pointSize * 1.18
    let width = min(pointSize * 1.7, height * ratio)
    drawAppKitImage(
        context,
        image: configured,
        in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    )
}

func drawDesktop(_ context: CGContext) {
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x07194a), color(0x244dc0), color(0x8d4de8)] as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: canvasWidth, y: canvasHeight),
        options: []
    )

    let upperLight = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0xf4a8ff, alpha: 0.46), color(0xa873ff, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        upperLight,
        startCenter: CGPoint(x: 760, y: 560),
        startRadius: 0,
        endCenter: CGPoint(x: 760, y: 560),
        endRadius: 470,
        options: []
    )

    let distantWave = CGMutablePath()
    distantWave.move(to: CGPoint(x: -40, y: 420))
    distantWave.addCurve(
        to: CGPoint(x: 430, y: 330),
        control1: CGPoint(x: 130, y: 540),
        control2: CGPoint(x: 260, y: 270)
    )
    distantWave.addCurve(
        to: CGPoint(x: 1_020, y: 440),
        control1: CGPoint(x: 610, y: 410),
        control2: CGPoint(x: 790, y: 530)
    )
    distantWave.addLine(to: CGPoint(x: 1_020, y: 590))
    distantWave.addLine(to: CGPoint(x: -40, y: 590))
    distantWave.closeSubpath()
    context.addPath(distantWave)
    context.setFillColor(color(0xffb1ef, alpha: 0.15))
    context.fillPath()

    let middleWave = CGMutablePath()
    middleWave.move(to: CGPoint(x: -80, y: 40))
    middleWave.addCurve(
        to: CGPoint(x: 410, y: 250),
        control1: CGPoint(x: 90, y: 155),
        control2: CGPoint(x: 210, y: 310)
    )
    middleWave.addCurve(
        to: CGPoint(x: 1_020, y: 118),
        control1: CGPoint(x: 625, y: 178),
        control2: CGPoint(x: 770, y: 42)
    )
    middleWave.addLine(to: CGPoint(x: 1_020, y: -40))
    middleWave.addLine(to: CGPoint(x: -80, y: -40))
    middleWave.closeSubpath()
    context.addPath(middleWave)
    context.setFillColor(color(0x102b77, alpha: 0.74))
    context.fillPath()

    let foregroundWave = CGMutablePath()
    foregroundWave.move(to: CGPoint(x: -50, y: -20))
    foregroundWave.addCurve(
        to: CGPoint(x: 540, y: 170),
        control1: CGPoint(x: 175, y: 52),
        control2: CGPoint(x: 325, y: 230)
    )
    foregroundWave.addCurve(
        to: CGPoint(x: 1_010, y: 70),
        control1: CGPoint(x: 700, y: 118),
        control2: CGPoint(x: 840, y: 26)
    )
    foregroundWave.addLine(to: CGPoint(x: 1_010, y: -30))
    foregroundWave.closeSubpath()
    context.addPath(foregroundWave)
    context.setFillColor(color(0x07143a, alpha: 0.88))
    context.fillPath()

    let highlightRibbon = CGMutablePath()
    highlightRibbon.move(to: CGPoint(x: -30, y: 324))
    highlightRibbon.addCurve(
        to: CGPoint(x: 470, y: 282),
        control1: CGPoint(x: 160, y: 430),
        control2: CGPoint(x: 260, y: 214)
    )
    highlightRibbon.addCurve(
        to: CGPoint(x: 1_000, y: 355),
        control1: CGPoint(x: 640, y: 354),
        control2: CGPoint(x: 820, y: 418)
    )
    context.addPath(highlightRibbon)
    context.setStrokeColor(color(0xaebdff, alpha: 0.22))
    context.setLineWidth(4)
    context.strokePath()

    let vignette = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x040817, alpha: 0), color(0x040817, alpha: 0.34)] as CFArray,
        locations: [0.56, 1]
    )!
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: 500, y: 285),
        startRadius: 170,
        endCenter: CGPoint(x: 500, y: 285),
        endRadius: 650,
        options: [.drawsAfterEndLocation]
    )
}

func drawEdgeGlow(_ context: CGContext, strength: CGFloat) {
    guard strength > 0.001 else { return }
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0x8f87ff, alpha: 0.90 * strength),
            color(0x5865f2, alpha: 0.34 * strength),
            color(0x5865f2, alpha: 0)
        ] as CFArray,
        locations: [0, 0.25, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: canvasWidth, y: 270),
        startRadius: 0,
        endCenter: CGPoint(x: canvasWidth, y: 270),
        endRadius: 160,
        options: [.drawsAfterEndLocation]
    )
    let core = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0x8076ff, alpha: 0),
            color(0x9a92ff, alpha: 0.95 * strength),
            color(0x8076ff, alpha: 0)
        ] as CFArray,
        locations: [0, 0.5, 1]
    )!
    context.saveGState()
    context.clip(to: CGRect(x: 957, y: 80, width: 3, height: 380))
    context.drawLinearGradient(
        core,
        start: CGPoint(x: 0, y: 80),
        end: CGPoint(x: 0, y: 460),
        options: []
    )
    context.restoreGState()
}

func drawCursor(_ context: CGContext, position: CGPoint, alpha: CGFloat) {
    guard alpha > 0.001 else { return }
    let center = CGPoint(x: position.x + 8, y: position.y - 10)
    drawSystemSymbol(
        context,
        name: "cursorarrow",
        center: center,
        pointSize: 27,
        tint: color(0xffffff, alpha: 0.98 * alpha),
        weight: .bold
    )
    drawSystemSymbol(
        context,
        name: "cursorarrow",
        center: center,
        pointSize: 23,
        tint: color(0x111216, alpha: 0.98 * alpha),
        weight: .bold
    )
}

func drawAvatar(
    _ context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    colors: (UInt32, UInt32),
    initials: String,
    selected: Bool = false
) {
    let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    context.saveGState()
    context.addEllipse(in: rect)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(colors.0), color(colors.1)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    context.restoreGState()
    if selected {
        context.setStrokeColor(color(0xffffff, alpha: 0.92))
        context.setLineWidth(2)
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
    }
    let offset = CGFloat(initials.count) * radius * 0.29
    drawText(
        context,
        initials,
        at: CGPoint(x: center.x - offset, y: center.y - radius * 0.28),
        size: radius * 0.72,
        weight: .emphasizedSystem,
        fill: color(0xffffff, alpha: 0.95)
    )
}

func drawServerIcon(_ context: CGContext, center: CGPoint, index: Int, selected: Bool) {
    let palettes: [(UInt32, UInt32)] = [
        (0x5865f2, 0x8b5cf6), (0xff8a5b, 0xef476f), (0x43c6ac, 0x246bce),
        (0xffcf5c, 0x9c59d1), (0x5ac8fa, 0x315efb), (0xee6c9f, 0x8338ec)
    ]
    let palette = palettes[index % palettes.count]
    let rect = CGRect(x: center.x - 17, y: center.y - 17, width: 34, height: 34)
    context.saveGState()
    context.addPath(roundedRect(rect, radius: selected ? 11 : 17))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(palette.0), color(palette.1)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xffffff, alpha: 0.78))
    context.setLineWidth(2)
    if index % 3 == 0 {
        context.strokeEllipse(in: rect.insetBy(dx: 9, dy: 9))
        drawLine(
            context,
            from: CGPoint(x: center.x - 7, y: center.y),
            to: CGPoint(x: center.x + 7, y: center.y),
            stroke: color(0xffffff, alpha: 0.78),
            width: 2
        )
    } else if index % 3 == 1 {
        let diamond = CGMutablePath()
        diamond.move(to: CGPoint(x: center.x, y: center.y + 9))
        diamond.addLine(to: CGPoint(x: center.x + 9, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x, y: center.y - 9))
        diamond.addLine(to: CGPoint(x: center.x - 9, y: center.y))
        diamond.closeSubpath()
        context.addPath(diamond)
        context.strokePath()
    } else {
        fillRoundedRect(
            context,
            rect: CGRect(x: center.x - 9, y: center.y - 6, width: 18, height: 12),
            radius: 4,
            fill: color(0xffffff, alpha: 0.82)
        )
        context.setFillColor(color(palette.1))
        context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 2, width: 3, height: 3))
        context.fillEllipse(in: CGRect(x: center.x + 2, y: center.y - 2, width: 3, height: 3))
    }
}

func drawRail(_ context: CGContext, panelX: CGFloat, y: CGFloat, height: CGFloat, amount: CGFloat) {
    let rail = CGRect(x: panelX - 68, y: y + 9, width: 56, height: height - 18)
    for index in stride(from: 4, through: 1, by: -1) {
        let spread = CGFloat(index) * 4
        fillRoundedRect(
            context,
            rect: rail.insetBy(dx: -spread, dy: -spread),
            radius: 23 + spread,
            fill: color(0x000000, alpha: 0.025 * CGFloat(5 - index) * amount)
        )
    }
    fillRoundedRect(context, rect: rail, radius: 22, fill: color(0x090b10, alpha: 0.98))
    strokeRoundedRect(
        context,
        rect: rail.insetBy(dx: 0.5, dy: 0.5),
        radius: 22,
        stroke: color(0xffffff, alpha: 0.13),
        width: 1
    )

    let homeCenter = CGPoint(x: rail.midX, y: rail.maxY - 31)
    fillRoundedRect(
        context,
        rect: CGRect(x: homeCenter.x - 18, y: homeCenter.y - 18, width: 36, height: 36),
        radius: 14,
        fill: color(0x232630)
    )
    fillRoundedRect(
        context,
        rect: CGRect(x: homeCenter.x - 9, y: homeCenter.y - 6, width: 18, height: 12),
        radius: 5,
        fill: color(0xffffff, alpha: 0.88)
    )
    context.setFillColor(color(0xffffff, alpha: 0.88))
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: homeCenter.x + 3, y: homeCenter.y - 4))
    tail.addLine(to: CGPoint(x: homeCenter.x + 9, y: homeCenter.y - 10))
    tail.addLine(to: CGPoint(x: homeCenter.x + 7, y: homeCenter.y - 2))
    tail.closeSubpath()
    context.addPath(tail)
    context.fillPath()
    drawLine(
        context,
        from: CGPoint(x: rail.minX + 13, y: rail.maxY - 60),
        to: CGPoint(x: rail.maxX - 13, y: rail.maxY - 60),
        stroke: color(0xffffff, alpha: 0.13)
    )

    let centers = [rail.maxY - 86, rail.maxY - 128, rail.maxY - 170, rail.maxY - 212,
                   rail.maxY - 254, rail.maxY - 296, rail.maxY - 338]
    for (index, centerY) in centers.enumerated() {
        if index == 2 {
            fillRoundedRect(
                context,
                rect: CGRect(x: rail.minX + 2, y: centerY - 13, width: 3, height: 26),
                radius: 2,
                fill: color(0x8a7dff)
            )
        }
        drawServerIcon(
            context,
            center: CGPoint(x: rail.midX, y: centerY),
            index: index,
            selected: index == 2
        )
    }

    let addCenter = CGPoint(x: rail.midX, y: rail.minY + 27)
    fillRoundedRect(
        context,
        rect: CGRect(x: addCenter.x - 17, y: addCenter.y - 17, width: 34, height: 34),
        radius: 17,
        fill: color(0x181b23)
    )
    drawText(
        context,
        "+",
        at: CGPoint(x: addCenter.x - 6, y: addCenter.y - 7),
        size: 20,
        fill: color(0x7c8cff)
    )
}

enum ToolbarIcon {
    case sidebar
    case grid
    case pin
    case maximize
    case more
    case settings
    case chevron
}

func drawToolbarIcon(
    _ context: CGContext,
    icon: ToolbarIcon,
    center: CGPoint,
    highlighted: Bool = false
) {
    if highlighted {
        fillRoundedRect(
            context,
            rect: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24),
            radius: 8,
            fill: color(0x5865f2, alpha: 0.42)
        )
    }
    let ink = color(highlighted ? 0xffffff : 0xd8dae1, alpha: 0.94)
    switch icon {
    case .sidebar:
        drawSystemSymbol(context, name: "sidebar.left", center: center, pointSize: 13, tint: ink)
    case .grid:
        drawSystemSymbol(context, name: "square.grid.2x2.fill", center: center, pointSize: 13, tint: ink)
    case .pin:
        drawSystemSymbol(context, name: "pin", center: center, pointSize: 13, tint: ink)
    case .maximize:
        drawSystemSymbol(
            context,
            name: "arrow.up.left.and.arrow.down.right",
            center: center,
            pointSize: 13,
            tint: ink
        )
    case .more:
        drawSystemSymbol(
            context,
            name: "ellipsis",
            center: CGPoint(x: center.x - 3, y: center.y),
            pointSize: 13,
            tint: ink
        )
        drawSystemSymbol(
            context,
            name: "chevron.down",
            center: CGPoint(x: center.x + 9, y: center.y - 0.5),
            pointSize: 7,
            tint: color(0x8a7dff)
        )
    case .settings:
        drawSystemSymbol(context, name: "gearshape", center: center, pointSize: 13, tint: ink)
    case .chevron:
        drawSystemSymbol(context, name: "chevron.right", center: center, pointSize: 13, tint: ink)
    }
}

enum ChannelIcon {
    case threads
    case bell
    case pin
    case people
}

func drawChannelIcon(_ context: CGContext, icon: ChannelIcon, center: CGPoint) {
    let ink = color(0xb5bac1, alpha: 0.92)
    switch icon {
    case .threads:
        drawSystemSymbol(context, name: "line.3.horizontal.decrease", center: center, pointSize: 14, tint: ink)
    case .bell:
        drawSystemSymbol(context, name: "bell.fill", center: center, pointSize: 14, tint: ink)
    case .pin:
        drawSystemSymbol(context, name: "pin.fill", center: center, pointSize: 14, tint: ink)
        context.setFillColor(color(0xed4245))
        context.fillEllipse(in: CGRect(x: center.x + 5, y: center.y - 7, width: 6, height: 6))
    case .people:
        drawSystemSymbol(context, name: "person.2.fill", center: center, pointSize: 14, tint: ink)
    }
}

func drawComposerIcons(_ context: CGContext, composer: CGRect) {
    let ink = color(0xaeb3bc, alpha: 0.92)

    let giftCenter = CGPoint(x: composer.maxX - 153, y: composer.midY)
    drawSystemSymbol(context, name: "gift.fill", center: giftCenter, pointSize: 13, tint: ink)

    let gifCenter = CGPoint(x: composer.maxX - 119, y: composer.midY)
    fillRoundedRect(
        context,
        rect: CGRect(x: gifCenter.x - 13, y: gifCenter.y - 8, width: 26, height: 16),
        radius: 3,
        fill: ink
    )
    drawText(
        context,
        "GIF",
        at: CGPoint(x: gifCenter.x - 10, y: gifCenter.y - 4),
        size: 8,
        weight: .emphasizedSystem,
        fill: color(0x17191f)
    )

    let sticker = CGRect(x: composer.maxX - 91, y: composer.midY - 9, width: 18, height: 18)
    drawSystemSymbol(context, name: "photo.on.rectangle.angled", center: CGPoint(x: sticker.midX, y: sticker.midY), pointSize: 13, tint: ink)

    let smileCenter = CGPoint(x: composer.maxX - 49, y: composer.midY)
    drawSystemSymbol(context, name: "face.smiling.fill", center: smileCenter, pointSize: 13, tint: ink)

    let sparkleCenter = CGPoint(x: composer.maxX - 17, y: composer.midY)
    drawSystemSymbol(context, name: "sparkles", center: sparkleCenter, pointSize: 13, tint: ink)
}

func drawMessage(
    _ context: CGContext,
    origin: CGPoint,
    name: String,
    time: String,
    lines: [String],
    colors: (UInt32, UInt32),
    initials: String,
    nameColor: UInt32 = 0xf2f3f5
) {
    drawAvatar(
        context,
        center: CGPoint(x: origin.x + 14, y: origin.y + 18),
        radius: 14,
        colors: colors,
        initials: initials
    )
    drawText(
        context,
        name,
        at: CGPoint(x: origin.x + 38, y: origin.y + 25),
        size: 12,
        weight: .emphasizedSystem,
        fill: color(nameColor)
    )
    drawText(
        context,
        time,
        at: CGPoint(x: origin.x + 38 + CGFloat(name.count) * 7.0, y: origin.y + 25),
        size: 8.5,
        fill: color(0x949ba4)
    )
    for (index, line) in lines.enumerated() {
        drawText(
            context,
            line,
            at: CGPoint(x: origin.x + 38, y: origin.y + 8 - CGFloat(index) * 15),
            size: 11.5,
            fill: color(0xdbdee1)
        )
    }
}

func drawAttachment(_ context: CGContext, rect: CGRect) {
    context.saveGState()
    context.addPath(roundedRect(rect, radius: 10))
    context.clip()
    let sky = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x8198ff), color(0xc682e8), color(0xffba7a)] as CFArray,
        locations: [0, 0.52, 1]
    )!
    context.drawLinearGradient(
        sky,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    let back = CGMutablePath()
    back.move(to: CGPoint(x: rect.minX, y: rect.minY + 8))
    back.addLine(to: CGPoint(x: rect.minX + 48, y: rect.minY + 43))
    back.addLine(to: CGPoint(x: rect.minX + 93, y: rect.minY + 19))
    back.addLine(to: CGPoint(x: rect.minX + 145, y: rect.minY + 54))
    back.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 21))
    back.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    back.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    back.closeSubpath()
    context.addPath(back)
    context.setFillColor(color(0x313558, alpha: 0.88))
    context.fillPath()
    context.setFillColor(color(0xfff4cf, alpha: 0.92))
    context.fillEllipse(in: CGRect(x: rect.maxX - 37, y: rect.maxY - 34, width: 18, height: 18))
    context.restoreGState()
    strokeRoundedRect(
        context,
        rect: rect.insetBy(dx: 0.5, dy: 0.5),
        radius: 10,
        stroke: color(0xffffff, alpha: 0.14),
        width: 1
    )
}

func drawPanel(_ context: CGContext, openAmount: CGFloat, hoverAmount: CGFloat) {
    guard openAmount > 0.001 else { return }
    let width: CGFloat = 482
    let height: CGFloat = 500
    let visibleX: CGFloat = 458
    let hiddenX = CGFloat(canvasWidth) + 42
    let x = hiddenX + (visibleX - hiddenX) * easeOut(openAmount)
    let y: CGFloat = 20
    let panel = CGRect(x: x, y: y, width: width, height: height)

    for index in stride(from: 4, through: 1, by: -1) {
        let spread = CGFloat(index) * 4
        fillRoundedRect(
            context,
            rect: panel.insetBy(dx: -spread, dy: -spread).offsetBy(dx: -3, dy: -3),
            radius: 23 + spread,
            fill: color(0x000000, alpha: 0.032 * CGFloat(5 - index) * openAmount)
        )
    }
    strokeRoundedRect(
        context,
        rect: panel.insetBy(dx: -3, dy: -3),
        radius: 25,
        stroke: color(0x5967ff, alpha: 0.24 * openAmount),
        width: 3
    )

    context.saveGState()
    context.addPath(roundedRect(panel, radius: 22))
    context.clip()
    context.setFillColor(color(0x050608, alpha: 0.99))
    context.fill(panel)

    let accountBar = CGRect(x: x, y: panel.maxY - 46, width: width, height: 46)
    context.setFillColor(color(0x07080b))
    context.fill(accountBar)
    drawAvatar(
        context,
        center: CGPoint(x: x + 155, y: accountBar.midY),
        radius: 10,
        colors: (0xff9d66, 0x8957e5),
        initials: "N"
    )
    drawText(
        context,
        "Nova Vale",
        at: CGPoint(x: x + 171, y: accountBar.midY - 5),
        size: 13.5,
        weight: .emphasizedSystem,
        fill: color(0xf4f5f6)
    )

    let channelBar = CGRect(x: x, y: panel.maxY - 90, width: width, height: 44)
    context.setFillColor(color(0x090a0e))
    context.fill(channelBar)
    drawText(
        context,
        "#",
        at: CGPoint(x: x + 19, y: channelBar.midY - 9),
        size: 23,
        weight: .emphasizedSystem,
        fill: color(0x949ba4)
    )
    drawText(
        context,
        "night-shift",
        at: CGPoint(x: x + 44, y: channelBar.midY - 6),
        size: 15,
        weight: .emphasizedSystem,
        fill: color(0xf2f3f5)
    )
    drawChannelIcon(context, icon: .threads, center: CGPoint(x: panel.maxX - 126, y: channelBar.midY))
    drawChannelIcon(context, icon: .bell, center: CGPoint(x: panel.maxX - 94, y: channelBar.midY))
    drawChannelIcon(context, icon: .pin, center: CGPoint(x: panel.maxX - 62, y: channelBar.midY))
    drawChannelIcon(context, icon: .people, center: CGPoint(x: panel.maxX - 30, y: channelBar.midY))
    drawLine(
        context,
        from: CGPoint(x: x, y: channelBar.minY),
        to: CGPoint(x: panel.maxX, y: channelBar.minY),
        stroke: color(0xffffff, alpha: 0.12)
    )

    let contentMinY = y + 62
    let contentMaxY = channelBar.minY
    context.saveGState()
    context.clip(to: CGRect(x: x, y: contentMinY, width: width, height: contentMaxY - contentMinY))

    let dividerY = contentMaxY - 32
    drawLine(
        context,
        from: CGPoint(x: x + 25, y: dividerY),
        to: CGPoint(x: panel.maxX - 25, y: dividerY),
        stroke: color(0xffffff, alpha: 0.11)
    )
    fillRoundedRect(
        context,
        rect: CGRect(x: panel.midX - 42, y: dividerY - 9, width: 84, height: 18),
        radius: 9,
        fill: color(0x050608)
    )
    drawText(
        context,
        "TODAY",
        at: CGPoint(x: panel.midX - 17, y: dividerY - 3),
        size: 8,
        weight: .emphasizedSystem,
        fill: color(0x949ba4)
    )

    drawMessage(
        context,
        origin: CGPoint(x: x + 20, y: dividerY - 56),
        name: "Luma",
        time: "10:42",
        lines: ["The new build feels incredibly smooth."],
        colors: (0xff7a8a, 0x8b5cf6),
        initials: "L"
    )
    drawAttachment(
        context,
        rect: CGRect(x: x + 72, y: dividerY - 152, width: 170, height: 73)
    )
    drawMessage(
        context,
        origin: CGPoint(x: x + 20, y: dividerY - 198),
        name: "Orion",
        time: "10:43",
        lines: ["That edge reveal is exactly what I wanted.", "It stays out of the way until I need it."],
        colors: (0x43c6ac, 0x246bce),
        initials: "O",
        nameColor: 0x83d7ff
    )
    context.restoreGState()

    let composer = CGRect(x: x + 14, y: y + 12, width: width - 28, height: 42)
    fillRoundedRect(context, rect: composer, radius: 12, fill: color(0x17191f))
    drawText(
        context,
        "+",
        at: CGPoint(x: composer.minX + 13, y: composer.midY - 8),
        size: 22,
        fill: color(0xb5bac1)
    )
    drawText(
        context,
        "Message #night-shift",
        at: CGPoint(x: composer.minX + 44, y: composer.midY - 5),
        size: 11.5,
        fill: color(0x777d87)
    )
    drawComposerIcons(context, composer: composer)
    context.restoreGState()

    strokeRoundedRect(
        context,
        rect: panel.insetBy(dx: 0.5, dy: 0.5),
        radius: 22,
        stroke: color(0xffffff, alpha: 0.18),
        width: 1
    )

    let pill = CGRect(x: panel.maxX - 218, y: panel.maxY - 56, width: 208, height: 38)
    fillRoundedRect(context, rect: pill, radius: 19, fill: color(0x171920, alpha: 0.97))
    strokeRoundedRect(
        context,
        rect: pill.insetBy(dx: 0.5, dy: 0.5),
        radius: 19,
        stroke: color(0xffffff, alpha: 0.14),
        width: 1
    )
    let toolbarIcons: [ToolbarIcon] = [.sidebar, .grid, .pin, .maximize, .more, .settings, .chevron]
    let toolbarX: [CGFloat] = [18, 45, 72, 99, 128, 162, 190]
    for (index, icon) in toolbarIcons.enumerated() {
        drawToolbarIcon(
            context,
            icon: icon,
            center: CGPoint(x: pill.minX + toolbarX[index], y: pill.midY),
            highlighted: index == 2 && hoverAmount > 0.45
        )
    }

    drawRail(context, panelX: x, y: y, height: height, amount: openAmount)
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

    let canvas = CGRect(x: 2, y: 2, width: CGFloat(canvasWidth) - 4, height: CGFloat(canvasHeight) - 4)
    context.clear(
        CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))
    )
    context.saveGState()
    context.addPath(roundedRect(canvas, radius: 24))
    context.clip()

    let progress = CGFloat(index) / CGFloat(frameCount - 1)
    drawDesktop(context)

    let glowIn = easeOut(phase(progress, from: 0.05, to: 0.17))
    let glowOut = 1 - easeInOut(phase(progress, from: 0.29, to: 0.43))
    let breath = 0.82 + 0.18 * sin(progress * .pi * 12)
    drawEdgeGlow(context, strength: glowIn * glowOut * breath)

    let openAmount: CGFloat
    if progress < 0.25 {
        openAmount = 0
    } else if progress < 0.40 {
        openAmount = easeInOut(phase(progress, from: 0.25, to: 0.40))
    } else if progress < 0.79 {
        openAmount = 1
    } else {
        openAmount = 1 - easeInOut(phase(progress, from: 0.79, to: 0.94))
    }
    let hoverAmount = sin(.pi * phase(progress, from: 0.50, to: 0.70))
    drawPanel(context, openAmount: openAmount, hoverAmount: hoverAmount)

    let cursorTravel = easeInOut(phase(progress, from: 0.13, to: 0.28))
    let cursorToolbar = easeInOut(phase(progress, from: 0.43, to: 0.58))
    let cursorRetreat = easeInOut(phase(progress, from: 0.73, to: 0.88))
    let edgePosition = CGPoint(x: 952, y: 267)
    let toolbarPosition = CGPoint(x: 794, y: 483)
    var cursor = CGPoint(
        x: 770 + (edgePosition.x - 770) * cursorTravel,
        y: 222 + (edgePosition.y - 222) * cursorTravel
    )
    cursor.x += (toolbarPosition.x - edgePosition.x) * cursorToolbar
    cursor.y += (toolbarPosition.y - edgePosition.y) * cursorToolbar
    cursor.x += (818 - toolbarPosition.x) * cursorRetreat
    cursor.y += (420 - toolbarPosition.y) * cursorRetreat
    let cursorAlpha = phase(progress, from: 0.10, to: 0.16)
        * (1 - phase(progress, from: 0.86, to: 0.93))
    drawCursor(context, position: cursor, alpha: cursorAlpha)

    strokeRoundedRect(
        context,
        rect: canvas.insetBy(dx: 0.5, dy: 0.5),
        radius: 24,
        stroke: color(0xffffff, alpha: 0.16),
        width: 1
    )
    context.restoreGState()

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
        if index == 42 { poster = frame }
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
