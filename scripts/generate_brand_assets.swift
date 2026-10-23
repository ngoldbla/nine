#!/usr/bin/env swift
// generate_brand_assets.swift — deterministic brand assets for Nine.
//
// Renders the "App Icon & Top Shelf Image" brand asset (layered parallax icon
// stacks, Top Shelf banners) plus a Launch Image into nine/Assets.xcassets,
// and — because Nine is universal — its flat iOS/macOS/watchOS app icons and
// alternate iOS icons. Pure CoreGraphics; run on macOS:
//
//   swift scripts/generate_brand_assets.swift            # every app in `specs`
//   swift scripts/generate_brand_assets.swift nine       # one app
//
// This held all five Couch Suite apps' specs until the four tvOS-only siblings
// moved to their own repositories, each taking its own spec with it.
//
// Art direction ("pixels under glass"): Back = deep color field, Field = faint
// pixel grid, Board = the glyph's accent tiles, Spark = its secondary tile on
// top. Glyphs are the string maps below — '#' accent, '+' secondary, '.' empty.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    func alpha(_ a: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

/// An alternate iOS app icon (PRD-16). Only the palette moves — the mark is the
/// app's, and an alternate icon that changed it would be a different app on the
/// Home Screen.
struct IconVariant {
    let name: String        // the asset-catalog set name, e.g. "AppIcon-Ember"
    let backTop: RGB
    let backBottom: RGB
    let grid: RGB
    let accent: RGB
    let secondary: RGB
}

struct AppSpec {
    let folder: String
    let backTop: RGB    // gradient start (top)
    let backBottom: RGB // gradient end (bottom)
    let grid: RGB       // middle-layer pixel grid
    let accent: RGB     // glyph '#'
    let secondary: RGB  // glyph '+'
    // Apps that also ship an iOS build get a flat square AppIcon.appiconset
    // (single-size 1024, opaque RGB — the App Store rejects alpha).
    var iosIcon: Bool = false
    // Apps that also ship a macOS build get a margined, rounded-rect
    // AppIcon-macOS.appiconset (PRD-4 §1): the mac idiom expects the icon to
    // carry its own HIG margin + rounded shape (transparency is fine here,
    // unlike iOS).
    var macIcon: Bool = false
    // Apps that also ship a watchOS build get AppIcon-watchOS.appiconset
    // (PRD-6). Same single-1024 shape as iOS and opaque for the same reason,
    // but a distinct set because the `watchos` platform key is what makes
    // actool derive the round complication/Home-Screen sizes; an iOS set
    // handed to a watch target validates against the wrong idiom.
    var watchIcon: Bool = false
    // Alternate iOS icons (PRD-16). iOS only: a tvOS icon is a layered image
    // stack and macOS has no `setAlternateIconName` outside Catalyst.
    var altIcons: [IconVariant] = []
    let glyph: [String]
    // Corner radius of each glyph tile as a fraction of its shorter side, and
    // how much larger the '+' tiles draw than their cells — the same 0.16 and
    // 1.12 as the Spark group in `nine/Nine.icon`, so the tvOS tile, the Top
    // Shelf and the alternates carry the mark the Icon Composer document does.
    var tileCorner: CGFloat = 0
    var sparkScale: CGFloat = 1
}

