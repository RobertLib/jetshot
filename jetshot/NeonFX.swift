//
//  NeonFX.swift
//  jetshot
//
//  Core visual-effects foundation: real (blurred) bloom, radial glows,
//  shockwaves, sparks and the screen grade overlay.
//
//  The game is drawn entirely from vector shapes, so its look lives or dies on
//  how light is rendered. Everything here produces *pre-rendered, cached*
//  textures so the expensive part happens once per distinct shape and the
//  per-frame cost is a single additively blended sprite.
//

import SpriteKit

enum NeonFX {

    // MARK: - Shared resources

    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    /// Blooms and glows are numerous: one per distinct shape and colour. They are kept
    /// small by rendering them at no more than 1–2x (see `softScale`), and bounded by
    /// dropping whichever has gone longest unused once the cache is full, so a run of
    /// one-off shapes cannot push out the shared ones every wave keeps asking for.
    private static let maxCacheEntries = 96
    private static var bloomCache = LRUCache<String, BloomTexture>(capacity: maxCacheEntries)
    private static var radialCache = LRUCache<String, SKTexture>(capacity: maxCacheEntries)
    /// One entry per screen shape, and a session sees one or two (portrait and the odd
    /// split-view size), so a handful is plenty.
    private static var gradeCache = LRUCache<String, SKTexture>(capacity: 4)

    struct BloomTexture {
        let texture: SKTexture
        /// Size in points, already padded to contain the blur falloff.
        let size: CGSize
        /// Offset of the texture centre relative to the source node's origin.
        let center: CGPoint
    }

    static func clearCaches() {
        bloomCache.removeAll()
        radialCache.removeAll()
        gradeCache.removeAll()
    }

    /// A bounded cache that, when full, evicts the entry least recently asked for.
    ///
    /// The caches here used to empty themselves completely on reaching their limit, so
    /// a level's worth of one-off shapes threw out every shared bloom with them — enemy
    /// types, coins, power-ups, the player's shield — and each paid for a blur and a GPU
    /// readback again in the middle of a wave. Dropping one stale entry at a time keeps
    /// whatever is in steady use resident however many strays pass through.
    ///
    /// Eviction scans for the oldest entry, which is linear, but only happens on a miss
    /// in a full cache — and a miss is followed by rendering a texture, which dwarfs it.
    nonisolated struct LRUCache<Key: Hashable, Value> {
        let capacity: Int
        private var entries: [Key: (value: Value, lastUse: UInt64)] = [:]
        private var tick: UInt64 = 0

        init(capacity: Int) {
            self.capacity = max(1, capacity)
        }

        var count: Int { entries.count }

        /// Whether `key` is cached, without counting as a use.
        func contains(_ key: Key) -> Bool { entries[key] != nil }

        /// The cached value, marking it as just used.
        mutating func value(forKey key: Key) -> Value? {
            guard let entry = entries[key] else { return nil }
            tick &+= 1
            entries[key] = (entry.value, tick)
            return entry.value
        }

        mutating func insert(_ value: Value, forKey key: Key) {
            tick &+= 1
            if entries[key] == nil, entries.count >= capacity,
               let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
                entries.removeValue(forKey: oldest)
            }
            entries[key] = (value, tick)
        }

