//
//  GlowHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 21.10.2025.
//

import SpriteKit

/// Adds glow to shape nodes without affecting their physics.
///
/// This is a thin adapter over `NeonFX`, which renders a real Gaussian falloff
/// into a cached texture. The previous implementation stacked scaled copies of
/// the same path, which produced a hard-edged silhouette around every object and
/// made the whole game read as blurry rather than luminous. Call sites are
/// unchanged; they all inherit the better light for free.
class GlowHelper {

    /// Blur/spread scale with the object so a bullet and a boss both look right.
    private static func lightProfile(for node: SKShapeNode) -> (blur: CGFloat, spread: CGFloat) {
        let box = node.path?.boundingBoxOfPath ?? .zero
        let extent = max(box.width, box.height)
        let blur = min(max(extent * 0.24, 3.5), 18)
        let spread = min(max(extent * 0.055, 1.0), 3.5)
        return (blur, spread)
    }

    /// Adds the standard neon glow used across the game.
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - intensity: Overall intensity multiplier (default 1.0)
    static func addEnhancedGlow(to node: SKShapeNode, color: UIColor? = nil, intensity: CGFloat = 1.0) {
        let profile = lightProfile(for: node)
        NeonFX.addBloom(
            to: node,
            color: color,
            intensity: intensity,
            blur: profile.blur,
            spread: profile.spread,
            name: "enhancedGlow"
        )
    }

    /// Adds a breathing neon glow, for hero elements.
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - minIntensity: Minimum intensity during pulse (0.0 to 1.0)
    ///   - maxIntensity: Maximum intensity during pulse (0.0 to 1.0)
    ///   - duration: Duration of one pulse cycle
    static func addPulsingEnhancedGlow(to node: SKShapeNode, color: UIColor? = nil, minIntensity: CGFloat = 0.7, maxIntensity: CGFloat = 1.2, duration: TimeInterval = 1.0) {
        let profile = lightProfile(for: node)
        // Breathe the halo's size rather than its opacity: a light source that
        // swells reads as energy, one that just dims reads as a flicker bug.
        let ratio = max(minIntensity, 0.1) / max(maxIntensity, 0.2)
        NeonFX.addPulsingBloom(
            to: node,
            color: color,
            intensity: maxIntensity,
            blur: profile.blur,
            spread: profile.spread,
            minScale: max(0.8, ratio),
            maxScale: 1.14,
            duration: duration,
            name: "enhancedGlow"
        )
    }

}