let specs: [AppSpec] = [
    AppSpec(
        folder: "nine",
        backTop: RGB(r: 0.030, g: 0.030, b: 0.090), backBottom: RGB(r: 0.080, g: 0.070, b: 0.180),
        grid: RGB(r: 0.76, g: 0.70, b: 0.94),
        accent: RGB(r: 0.76, g: 0.70, b: 0.94), secondary: RGB(r: 1.0, g: 0.45, b: 0.38),
        // No flat iOS / macOS / watchOS icon: those platforms take the Icon
        // Composer document `nine/Nine.icon`. A leftover AppIcon.appiconset is
        // not inert — INCLUDE_ALL_APPICON_ASSETS ships it as a fourth alternate.
        // PRD-16. Grounds lifted from the three new themes and brightened: an
        // icon is seen at 60 pt against an arbitrary wallpaper, not full-screen
        // behind glass, so the board's backgrounds read as black squares at
        // icon size. The secondary is each theme's companion accent, which is
        // what keeps the three tellable apart in a Home Screen folder.
        altIcons: [
            IconVariant(
                name: "AppIcon-Ember",
                backTop: RGB(r: 0.14, g: 0.05, b: 0.03), backBottom: RGB(r: 0.34, g: 0.13, b: 0.06),
                grid: RGB(r: 0.98, g: 0.86, b: 0.78),
                accent: RGB(r: 0.98, g: 0.86, b: 0.78), secondary: RGB(r: 1.00, g: 0.56, b: 0.20)),
            IconVariant(
                name: "AppIcon-Tide",
                backTop: RGB(r: 0.02, g: 0.12, b: 0.14), backBottom: RGB(r: 0.05, g: 0.28, b: 0.31),
                grid: RGB(r: 0.76, g: 0.93, b: 0.94),
                accent: RGB(r: 0.76, g: 0.93, b: 0.94), secondary: RGB(r: 0.15, g: 0.80, b: 0.76)),
            IconVariant(
                name: "AppIcon-Mono",
                backTop: RGB(r: 0.11, g: 0.11, b: 0.12), backBottom: RGB(r: 0.26, g: 0.26, b: 0.28),
                grid: RGB(r: 0.88, g: 0.88, b: 0.89),
                accent: RGB(r: 0.88, g: 0.88, b: 0.89), secondary: RGB(r: 0.55, g: 0.55, b: 0.58)),
        ],
        // 2-cell tiles with 2-cell gaps (1.2 shipped 3): the gap the Icon
        // Composer document settled on, so the glass has surface to show.
        glyph: [
            "##..##..##",
            "##..##..##",
            "..........",
            "..........",
            "##..++..##",
            "##..++..##",
            "..........",
            "..........",
            "##..##..##",
            "##..##..##",
        ],
        tileCorner: 0.16,
        sparkScale: 1.12),
]

// MARK: - Rendering

func context(w: Int, h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ ctx: CGContext, to url: URL) {
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed: \(url.path)") }
}

/// Back layer: vertical gradient, fully opaque (Apple requires an opaque bottom layer).
func renderBack(_ s: AppSpec, w: Int, h: Int) -> CGContext {
    let ctx = context(w: w, h: h)
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
    return ctx
}

