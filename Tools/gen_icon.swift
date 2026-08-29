//
//  gen_icon.swift
//  Jetshot tools
//
//  Renders the 1024 × 1024 app icon.
//
//      swift Tools/gen_icon.swift jetshot/JetshotIcon.icon/Assets
//
//  Writes two files, because Icon Composer wants layers rather than one flattened
//  picture: `background.png` is the sky, `foreground.png` is the ship and everything
//  that glows, on transparent. Handing it a single full-bleed image works for the
//  default appearance and then has nothing to work with for the dark and tinted
//  ones — the tinted variant of a flattened icon is a tinted rectangle.
//
//  ## Why the icon looks like this
//
//  Every competitor in the category ships the same picture. Pull the top twelve
//  results for "space shooter" and you get twelve detailed three-quarter renders of
//  a metallic fighter, pointing up, firing a beam, surrounded by enemies, bullets
//  and explosions, on a saturated blue-red-purple sky with no empty space anywhere.
//  At the size the icon is actually seen first — around 60 points in a search
//  result — all twelve collapse into the same colourful smudge and none of them is
//  telling you anything.
//
//  The two that do stand out in that grid are the two that are a *symbol* rather
//  than a *scene*: Galaga Wars, a flat red ship on black with a ring of dots, and
//  Phoenix 2, a gold bird on dark blue. Neither has any detail to lose.
//
//  So this icon is deliberately the opposite of the crowd, and it costs nothing to
//  be, because it is also what the game genuinely looks like: one glowing vector
//  ship on a near-black sky, with real bloom around it and a great deal of nothing
//  else. In a row of search results it is the only dark tile and the only one with
//  a single readable shape.
//
//  The ship is the game's, redrawn for a square. `Player.setupPlayer`'s own path was
//  tried first, vertex for vertex, and it does not survive the blow-up: in play it is
//  36 points tall and its twin nacelles read as engines, but at 1024 they are long
//  parallel legs and the whole thing turns into a cartoon rocket standing up. The
//  path below keeps the language — sharp nose, swept wings, twin engines, one
//  cockpit — and changes the proportions to a square's: wings twice as wide, engines
//  a third as long. An icon is a poster, not a screenshot.
//
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "jetshot/JetshotIcon.icon/Assets"

let size = 1024
let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext() -> CGContext {
    CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// The game's own palette. `sceneBackground` and the ship's fill and stroke are
// UITheme.Colors and Player.setupPlayer respectively.
let skyTop = color(0.055, 0.055, 0.150)
let skyDeep = color(0.012, 0.012, 0.045)
let hullFill = color(0.20, 0.60, 0.90)
let hullEdge = color(0.40, 0.90, 1.00)
let neon = color(0.25, 0.85, 1.00)
let ember = color(0.60, 0.98, 1.00)

// MARK: - Geometry

/// The icon's ship, in its own ±18 unit space. Left half written out and mirrored,
/// because a hand-written right half is how a symmetrical shape ends up half a unit
/// off centre.
func shipPath() -> CGPath {
    // Nose down the centre line, out along the wing, back in to the engines.
    let half: [CGPoint] = [
        CGPoint(x: 0, y: 18),        // nose
        CGPoint(x: -3.6, y: 7.5),    // fuselage shoulder
        CGPoint(x: -3.2, y: 0.5),    // fuselage waist
        CGPoint(x: -16.5, y: -6.5),  // wing leading tip
        CGPoint(x: -13.8, y: -12.5), // wing trailing tip
        CGPoint(x: -6.6, y: -8.6),   // wing root
        CGPoint(x: -7.0, y: -15.0),  // engine outer
        CGPoint(x: -3.0, y: -15.0),  // engine inner
        CGPoint(x: -3.0, y: -7.6),   // engine shoulder
        CGPoint(x: 0, y: -5.6)       // centre notch
    ]

    let p = CGMutablePath()
    p.move(to: half[0])
    for point in half.dropFirst() { p.addLine(to: point) }
    for point in half.dropFirst().dropLast().reversed() {
        p.addLine(to: CGPoint(x: -point.x, y: point.y))
    }
    p.closeSubpath()
    return p
}

/// Where the two nozzles are, for the exhaust below them.
let nozzles: [CGFloat] = [-5.0, 5.0]

/// Ship units to icon points. 17 puts the hull at 561 × 561 — 55% of the tile each
/// way, square, which is what lets it sit in the middle of a square tile without
/// either axis running out first. The margins are the ones the crowded icons spend
/// on debris.
let shipScale: CGFloat = 17
let shipCenter = CGPoint(x: S / 2, y: S * 0.485)

/// Exhaust below, fire above. The ship alone, centred with empty space over and
/// under it, read as a cartoon rocket standing on two legs — the nacelles are legs
/// unless something is visibly coming out of them.
///
/// The exhaust is short and soft rather than a long beam, and that is copied rather
/// than invented: the game hangs a `NeonFX.radialGlow(radius: 11)` under each nozzle
/// on a ship 36 units tall, so what is actually under there is a broad soft blob,
/// not a spike. Long tapering plumes were tried and turned the lower half of the
/// tile into two blue pillars, which is the one reading worse than legs.
///
/// It is worth saying what the fire above is *not*: every competitor draws a single
/// fat laser firing upward out of a ship. This is the game's own multi-shot —
/// discrete bolts in ranks, as `Player.shoot()` puts them on screen.

func shipTransform() -> CGAffineTransform {
    CGAffineTransform(translationX: shipCenter.x, y: shipCenter.y)
        .scaledBy(x: shipScale, y: shipScale)
}

/// A point in ship units, in icon coordinates.
func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: shipCenter.x + x * shipScale, y: shipCenter.y + y * shipScale)
}

