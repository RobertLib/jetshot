//
//  GlowHelper.swift
//  jetshot
//
//  Created by Robert Libšanský on 21.10.2025.
//

import SpriteKit

/// Helper class for adding glow effects to sprites without affecting their physics
class GlowHelper {

    /// Adds a glow effect to a shape node
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - intensity: The intensity of the glow (0.0 to 1.0)
    ///   - radius: The radius of the glow blur
    static func addGlow(to node: SKShapeNode, color: UIColor? = nil, intensity: CGFloat = 0.8, radius: CGFloat = 10) {
        // Remove existing glow if present
        node.childNode(withName: "glowEffect")?.removeFromParent()

        // Create a copy of the shape for the glow effect
        let glowNode = SKShapeNode()
        glowNode.path = node.path
        glowNode.name = "glowEffect"
        glowNode.zPosition = -1 // Behind the main node

        // Use provided color or node's fill color
        let glowColor = color ?? node.fillColor
        glowNode.fillColor = glowColor
        glowNode.strokeColor = .clear
        glowNode.lineWidth = 0

        // Add glow effect using SKEffectNode
        let effectNode = SKEffectNode()
        effectNode.shouldRasterize = true
        effectNode.shouldEnableEffects = true
        effectNode.zPosition = -1

        // Create CIFilter for gaussian blur to create glow effect
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        effectNode.filter = filter

        // Adjust alpha for intensity
        glowNode.alpha = intensity

        effectNode.addChild(glowNode)
        node.addChild(effectNode)
    }

    /// Adds a simple glow effect using multiple layers (alternative method for better performance)
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - layers: Number of glow layers (more = stronger glow)
    static func addSimpleGlow(to node: SKShapeNode, color: UIColor? = nil, layers: Int = 3) {
        // Remove existing glow if present
        node.childNode(withName: "simpleGlowEffect")?.removeFromParent()

        let containerNode = SKNode()
        containerNode.name = "simpleGlowEffect"
        containerNode.zPosition = -1

        let glowColor = color ?? node.fillColor

        // Create multiple layers with increasing size and decreasing alpha
        for i in 1...layers {
            let glowNode = SKShapeNode()
            glowNode.path = node.path
            glowNode.fillColor = glowColor
            glowNode.strokeColor = .clear
            glowNode.lineWidth = 0
            glowNode.zPosition = -CGFloat(i)

            // Each layer is slightly larger and more transparent
            let scale = 1.0 + (CGFloat(i) * 0.15)
            let alpha = 0.6 / CGFloat(i)

            glowNode.setScale(scale)
            glowNode.alpha = alpha

            containerNode.addChild(glowNode)
        }

        node.addChild(containerNode)
    }

    /// Adds an enhanced multi-layer neon glow effect (optimized to 3 layers)
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - intensity: Overall intensity multiplier (default 1.0)
    static func addEnhancedGlow(to node: SKShapeNode, color: UIColor? = nil, intensity: CGFloat = 1.0) {
        // Remove existing glow if present
        node.childNode(withName: "enhancedGlow")?.removeFromParent()

        let containerNode = SKNode()
        containerNode.name = "enhancedGlow"
        containerNode.zPosition = -1

        let glowColor = color ?? node.fillColor

        // Optimized to 3 layers instead of 5 for better performance
        // Inner bright core layer
        let innerGlow = SKShapeNode()
        innerGlow.path = node.path
        innerGlow.fillColor = glowColor
        innerGlow.strokeColor = .clear
        innerGlow.lineWidth = 0
        innerGlow.zPosition = -1
        innerGlow.setScale(1.12)
        innerGlow.alpha = 0.4 * intensity
        innerGlow.blendMode = .add
        containerNode.addChild(innerGlow)

        // Middle glow layer
        let middleGlow = SKShapeNode()
        middleGlow.path = node.path
        middleGlow.fillColor = glowColor
        middleGlow.strokeColor = .clear
        middleGlow.lineWidth = 0
        middleGlow.zPosition = -2
        middleGlow.setScale(1.35)
        middleGlow.alpha = 0.25 * intensity
        middleGlow.blendMode = .add
        containerNode.addChild(middleGlow)

        // Outer soft glow layer
        let outerGlow = SKShapeNode()
        outerGlow.path = node.path
        outerGlow.fillColor = glowColor
        outerGlow.strokeColor = .clear
        outerGlow.lineWidth = 0
        outerGlow.zPosition = -3
        outerGlow.setScale(1.6)
        outerGlow.alpha = 0.15 * intensity
        outerGlow.blendMode = .add
        containerNode.addChild(outerGlow)

        node.addChild(containerNode)
    }

    /// Adds a pulsing enhanced glow effect
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - minIntensity: Minimum intensity during pulse (0.0 to 1.0)
    ///   - maxIntensity: Maximum intensity during pulse (0.0 to 1.0)
    ///   - duration: Duration of one pulse cycle
    static func addPulsingEnhancedGlow(to node: SKShapeNode, color: UIColor? = nil, minIntensity: CGFloat = 0.7, maxIntensity: CGFloat = 1.2, duration: TimeInterval = 1.0) {
        addEnhancedGlow(to: node, color: color, intensity: minIntensity)

        guard let glowContainer = node.childNode(withName: "enhancedGlow") else { return }

        // Create pulsing animation with ease in/out for smoother effect
        let pulseUp = SKAction.scale(to: maxIntensity / minIntensity, duration: duration / 2)
        pulseUp.timingMode = .easeInEaseOut
        let pulseDown = SKAction.scale(to: 1.0, duration: duration / 2)
        pulseDown.timingMode = .easeInEaseOut
        let pulse = SKAction.sequence([pulseUp, pulseDown])
        let repeatPulse = SKAction.repeatForever(pulse)

        glowContainer.run(repeatPulse)
    }

    /// Adds an animated pulsing glow effect
    /// - Parameters:
    ///   - node: The shape node to add glow to
    ///   - color: The color of the glow (defaults to the node's fill color)
    ///   - minIntensity: Minimum intensity during pulse (0.0 to 1.0)
    ///   - maxIntensity: Maximum intensity during pulse (0.0 to 1.0)
    ///   - duration: Duration of one pulse cycle
    static func addPulsingGlow(to node: SKShapeNode, color: UIColor? = nil, minIntensity: CGFloat = 0.3, maxIntensity: CGFloat = 0.8, duration: TimeInterval = 1.0) {
        addSimpleGlow(to: node, color: color, layers: 3)

        guard let glowContainer = node.childNode(withName: "simpleGlowEffect") else { return }

        // Create pulsing animation
        let pulseUp = SKAction.fadeAlpha(to: maxIntensity, duration: duration / 2)
        let pulseDown = SKAction.fadeAlpha(to: minIntensity, duration: duration / 2)
        let pulse = SKAction.sequence([pulseUp, pulseDown])
        let repeatPulse = SKAction.repeatForever(pulse)

        glowContainer.alpha = minIntensity
        glowContainer.run(repeatPulse)
    }

    /// Removes glow effect from a node
    /// - Parameter node: The shape node to remove glow from
    static func removeGlow(from node: SKShapeNode) {
        node.childNode(withName: "glowEffect")?.removeFromParent()
        node.childNode(withName: "simpleGlowEffect")?.removeFromParent()
        node.childNode(withName: "enhancedGlow")?.removeFromParent()
    }
}
