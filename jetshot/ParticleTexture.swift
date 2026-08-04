//
//  ParticleTexture.swift
//  jetshot
//

import SpriteKit
import UIKit

/// Cached white particle textures for `SKEmitterNode`.
///
/// Every emitter in the game needs the same thing: a plain white circle that the
/// emitter then tints via `particleColor`. Nine separate call sites each rendered
/// their own copy inline, and four of them did it *during gameplay* — a full
/// `UIGraphicsImageRenderer` pass plus `SKTexture` upload on every coin pickup,
/// every bullet absorbed by a vortex, and every meteor/flanker spawn. The results
/// were byte-identical.
///
/// `NeonFX`, `SurfaceFX`, `Player` and `ParallaxBackgroundHelper` already cache
/// their textures; this is the same idea for the plain shapes. Keyed by shape and
/// diameter so the existing `particleScale` values at each call site keep working
/// unchanged.
enum ParticleTexture {

    private static var cache: [String: SKTexture] = [:]

    /// Hard-edged white circle.
    static func solidCircle(diameter: CGFloat) -> SKTexture {
        texture(forKey: "solid-\(diameter)", diameter: diameter) { context, rect in
            UIColor.white.setFill()
            context.fillEllipse(in: rect)
        }
    }

    /// White circle fading linearly to fully transparent at the rim.
    static func softCircle(diameter: CGFloat) -> SKTexture {
        texture(forKey: "soft-\(diameter)", diameter: diameter) { context, rect in
            drawRadialGradient(
                in: context,
                rect: rect,
                colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor],
                locations: [0, 1]
            )
        }
    }

    /// White circle that holds its brightness through the middle before falling
    /// off — a hotter core than `softCircle`, used for engine thrust.
    static func glowCircle(diameter: CGFloat) -> SKTexture {
        texture(forKey: "glow-\(diameter)", diameter: diameter) { context, rect in
            drawRadialGradient(
                in: context,
                rect: rect,
                colors: [
                    UIColor.white.cgColor,
                    UIColor.white.withAlphaComponent(0.5).cgColor,
                    UIColor.clear.cgColor
                ],
                locations: [0, 0.5, 1]
            )
        }
    }

    /// Drops the cache. Called from `GameScene.handleMemoryWarning()` alongside the
    /// other texture caches; the next request re-renders on demand.
    static func clearCache() {
        cache.removeAll()
    }

    // MARK: - Rendering

    private static func texture(
        forKey key: String,
        diameter: CGFloat,
        draw: (CGContext, CGRect) -> Void
    ) -> SKTexture {
        if let cached = cache[key] { return cached }

        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }

        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Centre-out radial gradient clipped to the circle.
    ///
    /// `CGGradient(colorsSpace:colors:locations:)` was force-unwrapped at four call
    /// sites. It only returns nil for a malformed colour/location pair, which these
    /// literals are not — but a crash is a poor way to find that out, and one of
    /// the sites already used `if let` for the identical call. Bailing out leaves a
    /// transparent texture, which costs a barely visible particle rather than the app.
    private static func drawRadialGradient(
        in context: CGContext,
        rect: CGRect,
        colors: [CGColor],
        locations: [CGFloat]
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        ) else { return }

        let centre = CGPoint(x: rect.midX, y: rect.midY)
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        context.drawRadialGradient(
            gradient,
            startCenter: centre,
            startRadius: 0,
            endCenter: centre,
            endRadius: rect.width / 2,
            options: []
        )
        context.restoreGState()
    }
}