// MARK: - Bloom
//
// The same trick NeonFX uses in the game: blur the silhouette and composite the
// blurs back additively, rather than fake a glow with a soft-edged gradient. Three
// radii, because one wide blur alone reads as fog and one tight blur alone reads as
// a sticker — the wide pass tints the sky, the middle pass gives the shape a halo
// and the tight pass makes the edge itself look hot.

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func blurred(_ image: CGImage, radius: Double) -> CGImage? {
    let input = CIImage(cgImage: image)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage else { return nil }
    // Clamp back to the original extent; a blur grows the image by its radius and
    // the overhang would land the icon off-centre when it is drawn into the tile.
    return ciContext.createCGImage(output, from: input.extent)
}

/// The shot, in ship units: two inner columns and two outer ones, fading and
/// shortening with distance so the eye reads them as travelling away rather than as
/// a static pattern.
struct Bolt { let x: CGFloat; let y: CGFloat; let height: CGFloat; let alpha: CGFloat }
/// Rows rather than a scatter, because that is what `Player.shoot()` puts on screen:
/// the barrels fire together, so the bolts travel as a rank. A staggered pattern was
/// tried first and read as debris.
let bolts: [Bolt] = ([-9.0, -3.1, 3.1, 9.0] as [CGFloat]).map {
    Bolt(x: $0, y: 22.4, height: 3.0, alpha: 1.00)
} + ([-9.0, -3.1, 3.1, 9.0] as [CGFloat]).map {
    Bolt(x: $0, y: 28.0, height: 2.4, alpha: 0.48)
} + ([-3.1, 3.1] as [CGFloat]).map {
    Bolt(x: $0, y: 32.7, height: 1.8, alpha: 0.22)
}

func boltPath(_ b: Bolt) -> CGPath {
    let p = at(b.x, b.y)
    let w: CGFloat = 0.78 * shipScale
    let h = b.height * shipScale
    let rect = CGRect(x: p.x - w, y: p.y - h / 2, width: w * 2, height: h)
    return CGPath(roundedRect: rect, cornerWidth: w, cornerHeight: w, transform: nil)
}

/// Everything that glows, as one silhouette on transparent — the source every bloom
/// pass is blurred from.
func makeGlowSource() -> CGImage {
    let ctx = makeContext()

    ctx.saveGState()
    ctx.concatenate(shipTransform())
    ctx.setFillColor(neon)
    ctx.addPath(shipPath())
    ctx.fillPath()
    ctx.restoreGState()

    // Engine exhaust: a short soft cone under each nozzle. Drawn into the glow
    // source rather than on top of it, so the bloom carries it too — an engine that
    // does not light the sky around it looks switched off.
    for x in nozzles {
        let top = at(x, -14.4)
        let plume = CGMutablePath()
        plume.move(to: CGPoint(x: top.x - 38, y: top.y + 8))
        plume.addLine(to: CGPoint(x: top.x + 38, y: top.y + 8))
        plume.addLine(to: CGPoint(x: top.x + 18, y: top.y - 146))
        plume.addLine(to: CGPoint(x: top.x - 18, y: top.y - 146))
        plume.closeSubpath()
        ctx.setFillColor(color(0.25, 0.85, 1.00, 0.85))
        ctx.addPath(plume)
        ctx.fillPath()
    }

    for bolt in bolts {
        ctx.setFillColor(color(0.35, 0.90, 1.00, bolt.alpha * 0.9))
        ctx.addPath(boltPath(bolt))
        ctx.fillPath()
    }

    return ctx.makeImage()!
}