        mutating func removeAll() {
            entries.removeAll()
        }
    }

    /// Render scale for a texture that is blurred or soft by construction.
    ///
    /// A Gaussian halo or a radial falloff has no detail finer than its blur, so the
    /// device's 3x buys nothing but nine times the pixels: nine times the memory and
    /// nine times the CoreImage work for a bloom, at its first use, mid-wave. Upscaled
    /// with linear filtering it is indistinguishable.
    private static func softScale(cap: CGFloat) -> CGFloat {
        min(UIGraphicsImageRendererFormat.preferred().scale, cap)
    }

    // MARK: - Shape bloom

    /// Attaches a genuinely blurred, additively blended halo behind a shape node.
    ///
    /// This replaces the old "three scaled copies of the path" trick, which
    /// produced hard-edged, muddy haloes. A real Gaussian falloff reads as light
    /// instead of as a bigger version of the same shape, which is what makes the
    /// crisp vector on top look neon rather than blurry.
    ///
    /// - Parameters:
    ///   - node: Shape to light up. Its `path` is used as the emitter silhouette.
    ///   - color: Light colour. Defaults to the node's fill (or stroke, if unfilled).
    ///   - intensity: Overall brightness multiplier. 1.0 is the tuned default.
    ///   - blur: Gaussian radius in points. Larger = softer, wider bloom.
    ///   - spread: Dilates the silhouette before blurring, so thin shapes
    ///             (bullets, wireframes) still throw a substantial halo.
    ///   - name: Child node name, so it can be found/removed later.
    @discardableResult
    static func addBloom(
        to node: SKShapeNode,
        color: UIColor? = nil,
        intensity: CGFloat = 1.0,
        blur: CGFloat = 6,
        spread: CGFloat = 1.5,
        name: String = "neonBloom"
    ) -> SKNode? {
        node.childNode(withName: name)?.removeFromParent()

        guard let path = node.path else { return nil }
        let glowColor = color ?? resolvedLightColor(for: node)

        guard let bloom = bloomTexture(for: path, color: glowColor, blur: blur, spread: spread) else {
            return nil
        }

        // The container sits at the silhouette's centre so that pulsing it
        // (see `pulse(_:)`) scales the halo around the shape, not around origin.
        let container = SKNode()
        container.name = name
        container.position = bloom.center
        container.zPosition = -1

        let halo = SKSpriteNode(texture: bloom.texture, size: bloom.size)
        halo.blendMode = .add
        halo.alpha = min(1.0, 0.72 * intensity)
        container.addChild(halo)

        node.addChild(container)
        return container
    }

    /// Adds a bloom that breathes, for hero elements (player, pickups, bosses).
    static func addPulsingBloom(
        to node: SKShapeNode,
        color: UIColor? = nil,
        intensity: CGFloat = 1.0,
        blur: CGFloat = 6,
        spread: CGFloat = 1.5,
        minScale: CGFloat = 0.92,
        maxScale: CGFloat = 1.12,
        duration: TimeInterval = 1.2,
        name: String = "neonBloom"
    ) {
        guard let container = addBloom(
            to: node, color: color, intensity: intensity,
            blur: blur, spread: spread, name: name
        ) else { return }

        container.setScale(minScale)
        let up = SKAction.scale(to: maxScale, duration: duration / 2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.scale(to: minScale, duration: duration / 2)
        down.timingMode = .easeInEaseOut
        container.run(.repeatForever(.sequence([up, down])))
    }

    static func removeBloom(from node: SKShapeNode, name: String = "neonBloom") {
        node.childNode(withName: name)?.removeFromParent()
    }

    private static func resolvedLightColor(for node: SKShapeNode) -> UIColor {
        // An unfilled wireframe should glow in its stroke colour.
        if node.fillColor.cgColor.alpha > 0.01 { return node.fillColor }
        if node.strokeColor.cgColor.alpha > 0.01 { return node.strokeColor }
        return .white
    }

    // MARK: - Bloom texture rendering

    private static func bloomTexture(
        for path: CGPath,
        color: UIColor,
        blur: CGFloat,
        spread: CGFloat
    ) -> BloomTexture? {
        let box = path.boundingBoxOfPath
        guard box.width.isFinite, box.height.isFinite,
              box.width > 0.01, box.height > 0.01 else { return nil }

        let key = "\(pathKey(path))|\(colorKey(color))|\(Int(blur * 4))|\(Int(spread * 4))"
        if let cached = bloomCache.value(forKey: key) {
            return BloomTexture(
                texture: cached.texture,
                size: cached.size,
                center: CGPoint(x: box.midX, y: box.midY)
            )
        }

        // A blur of a few points or more leaves nothing a 1x texture cannot hold. A
        // tighter one keeps some of the silhouette's edge, so it gets 2x.
        let scale = softScale(cap: blur >= 3 ? 1 : 2)

        // Pad enough for the Gaussian tail (~3 sigma) plus the dilation, then round up
        // to whole pixels so the silhouette lands exactly in the middle of the texture.
        let padding = blur * 3 + spread + 2
        let canvas = CGSize(width: ((box.width + padding * 2) * scale).rounded(.up) / scale,
                            height: ((box.height + padding * 2) * scale).rounded(.up) / scale)
        guard canvas.width < 2048, canvas.height < 2048 else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // Move the silhouette so its bounding box is centred on the canvas.
            cg.translateBy(x: canvas.width / 2 - box.midX, y: canvas.height / 2 - box.midY)

            cg.setFillColor(color.cgColor)
            cg.setStrokeColor(color.cgColor)
            cg.addPath(path)
            cg.fillPath()

            if spread > 0 {
                // Dilate: stroking with a round pen thickens thin geometry so
                // bullets and wireframes emit light instead of a faint smear.
                cg.addPath(path)
                cg.setLineWidth(spread * 2)
                cg.setLineJoin(.round)
                cg.setLineCap(.round)
                cg.strokePath()
            }
        }

        guard let cgImage = image.cgImage else { return nil }

        let input = CIImage(cgImage: cgImage)
        // `clampedToExtent` keeps the blur from darkening at the canvas border;
        // the border is transparent, so it extends transparency outwards. The radius
        // is in pixels, so it scales with the texture to stay `blur` points wide.
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur * image.scale])
            .cropped(to: input.extent)

        guard let output = ciContext.createCGImage(blurred, from: input.extent) else { return nil }
        let texture = SKTexture(image: UIImage(cgImage: output, scale: image.scale, orientation: .up))
        texture.filteringMode = .linear

        bloomCache.insert(BloomTexture(texture: texture, size: canvas, center: .zero), forKey: key)

        return BloomTexture(
            texture: texture,
            size: canvas,
            center: CGPoint(x: box.midX, y: box.midY)
        )
    }

    // MARK: - Text bloom

    /// Puts a genuine blurred copy of a label behind itself.
    ///
    /// Labels can't use `addBloom` (they have no path), and duplicating the text
    /// at a larger scale just looks like a drop shadow. Rasterising one blurred
    /// copy costs a single offscreen pass at setup and nothing per frame, so it
    /// is well suited to titles and headings.
    static func addTextBloom(
        to label: SKLabelNode,
        color: UIColor? = nil,
        blur: CGFloat = 12,
        intensity: CGFloat = 0.9
    ) {
        label.childNode(withName: "textBloom")?.removeFromParent()

        let effect = SKEffectNode()
        effect.name = "textBloom"
        effect.shouldRasterize = true
        effect.shouldEnableEffects = true
        effect.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        effect.blendMode = .add
        effect.alpha = intensity
        effect.zPosition = -1

        let copy = SKLabelNode(fontNamed: label.fontName ?? UITheme.Typography.fontBold)
        copy.text = label.text
        copy.fontSize = label.fontSize
        copy.fontColor = color ?? label.fontColor
        copy.horizontalAlignmentMode = label.horizontalAlignmentMode
        copy.verticalAlignmentMode = label.verticalAlignmentMode
        effect.addChild(copy)

        label.addChild(effect)
    }

    /// The view a text bloom has already been rendered through once.
    private static weak var textBloomWarmView: SKView?

    /// Renders a throwaway text bloom through `view`, off screen, once per view.
    ///
    /// The first blurred `SKEffectNode` a renderer meets has CoreImage set up its blur
    /// for it, which can cost a frame. A title screen absorbs that unnoticed, but the
    /// first in-game banner lands mid-fight. The menus and the game all attach the
    /// grade while they set up, with their view at hand, so that is where the cost is
    /// paid instead — by the first menu, long before any banner.
    private static func prewarmTextBloom(in view: SKView) {
        guard textBloomWarmView !== view else { return }
        textBloomWarmView = view
        let label = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        label.text = "0"
        label.fontSize = 28
        addTextBloom(to: label)
        _ = view.texture(from: label)
    }

    /// Uppercase, letter-spaced text. Tracking is the difference between a label
    /// that looks typed and one that looks designed.
    static func trackedText(
        _ text: String,
        font: String,
        size: CGFloat,
        color: UIColor,
        tracking: CGFloat
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont(name: font, size: size) ?? UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
            .kern: tracking
        ])
    }

    // MARK: - Radial glow sprites

    /// A soft round light blob — the workhorse for muzzle flashes, explosion
    /// cores, engine plumes, pickup halos and anything else that is "just light".
    static func radialGlow(
        radius: CGFloat,
        color: UIColor,
        softness: CGFloat = 0.55,
        additive: Bool = true
    ) -> SKSpriteNode {
        let texture = radialTexture(color: color, softness: softness)
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: radius * 2, height: radius * 2))
        if additive { sprite.blendMode = .add }
        return sprite
    }

    private static func radialTexture(color: UIColor, softness: CGFloat) -> SKTexture {
        let key = "\(colorKey(color))|\(Int(softness * 100))"
        if let cached = radialCache.value(forKey: key) { return cached }

        // A falloff with no edges anywhere in it: 128 pixels, stretched to whatever
        // size the glow is drawn at, reads the same as the 384 that 3x would make.
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = softScale(cap: 1)
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let centre = CGPoint(x: side / 2, y: side / 2)

            // A single Gaussian-ish falloff reads flat; stacking a tight bright
            // core over a wide faint skirt is what makes light look hot.
            let stops: [(CGFloat, CGFloat)] = [
                (0.0, 1.0),
                (softness * 0.35, 0.72),
                (softness, 0.28),
                (0.72, 0.08),
                (1.0, 0.0)
            ]
            let colors = stops.map { color.withAlphaComponent($0.1).cgColor } as CFArray
            let locations = stops.map { $0.0 }

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: side / 2,
                    options: []
                )
            }
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        radialCache.insert(texture, forKey: key)
        return texture
    }

    // MARK: - Impact & explosion primitives

    /// Expanding thin ring. Reads as a pressure wave rather than a growing disc.
    ///
    /// Built from light-tube segments (see `LightRing`), so the line keeps the films'
    /// hot-core-in-a-halo profile and stays thin as it travels instead of fattening.
    static func shockwave(
        at position: CGPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        color: UIColor,
        lineWidth: CGFloat = 3,
        duration: TimeInterval = 0.45
    ) -> SKNode {
        let ring = LightRing.wave(from: startRadius, to: endRadius, width: max(1, lineWidth * 0.6),
                                  color: color, duration: duration)
        ring.position = position
        return ring
    }

    /// Directional spark streaks with drag — the cheapest way to sell an impact.
    /// Each one is a single light-tube sprite.
    static func sparks(
        at position: CGPoint,
        count: Int,
        color: UIColor,
        speed: CGFloat,
        spreadAngle: CGFloat = .pi * 2,
        baseAngle: CGFloat = 0,
        length: CGFloat = 7,
        lifetime: TimeInterval = 0.32
    ) -> SKNode {
        let container = SKNode()
        container.position = position

        for _ in 0..<max(0, count) {
            let angle = baseAngle + CGFloat.random(in: -spreadAngle / 2...spreadAngle / 2)
            let velocity = speed * CGFloat.random(in: 0.55...1.0)
            let life = lifetime * Double.random(in: 0.7...1.15)

            let streak = LightSprite.tube(from: CGPoint(x: -length / 2, y: 0), to: CGPoint(x: length / 2, y: 0),
                                          width: 1.3, color: color)
            streak.zRotation = angle

            // Ease-out travel imitates air drag on the debris.
            let travel = SKAction.move(
                by: CGVector(dx: cos(angle) * velocity, dy: sin(angle) * velocity),
                duration: life
            )
            travel.timingMode = .easeOut
            let shrink = SKAction.scaleX(to: 0.25, duration: life)
            let fade = SKAction.fadeOut(withDuration: life)
            fade.timingMode = .easeIn

            streak.run(.sequence([.group([travel, shrink, fade]), .removeFromParent()]))
            container.addChild(streak)
        }

        container.run(.sequence([.wait(forDuration: lifetime * 1.4), .removeFromParent()]))
        return container
    }

    /// A short additive light punch at a point (muzzle flash, hit spark core).
    static func flashPoint(
        at position: CGPoint,
        radius: CGFloat,
        color: UIColor,
        duration: TimeInterval = 0.16,
        growTo: CGFloat = 1.9
    ) -> SKNode {
        let glow = radialGlow(radius: radius, color: color)
        glow.position = position
        let grow = SKAction.scale(to: growTo, duration: duration)
        grow.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: duration)
        glow.run(.sequence([.group([grow, fade]), .removeFromParent()]))
        return glow
    }

    /// Full-screen additive bleach for heavy hits. Kept very short and subtle —
    /// it should register as impact, not as a strobe.
    static func screenFlash(
        in scene: SKScene,
        color: UIColor = .white,
        alpha: CGFloat = 0.16,
        duration: TimeInterval = 0.14
    ) {
        let flash = SKSpriteNode(color: color, size: CGSize(width: scene.size.width * 1.2,
                                                           height: scene.size.height * 1.2))
        flash.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        flash.blendMode = .add
        flash.alpha = 0
        flash.zPosition = 9000
        scene.addChild(flash)

        let inAction = SKAction.fadeAlpha(to: alpha, duration: duration * 0.25)
        let outAction = SKAction.fadeOut(withDuration: duration * 0.75)
        outAction.timingMode = .easeOut
        flash.run(.sequence([inAction, outAction, .removeFromParent()]))
    }

    // MARK: - Screen grade

    /// Vignette + edge cooling, drawn once into a texture.
    ///
    /// Costs one full-screen blended sprite and buys most of the "this was art
    /// directed" impression: it darkens the corners so the bright neon centre
    /// pops, and stops the flat navy background reading as washed out.
    ///
    /// The texture behind it is a thumbnail of the screen, stretched to fit: the
    /// vignette is one smooth gradient, and a full-resolution copy of it held 14 MB
    /// on a large phone and 23 MB on a large iPad for no visible difference.
    static func gradeOverlay(size: CGSize) -> SKSpriteNode {
        let texture = gradeTexture(size: size)
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.name = "screenGrade"
        return sprite
    }

    /// Adds (or re-sizes) the grade overlay on a scene, and the first time a view is
    /// seen here, warms it up for text bloom (see `prewarmTextBloom`).
    /// - Parameter zPosition: Should sit above gameplay entities but below the HUD.
    static func attachGrade(to scene: SKScene, zPosition: CGFloat = 60) {
        scene.childNode(withName: "screenGrade")?.removeFromParent()
        let grade = gradeOverlay(size: scene.size)
        grade.zPosition = zPosition
        scene.addChild(grade)
        if let view = scene.view { prewarmTextBloom(in: view) }
    }

    private static func gradeTexture(size: CGSize) -> SKTexture {
        // The screen's shape at 128 pixels on its long side, so the stretch is the same
        // both ways and the vignette stays round. Keyed by that shape rather than by the
        // exact size, so a resize to the same proportions reuses it.
        let long: CGFloat = 128
        let width = max(size.width, 1), height = max(size.height, 1)
        let canvas = width >= height
            ? CGSize(width: long, height: max(1, (long * height / width).rounded()))
            : CGSize(width: max(1, (long * width / height).rounded()), height: long)
        let key = "grade|\(Int(canvas.width))x\(Int(canvas.height))"
        if let cached = gradeCache.value(forKey: key) { return cached }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            let centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = max(canvas.width, canvas.height) * 0.78

            // Vignette: transparent through the playfield, deep blue-black at
            // the corners. Tinted rather than pure black so it feels like space
            // falling away instead of a dirty lens.
            let edge = UIColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1.0)
            let stops: [(CGFloat, CGFloat)] = [
                (0.0, 0.0),
                (0.45, 0.0),
                (0.68, 0.18),
                (0.85, 0.42),
                (1.0, 0.72)
            ]
            let colors = stops.map { edge.withAlphaComponent($0.1).cgColor } as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: stops.map { $0.0 }
            ) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: radius,
                    options: [.drawsAfterEndLocation]
                )
            }
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        gradeCache.insert(texture, forKey: key)
        return texture
    }

    // MARK: - Keys

    private static func pathKey(_ path: CGPath) -> String {
        var hasher = Hasher()
        path.applyWithBlock { element in
            let type = element.pointee.type
            hasher.combine(type.rawValue)
            let pointCount: Int
            switch type {
            case .moveToPoint, .addLineToPoint: pointCount = 1
            case .addQuadCurveToPoint: pointCount = 2
            case .addCurveToPoint: pointCount = 3
            case .closeSubpath: pointCount = 0
            @unknown default: pointCount = 0
            }
            for i in 0..<pointCount {
                let point = element.pointee.points[i]
                // Quantise so imperceptibly different paths still share a texture.
                hasher.combine(Int((point.x * 4).rounded()))
                hasher.combine(Int((point.y * 4).rounded()))
            }
        }
        return String(hasher.finalize())
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(Int(r * 255))_\(Int(g * 255))_\(Int(b * 255))_\(Int(a * 255))"
    }
}