/// Field layer: faint pixel grid of small squares, transparent elsewhere.
func renderField(_ s: AppSpec, w: Int, h: Int) -> CGContext {
    let ctx = context(w: w, h: h)
    let cell = max(8, min(w, h) / 24)          // grid pitch scales with asset size
    let dot = max(1, cell / 8)                 // small square at each grid point
    ctx.setFillColor(s.grid.alpha(0.10))
    var y = cell / 2
    while y < h {
        var x = cell / 2
        while x < w {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    return ctx
}

/// A glyph layer: only the tiles drawn with `chars`, transparent elsewhere.
/// The tvOS stack splits the glyph so the '+' Spark sits on its own, topmost
/// layer and moves furthest under focus — parallax is the only depth tvOS has.
func renderGlyph(_ s: AppSpec, w: Int, h: Int, chars: Set<Character>, coverage: CGFloat = 0.62) -> CGContext {
    let ctx = context(w: w, h: h)
    drawGlyph(s, into: ctx, w: w, h: h, coverage: coverage, dim: 1.0, only: chars)
    return ctx
}

/// One tile of a glyph map: a 4-connected run of one character, in cells.
struct GlyphTile {
    let ch: Character
    let rows: ClosedRange<Int>
    let cols: ClosedRange<Int>
}

/// Rounding has to know where a tile ends, so the map is read as tiles rather
/// than painted cell by cell — per-cell corners would notch every tile.
func tiles(of glyph: [String]) -> [GlyphTile] {
    let grid = glyph.map(Array.init)
    func at(_ r: Int, _ c: Int) -> Character? {
        grid.indices.contains(r) && grid[r].indices.contains(c) ? grid[r][c] : nil
    }
    var seen = Set<[Int]>()
    var found: [GlyphTile] = []
    for r in grid.indices {
        for c in grid[r].indices where grid[r][c] != "." && !seen.contains([r, c]) {
            let ch = grid[r][c]
            var stack = [[r, c]], rows = r...r, cols = c...c
            seen.insert([r, c])
            while let cell = stack.popLast() {
                rows = min(rows.lowerBound, cell[0])...max(rows.upperBound, cell[0])
                cols = min(cols.lowerBound, cell[1])...max(cols.upperBound, cell[1])
                for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let next = [cell[0] + dr, cell[1] + dc]
                    if at(next[0], next[1]) == ch, seen.insert(next).inserted { stack.append(next) }
                }
            }
            found.append(GlyphTile(ch: ch, rows: rows, cols: cols))
        }
    }
    return found
}

/// The glyph map, centered on an integer cell pitch. Each tile is one rounded
/// rectangle (`tileCorner`); '+' tiles grow about their centre by `sparkScale`.
func drawGlyph(
    _ s: AppSpec, into ctx: CGContext, w: Int, h: Int, coverage: CGFloat, dim: CGFloat,
    only chars: Set<Character> = ["#", "+"]
) {
    let rows = s.glyph.count
    let cols = s.glyph.map(\.count).max()!
    let px = max(1, Int(min(CGFloat(w) / CGFloat(cols), CGFloat(h) / CGFloat(rows)) * coverage))
    let x0 = (w - cols * px) / 2
    let y0 = (h - rows * px) / 2
    for tile in tiles(of: s.glyph) where chars.contains(tile.ch) {
        let color: RGB
        switch tile.ch {
        case "#": color = s.accent
        case "+": color = s.secondary
        default: continue
        }
        // Flip rows: CoreGraphics origin is bottom-left; glyph maps read top-down.
        var rect = CGRect(
            x: x0 + tile.cols.lowerBound * px, y: y0 + (rows - 1 - tile.rows.upperBound) * px,
            width: tile.cols.count * px, height: tile.rows.count * px)
        if tile.ch == "+" {
            let grow = s.sparkScale - 1
            rect = rect.insetBy(dx: -rect.width * grow / 2, dy: -rect.height * grow / 2)
        }
        let radius = min(rect.width, rect.height) * s.tileCorner
        ctx.setFillColor(color.alpha(dim))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }
}

/// Flattened composition (Top Shelf, Launch): back + grid + glyph in one opaque PNG.
func renderFlat(_ s: AppSpec, w: Int, h: Int, coverage: CGFloat, glyphDim: CGFloat = 1.0) -> CGContext {
    let ctx = renderBack(s, w: w, h: h)
    let cell = max(8, min(w, h) / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < h {
        var x = cell / 2
        while x < w {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    drawGlyph(s, into: ctx, w: w, h: h, coverage: coverage, dim: glyphDim)
    return ctx
}

// MARK: - Asset catalog plumbing

let info = "\"info\" : { \"author\" : \"xcode\", \"version\" : 1 }"

func write(_ text: String, _ url: URL) {
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.data(using: .utf8)!.write(to: url)
}

/// One parallax layer folder: Name.imagestacklayer/Content.imageset/<pngs>
func emitLayer(
    _ s: AppSpec, name: String, stack: URL, w: Int, h: Int, scales: [Int],
    render: (AppSpec, Int, Int) -> CGContext
) {
    let layerDir = stack.appendingPathComponent("\(name).imagestacklayer")
    write("{ \(info) }", layerDir.appendingPathComponent("Contents.json"))
    let setDir = layerDir.appendingPathComponent("Content.imageset")
    var entries: [String] = []
    for scale in scales {
        let file = scale == 1 ? "\(name.lowercased()).png" : "\(name.lowercased())@\(scale)x.png"
        entries.append(
            "{ \"filename\" : \"\(file)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
        writePNG(render(s, w * scale, h * scale), to: setDir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        setDir.appendingPathComponent("Contents.json"))
}

func emitStack(_ s: AppSpec, name: String, brand: URL, w: Int, h: Int, scales: [Int]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    // Front to back, the same planes as the groups in `nine/Nine.icon`.
    let layers = ["Spark", "Board", "Field", "Back"]
    write(
        "{ \"layers\" : [ "
            + layers.map { "{ \"filename\" : \"\($0).imagestacklayer\" }" }.joined(separator: ", ")
            + " ], \(info) }",
        stack.appendingPathComponent("Contents.json"))
    emitLayer(s, name: "Spark", stack: stack, w: w, h: h, scales: scales) {
        renderGlyph($0, w: $1, h: $2, chars: ["+"])
    }
    emitLayer(s, name: "Board", stack: stack, w: w, h: h, scales: scales) {
        renderGlyph($0, w: $1, h: $2, chars: ["#"])
    }
    emitLayer(s, name: "Field", stack: stack, w: w, h: h, scales: scales) {
        renderField($0, w: $1, h: $2)
    }
    emitLayer(s, name: "Back", stack: stack, w: w, h: h, scales: scales) {
        renderBack($0, w: $1, h: $2)
    }
}

func emitImageset(_ s: AppSpec, name: String, brand: URL, w: Int, h: Int, coverage: CGFloat) {
    let setDir = brand.appendingPathComponent("\(name).imageset")
    var entries: [String] = []
    for scale in [1, 2] {
        let file = scale == 1 ? "shelf.png" : "shelf@\(scale)x.png"
        entries.append(
            "{ \"filename\" : \"\(file)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
        writePNG(
            renderFlat(s, w: w * scale, h: h * scale, coverage: coverage),
            to: setDir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        setDir.appendingPathComponent("Contents.json"))
}

func emitLaunchImage(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("Launch Image.launchimage")
    var entries: [String] = []
    for scale in [1, 2] {
        let file = scale == 1 ? "launch.png" : "launch@\(scale)x.png"
        entries.append("""
            { "extent" : "full-screen", "filename" : "\(file)", "idiom" : "tv", \
            "minimum-system-version" : "11.0", "orientation" : "landscape", \
            "scale" : "\(scale)x" }
            """)
        // Launch is deliberately quiet: dark field, dim glyph — apps open into black rooms.
        writePNG(
            renderFlat(s, w: 1920 * scale, h: 1080 * scale, coverage: 0.28, glyphDim: 0.5),
            to: dir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

/// iOS app icon: the flat composition (back + grid + glyph) in an OPAQUE
/// bitmap — the App Store rejects icons that carry an alpha channel.
func renderIOSIcon(_ s: AppSpec, size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])
    let cell = max(8, size / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < size {
        var x = cell / 2
        while x < size {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    drawGlyph(s, into: ctx, w: size, h: size, coverage: 0.66, dim: 1.0)
    return ctx
}

/// Single-size icon set: Xcode derives every device size from the 1024.
func emitIOSAppIcon(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("AppIcon.appiconset")
    writePNG(renderIOSIcon(s, size: 1024), to: dir.appendingPathComponent("AppIcon-1024.png"))
    write(
        "{ \"images\" : [ { \"filename\" : \"AppIcon-1024.png\", \"idiom\" : \"universal\", "
            + "\"platform\" : \"ios\", \"size\" : \"1024x1024\" } ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

/// The watch icon set (PRD-6). watchOS takes the flat square art, same as iOS
/// — the system applies the circular mask itself — so this reuses
/// `renderIOSIcon` verbatim rather than inventing a wrist-specific mark.
func emitWatchAppIcon(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("AppIcon-watchOS.appiconset")
    writePNG(renderIOSIcon(s, size: 1024), to: dir.appendingPathComponent("AppIcon-1024.png"))
    write(
        "{ \"images\" : [ { \"filename\" : \"AppIcon-1024.png\", \"idiom\" : \"universal\", "
            + "\"platform\" : \"watchos\", \"size\" : \"1024x1024\" } ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

/// Alternate iOS icons (PRD-16). Each is the *primary* renderer run against a
/// recolored copy of the spec, so the mark, the grid pitch and the glyph
/// coverage stay bit-identical to the primary icon — only the palette moves.
/// Renders opaque for the same reason `emitIOSAppIcon` does: the App Store
/// rejects an iOS icon carrying an alpha channel, and that applies to alternates.
func emitIOSAltIcons(_ s: AppSpec, catalog: URL) {
    for variant in s.altIcons {
        let recolored = AppSpec(
            folder: s.folder,
            backTop: variant.backTop, backBottom: variant.backBottom,
            grid: variant.grid, accent: variant.accent, secondary: variant.secondary,
            glyph: s.glyph, tileCorner: s.tileCorner, sparkScale: s.sparkScale)
        let dir = catalog.appendingPathComponent("\(variant.name).appiconset")
        let file = "\(variant.name)-1024.png"
        writePNG(renderIOSIcon(recolored, size: 1024), to: dir.appendingPathComponent(file))
        write(
            "{ \"images\" : [ { \"filename\" : \"\(file)\", \"idiom\" : \"universal\", "
                + "\"platform\" : \"ios\", \"size\" : \"1024x1024\" } ], \(info) }",
            dir.appendingPathComponent("Contents.json"))
    }
}

/// macOS app icon: the flat composition clipped to a rounded-rect with a HIG
/// margin (PRD-4 §1). Transparency IS expected here (the margin + corners),
/// unlike the opaque iOS icon.
func renderMacIcon(_ s: AppSpec, size: Int) -> CGContext {
    let ctx = context(w: size, h: size)          // premultipliedLast: transparent
    let fsize = CGFloat(size)
    let margin = fsize * 0.10                     // ~10% HIG margin all around
    let inner = CGRect(x: margin, y: margin, width: fsize - 2 * margin, height: fsize - 2 * margin)
    let radius = inner.width * 0.2237             // the macOS continuous-corner ratio
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace!, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: fsize), end: CGPoint(x: 0, y: 0), options: [])
    let cell = max(8, size / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < size {
        var x = cell / 2
        while x < size {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    ctx.restoreGState()
    // Glyph centered over the whole canvas; the reduced coverage keeps it
    // inside the margin.
    drawGlyph(s, into: ctx, w: size, h: size, coverage: 0.50, dim: 1.0)
    return ctx
}

/// The full mac idiom icon set (16…512 at 1x/2x); Xcode assembles the .icns.
func emitMacAppIcon(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("AppIcon-macOS.appiconset")
    let sizes: [(pt: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
        (256, 1), (256, 2), (512, 1), (512, 2),
    ]
    var entries: [String] = []
    for item in sizes {
        let file = "icon_\(item.pt)x\(item.pt)@\(item.scale)x.png"
        entries.append(
            "{ \"size\" : \"\(item.pt)x\(item.pt)\", \"idiom\" : \"mac\", "
                + "\"filename\" : \"\(file)\", \"scale\" : \"\(item.scale)x\" }")
        writePNG(renderMacIcon(s, size: item.pt * item.scale), to: dir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let rootDir = scriptDir.deletingLastPathComponent()
let requested = Array(CommandLine.arguments.dropFirst())
let selected = requested.isEmpty ? specs : specs.filter { requested.contains($0.folder) }
guard !selected.isEmpty else {
    FileHandle.standardError.write("No matching app. Folders: \(specs.map(\.folder))\n".data(using: .utf8)!)
    exit(1)
}

for s in selected {
    let catalog = rootDir.appendingPathComponent("\(s.folder)/Assets.xcassets")
    try? FileManager.default.removeItem(at: catalog)
    write("{ \(info) }", catalog.appendingPathComponent("Contents.json"))

    let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
    write("""
        { "assets" : [ \
        { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" }, \
        { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" }, \
        { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" }, \
        { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" } \
        ], \(info) }
        """, brand.appendingPathComponent("Contents.json"))

    emitStack(s, name: "App Icon", brand: brand, w: 400, h: 240, scales: [1, 2])
    emitStack(s, name: "App Icon - App Store", brand: brand, w: 1280, h: 768, scales: [1])
    emitImageset(s, name: "Top Shelf Image", brand: brand, w: 1920, h: 720, coverage: 0.55)
    emitImageset(s, name: "Top Shelf Image Wide", brand: brand, w: 2320, h: 720, coverage: 0.55)
    emitLaunchImage(s, catalog: catalog)
    if s.iosIcon { emitIOSAppIcon(s, catalog: catalog) }
    if !s.altIcons.isEmpty { emitIOSAltIcons(s, catalog: catalog) }
    if s.macIcon { emitMacAppIcon(s, catalog: catalog) }
    if s.watchIcon { emitWatchAppIcon(s, catalog: catalog) }
    print("✓ \(s.folder)/Assets.xcassets")
}