// MARK: - Background

let bg = makeContext()

// Sky. Radial rather than linear, centred a little above the middle, so the
// brightest part of the background sits behind the ship and the corners fall away
// to nearly black — the vignette and the backdrop are the same gradient.
let sky = CGGradient(
    colorsSpace: space,
    colors: [skyTop, skyDeep] as CFArray,
    locations: [0, 1]
)!
bg.setFillColor(skyDeep)
bg.fill(CGRect(x: 0, y: 0, width: S, height: S))
bg.drawRadialGradient(
    sky,
    startCenter: CGPoint(x: S / 2, y: S * 0.56), startRadius: 0,
    endCenter: CGPoint(x: S / 2, y: S * 0.56), endRadius: S * 0.78,
    options: [.drawsAfterEndLocation]
)

// Stars. Sixteen, small, and seeded rather than random so the icon is
// byte-reproducible — an icon that changes on every regeneration cannot be diffed.
var seed: UInt64 = 0x5EED_1E75
func rnd() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) % 100_000) / 100_000
}
for _ in 0..<16 {
    let x = rnd() * S
    let y = rnd() * S
    // Keep them out of the middle, where they would only compete with the ship.
    let dx = (x - S / 2) / S, dy = (y - S * 0.52) / S
    guard (dx * dx + dy * dy).squareRoot() > 0.30 else { continue }
    let r = 1.6 + rnd() * 2.6
    bg.setFillColor(color(1, 1, 1, 0.20 + rnd() * 0.35))
    bg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// MARK: - Foreground

let ctx = makeContext()

// A broad cyan core behind the ship, before the bloom. The blurs alone hug the
// silhouette; this is what puts light in the middle of the tile, so the icon reads
// as lit from within rather than as a decal on a dark square.
ctx.setBlendMode(.plusLighter)
let core = CGGradient(
    colorsSpace: space,
    colors: [color(0.10, 0.55, 0.95, 0.55), color(0.06, 0.30, 0.75, 0.22),
             color(0, 0, 0, 0)] as CFArray,
    locations: [0, 0.45, 1]
)!
ctx.drawRadialGradient(
    core,
    startCenter: CGPoint(x: S / 2, y: S * 0.50), startRadius: 0,
    endCenter: CGPoint(x: S / 2, y: S * 0.50), endRadius: S * 0.52,
    options: []
)
ctx.setBlendMode(.normal)

// Bloom, widest and faintest first. Four passes rather than three, and hotter than
// a photographic bloom would be: the game runs its own bloom additively over black
// and the icon has to survive being shrunk to 60 points, where a subtle halo is
// simply gone.
let glow = makeGlowSource()
let full = CGRect(x: 0, y: 0, width: S, height: S)
ctx.setBlendMode(.plusLighter)
for (radius, alpha) in [(130.0, 0.42), (60.0, 0.55), (24.0, 0.70), (9.0, 0.85)] {
    guard let pass = blurred(glow, radius: radius) else { continue }
    ctx.setAlpha(CGFloat(alpha))
    ctx.draw(pass, in: full)
}
ctx.setAlpha(1)
ctx.setBlendMode(.normal)

// The exhaust again, crisply this time, so it has a bright core inside the haze.
// A radial blob first — the shape the game actually hangs there — then a short
// tapering flame inside it for direction.
ctx.setBlendMode(.plusLighter)
for x in nozzles {
    let top = at(x, -14.4)

    let blob = CGGradient(
        colorsSpace: space,
        colors: [color(0.90, 1.0, 1.0, 1.0), color(0.28, 0.86, 1.0, 0.62),
                 color(0.05, 0.45, 0.95, 0)] as CFArray,
        locations: [0, 0.32, 1]
    )!
    ctx.saveGState()
    ctx.translateBy(x: top.x, y: top.y - 40)
    ctx.scaleBy(x: 1.0, y: 2.0)   // stretched down the direction of travel
    ctx.drawRadialGradient(
        blob,
        startCenter: .zero, startRadius: 0,
        endCenter: .zero, endRadius: 78,
        options: []
    )
    ctx.restoreGState()

    let flame = CGMutablePath()
    flame.move(to: CGPoint(x: top.x - 34, y: top.y + 6))
    flame.addLine(to: CGPoint(x: top.x + 34, y: top.y + 6))
    flame.addLine(to: CGPoint(x: top.x + 9, y: top.y - 132))
    flame.addLine(to: CGPoint(x: top.x - 9, y: top.y - 132))
    flame.closeSubpath()
    let core = CGGradient(
        colorsSpace: space,
        colors: [color(1.0, 1.0, 1.0, 1.0), color(0.55, 0.97, 1.0, 0.55),
                 color(0.10, 0.70, 1.0, 0)] as CFArray,
        locations: [0, 0.4, 1]
    )!
    ctx.saveGState()
    ctx.addPath(flame)
    ctx.clip()
    ctx.drawLinearGradient(
        core,
        start: CGPoint(x: top.x, y: top.y + 6),
        end: CGPoint(x: top.x, y: top.y - 132),
        options: []
    )
    ctx.restoreGState()
}
ctx.setBlendMode(.normal)

// The hull. Filled with the game's blue, then a hot cyan edge — the edge is what
// survives at 60 points, so it is drawn heavier here than the game's 2.5 points
// scales to.
ctx.saveGState()
ctx.concatenate(shipTransform())
ctx.addPath(shipPath())
ctx.restoreGState()
ctx.clip()
// Lit from the nose, which is where the ship is going and where the eye lands
// first. Flat fill plus a sheen was tried and the hull read as a paper cut-out.
let hull = CGGradient(
    colorsSpace: space,
    colors: [color(0.78, 0.99, 1.00, 1), hullEdge, hullFill,
             color(0.16, 0.46, 0.78, 1)] as CFArray,
    locations: [0, 0.18, 0.62, 1]
)!
ctx.drawLinearGradient(hull, start: at(0, 18), end: at(0, -18), options: [])
ctx.resetClip()

// One inlay panel down the fuselage. The hull was otherwise a flat sheet of light
// blue between two edges, and a single darker shape reads as structure where a
// dozen panel lines would read as noise — and would be gone at 60 points anyway.
let inlay = CGMutablePath()
let spine: [CGPoint] = [
    CGPoint(x: 0, y: 12.4), CGPoint(x: -2.0, y: 6.2), CGPoint(x: -1.9, y: -6.0),
    CGPoint(x: 0, y: -4.6), CGPoint(x: 1.9, y: -6.0), CGPoint(x: 2.0, y: 6.2)
]
inlay.move(to: spine[0])
for point in spine.dropFirst() { inlay.addLine(to: point) }
inlay.closeSubpath()
ctx.saveGState()
ctx.concatenate(shipTransform())
ctx.setFillColor(color(0.10, 0.36, 0.68, 0.55))
ctx.addPath(inlay)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.concatenate(shipTransform())
ctx.setStrokeColor(hullEdge)
ctx.setLineWidth(2.2)
ctx.setLineJoin(.round)
ctx.addPath(shipPath())
ctx.strokePath()
ctx.restoreGState()

// Cockpit: the one piece of interior detail, and it is a circle because a circle is
// the only detail that still reads once the tile is 60 points across.
let cockpit = at(0, 6.5)
ctx.setFillColor(color(0.22, 0.62, 0.92, 1.0))
ctx.fillEllipse(in: CGRect(x: cockpit.x - 44, y: cockpit.y - 44, width: 88, height: 88))
ctx.setFillColor(color(0.34, 0.86, 1.00, 0.98))
ctx.fillEllipse(in: CGRect(x: cockpit.x - 37, y: cockpit.y - 37, width: 74, height: 74))
ctx.setFillColor(color(0.92, 1.00, 1.00, 1.0))
ctx.fillEllipse(in: CGRect(x: cockpit.x - 20, y: cockpit.y - 20, width: 40, height: 40))
ctx.setStrokeColor(ember)
ctx.setLineWidth(5)
ctx.strokeEllipse(in: CGRect(x: cockpit.x - 44, y: cockpit.y - 44, width: 88, height: 88))

// Fire, crisply, over its own bloom.
ctx.setBlendMode(.plusLighter)
for bolt in bolts {
    ctx.setFillColor(color(0.80, 1.0, 1.0, bolt.alpha))
    ctx.addPath(boltPath(bolt))
    ctx.fillPath()
}
ctx.setBlendMode(.normal)

// MARK: - Write

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("could not write \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("could not finalise \(path)\n".utf8))
        exit(1)
    }
    print("→ \(path)  \(size)×\(size)")
}

write(bg.makeImage()!, to: outDir + "/background.png")
write(ctx.makeImage()!, to: outDir + "/foreground.png")
