//
//  PerkPickOverlay.swift
//  jetshot
//

import SpriteKit

/// The "choose an upgrade" screen an endless run stops on after each boss.
///
/// Hangs off the scene's HUD layer, which is never paused, so it animates while the
/// gameplay behind it is frozen. Modal: `GameScene.touchesBegan` hands it every tap
/// while it is up, the same arrangement as `SettingsOverlay`.
final class PerkPickOverlay: SKNode {

    static let nodeName = "perkPickOverlay"

    private let perks: [EndlessPerk]
    private let onPick: (EndlessPerk) -> Void
    private var cards: [(node: SKNode, frame: CGRect, perk: EndlessPerk)] = []
    /// Cards that have finished arriving. Only these answer a tap — see `handleTap(at:)`.
    private var arrived: Set<Int> = []
    private var isResolved = false

    /// The overlay's layers, bottom to top. The view sets `ignoresSiblingOrder`, so
    /// nodes that share a z draw in no defined order; these keep the scrim under the
    /// cards, each card's glass under its tint, and the tint under its line art and type.
    private enum Layer {
        static let scrim: CGFloat = -10
        static let content: CGFloat = 0
        static let frame: CGFloat = 10
        // Within a card.
        static let glass: CGFloat = 0
        static let wash: CGFloat = 1
        static let lines: CGFloat = 2
        static let type: CGFloat = 3
        static let lock: CGFloat = 4
        // Within the content: above the scrim with room underneath for the title's
        // bloom, which hangs one step below its lettering.
        static let header: CGFloat = 2
    }

    /// - Parameters:
    ///   - stacks: what the run already holds, for the pips on each card.
    ///   - frameDepths: the letterbox's bars, deep enough to close over the HUD.
    ///   - onPick: called once, after the choice has played out.
    init(
        sceneSize: CGSize,
        perks: [EndlessPerk],
        stacks: [EndlessPerk: Int],
        round: Int,
        frameDepths: (top: CGFloat, bottom: CGFloat) = (60, 60),
        onPick: @escaping (EndlessPerk) -> Void
    ) {
        self.perks = perks
        self.onPick = onPick
        super.init()
        name = Self.nodeName
        zPosition = 3000
        build(size: sceneSize, stacks: stacks, round: round, frameDepths: frameDepths)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Names of the cards in order, for tests and the screenshot harness.
    static func cardName(_ index: Int) -> String { "perkCard_\(index)" }

    /// The card at `index`, in this overlay's coordinates — which are the scene's, since
    /// the overlay sits at the HUD layer's origin.
    func cardCentre(_ index: Int) -> CGPoint? {
        guard cards.indices.contains(index) else { return nil }
        let frame = cards[index].frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Layout

    /// Set as the level card is: the letterbox closes over the frozen run, the title
    /// is tracked gold over a hairline, and the choices are lit frames in the colour of
    /// what they give.
    private func build(size: CGSize, stacks: [EndlessPerk: Int], round: Int, frameDepths depths: (top: CGFloat, bottom: CGFloat)) {
        let scrim = SKSpriteNode(color: .black, size: CGSize(width: size.width + 4, height: size.height + 4))
        scrim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scrim.alpha = 0.7
        scrim.name = "perkScrim"
        scrim.zPosition = Layer.scrim
        addChild(scrim)

        let frame = FilmUI.Letterbox(size: size, top: depths.top, bottom: depths.bottom, accent: StoryPalette.gold)
        frame.zPosition = Layer.frame
        addChild(frame)

        // Title block and cards, centred together in the picture, and drawn larger on a
        // wide screen. Laid out in the content's own points; the card frames kept for
        // hit-testing are converted back into the overlay's.
        let scale = FilmUI.uiScale(for: size)
        let content = SKNode()
        content.position = CGPoint(x: size.width / 2, y: frame.picture.midY)
        content.setScale(scale)
        content.zPosition = Layer.content
        addChild(content)

        let measure = size.width / scale - 40
        let cardWidth = min(measure, 360)
        let cardHeight: CGFloat = 88
        let gap: CGFloat = 12
        let cardsHeight = CGFloat(perks.count) * cardHeight + CGFloat(max(0, perks.count - 1)) * gap

        let title = FilmUI.title(L10n.Perk.title, size: 28, color: UITheme.Colors.primaryGold,
                                 glow: StoryPalette.gold, tracking: 5, maxWidth: measure, minimumSize: 16)
        let subtitle = Cinematic.typewriter(L10n.Perk.subtitle(round: round), fontSize: 12, color: StoryPalette.cyan,
                                            tracking: 2.5, delay: 0.15, duration: 0.5, maxWidth: measure)

        let headerHeight: CGFloat = 14 + 14 + title.frame.height + 14 + 1
        let blockHeight = headerHeight + 30 + cardsHeight
        var y = blockHeight / 2

        y -= 7
        subtitle.position = CGPoint(x: 0, y: y)
        subtitle.zPosition = Layer.header
        content.addChild(subtitle)
        y -= 7 + 14 + title.frame.height / 2
        title.position = CGPoint(x: 0, y: y)
        title.zPosition = Layer.header
        content.addChild(title)
        y -= title.frame.height / 2 + 14
        let rule = FilmUI.drawnRule(width: min(cardWidth, 240), color: UITheme.Colors.primaryGold, alpha: 0.7, delay: 0.1)
        rule.position = CGPoint(x: 0, y: y)
        rule.zPosition = Layer.header
        content.addChild(rule)
        y -= 30

        for (index, perk) in perks.enumerated() {
            let centre = CGPoint(x: 0, y: y - cardHeight / 2)
            y -= cardHeight + gap
            let card = makeCard(perk: perk, width: cardWidth, height: cardHeight, held: stacks[perk] ?? 0)
            card.name = Self.cardName(index)
            card.position = centre
            content.addChild(card)

            let onScreen = CGPoint(x: content.position.x + centre.x * scale, y: content.position.y + centre.y * scale)
            let frame = CGRect(x: onScreen.x - cardWidth * scale / 2, y: onScreen.y - cardHeight * scale / 2,
                               width: cardWidth * scale, height: cardHeight * scale)
            cards.append((card, frame, perk))

            // Slide in from the right, one after another — and only once a card has
            // landed does it answer a tap.
            card.alpha = 0
            card.position.x += 40
            let arrive = SKAction.moveBy(x: -40, y: 0, duration: 0.25)
            arrive.timingMode = .easeOut
            card.run(.sequence([
                .wait(forDuration: 0.15 + Double(index) * 0.08),
                .group([.fadeIn(withDuration: 0.22), arrive]),
                .run { [weak self] in self?.arrived.insert(index) }
            ]))
        }

        alpha = 0
        run(.fadeIn(withDuration: 0.15))
    }

    private func makeCard(perk: EndlessPerk, width: CGFloat, height: CGFloat, held: Int) -> SKNode {
        let accent = Self.accent(for: perk)
        let card = SKNode()
        let size = CGSize(width: width, height: height)

        let glass = SKSpriteNode(color: FilmUI.glass, size: size)
        glass.alpha = 0.88
        glass.name = "perkGlass"
        glass.zPosition = Layer.glass
        card.addChild(glass)
        let wash = SKSpriteNode(color: accent, size: size)
        wash.alpha = 0.06
        wash.name = "perkWash"
        wash.zPosition = Layer.wash
        card.addChild(wash)

        let panel = SKShapeNode(rectOf: size)
        panel.fillColor = .clear
        panel.strokeColor = accent.withAlphaComponent(0.3)
        panel.lineWidth = 1
        panel.name = "perkPanel"
        panel.zPosition = Layer.lines
        card.addChild(panel)
        for tube in FilmUI.addBrackets(to: card, size: size, arm: 12, color: accent, width: 1.4) {
            tube.zPosition = Layer.lines
        }

        // The perk's glyph in a ring of its light, on the left.
        let iconX = -width / 2 + 42
        let ring = LightSprite.ring(radius: 22, color: accent)
        ring.position = CGPoint(x: iconX, y: 0)
        ring.alpha = 0.85
        ring.zPosition = Layer.lines
        card.addChild(ring)

        let icon = SKShapeNode(path: Self.iconPath(for: perk, radius: 11))
        icon.strokeColor = StoryPalette.mix(accent, .white, 0.6)
        icon.fillColor = .clear
        icon.lineWidth = 2
        icon.lineCap = .round
        icon.lineJoin = .round
        icon.position = ring.position
        icon.zPosition = Layer.type
        card.addChild(icon)

        let textX = iconX + 40
        let textWidth = width / 2 - textX - 14
        let pipsWidth: CGFloat = perk.maxStacks > 1 ? CGFloat(perk.maxStacks) * 10 + 6 : 0

        let nameLabel = FilmUI.label(L10n.Perk.name(perk), size: 18, color: StoryPalette.mix(accent, .white, 0.3),
                                     tracking: 2, maxWidth: textWidth - pipsWidth, minimumSize: 12)
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.position = CGPoint(x: textX, y: 17)
        nameLabel.zPosition = Layer.type
        card.addChild(nameLabel)

        let detail = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        detail.text = L10n.Perk.detail(perk)
        detail.fontSize = 14
        detail.fontColor = UITheme.Colors.textBody
        detail.horizontalAlignmentMode = .left
        detail.verticalAlignmentMode = .top
        detail.numberOfLines = 2
        detail.preferredMaxLayoutWidth = textWidth
        detail.position = CGPoint(x: textX, y: 5)
        detail.zPosition = Layer.type
        card.addChild(detail)

        // How many of this perk the run will hold after taking it, out of its cap: a
        // segment per stack, lit for those held, blinking for the one this card gives.
        if perk.maxStacks > 1 {
            let pitch: CGFloat = 10
            for i in 0..<perk.maxStacks {
                let left = width / 2 - 16 - CGFloat(perk.maxStacks - i) * pitch + 2
                let filled = i < held
                let gaining = i == held
                let segment = FilmUI.tube(CGPoint(x: left, y: 17), CGPoint(x: left + pitch - 4, y: 17),
                                          width: 1.6, color: gaining ? .white : accent)
                segment.alpha = filled ? 1 : (gaining ? 1 : 0.22)
                segment.zPosition = Layer.type
                card.addChild(segment)
                if gaining {
                    segment.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)])))
                }
            }
        }
        return card
    }

    // MARK: - Input

    /// Handles a tap at a scene-space `location`. Taps outside every card are swallowed:
    /// the overlay is modal, and a stray tap must not fall through to the paused game.
    ///
    /// So is a tap on a card still on its way in. The picker goes up the instant the boss
    /// falls, while the player's thumb is busy flying, and the frames it hit-tests are
    /// fixed before a card has drawn a single pixel — so a finger re-gripping the glass
    /// in the first few tenths of a second used to take a perk nobody had seen.
    func handleTap(at location: CGPoint) {
        guard !isResolved else { return }
        guard let index = cards.firstIndex(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(location) }),
              arrived.contains(index) else { return }
        pick(index)
    }

    /// Chooses the card at `index`, as a tap on it would.
    func pick(_ index: Int) {
        guard !isResolved, cards.indices.contains(index) else { return }
        isResolved = true

        let chosen = cards[index]
        HapticManager.shared.success()
        if let scene = scene { SoundManager.shared.playPowerUpSound(on: scene) }

        for (i, card) in cards.enumerated() where i != index {
            card.node.run(.fadeAlpha(to: 0.15, duration: 0.15))
        }
        // The chosen frame flashes and its brackets lock on.
        if let wash = chosen.node.childNode(withName: "perkWash") {
            wash.run(.sequence([.fadeAlpha(to: 0.4, duration: 0.06), .fadeAlpha(to: 0.1, duration: 0.3)]))
        }
        let lock = SKNode()
        // The frame is kept in the overlay's points; the card is drawn in its scaled
        // container's.
        let scale = chosen.node.parent?.xScale ?? 1
        FilmUI.addBrackets(to: lock, size: CGSize(width: chosen.frame.width / scale + 10,
                                                  height: chosen.frame.height / scale + 10),
                           arm: 16, color: .white, width: 1.6)
        lock.setScale(1.12)
        lock.alpha = 0
        lock.zPosition = Layer.lock
        let close = SKAction.scale(to: 1, duration: 0.18)
        close.timingMode = .easeOut
        lock.run(.group([.fadeIn(withDuration: 0.08), close]))
        chosen.node.addChild(lock)
        chosen.node.run(.sequence([
            .scale(to: 1.04, duration: 0.08),
            .scale(to: 1.0, duration: 0.14)
        ]))

        let perk = chosen.perk
        run(.sequence([
            .wait(forDuration: 0.4),
            .fadeOut(withDuration: 0.18),
            .run { [weak self] in
                guard let self = self else { return }
                self.removeFromParent()
                self.onPick(perk)
            }
        ]))
    }

    // MARK: - Art

    static func accent(for perk: EndlessPerk) -> UIColor {
        switch perk {
        case .fireRate: return UIColor(red: 0.3, green: 1.0, blue: 0.9, alpha: 1)
        case .coolant: return UIColor(red: 0.55, green: 0.8, blue: 1.0, alpha: 1)
        case .capacitor: return ShardSystem.color
        case .longOverdrive: return ProjectileFX.overdriveBolt
        case .daredevil: return UIColor(red: 1.0, green: 0.62, blue: 0.82, alpha: 1)
        case .chainKeeper: return UIColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1)
        case .armor: return UIColor(red: 0.45, green: 1.0, blue: 0.55, alpha: 1)
        case .arsenal: return UIColor(red: 1.0, green: 0.6, blue: 0.25, alpha: 1)
        case .roundShield: return UIColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1)
        case .magnet: return UIColor(red: 1.0, green: 0.86, blue: 0.3, alpha: 1)
        }
    }

    /// A line-art glyph for each perk, centred on the origin within `radius`.
    static func iconPath(for perk: EndlessPerk, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch perk {
        case .fireRate:
            for x in [-r * 0.6, 0, r * 0.6] {
                path.move(to: CGPoint(x: x, y: -r * 0.8))
                path.addLine(to: CGPoint(x: x, y: r * 0.8))
            }
        case .coolant:
            for i in 0..<3 {
                let a = CGFloat(i) * .pi / 3
                path.move(to: CGPoint(x: cos(a) * r, y: sin(a) * r))
                path.addLine(to: CGPoint(x: -cos(a) * r, y: -sin(a) * r))
            }
        case .capacitor, .longOverdrive:
            for offset in [-r * 0.35, r * 0.35] {
                path.move(to: CGPoint(x: -r * 0.7, y: offset - r * 0.3))
                path.addLine(to: CGPoint(x: 0, y: offset + r * 0.3))
                path.addLine(to: CGPoint(x: r * 0.7, y: offset - r * 0.3))
            }
            if perk == .longOverdrive {
                path.move(to: CGPoint(x: -r, y: -r * 0.95))
                path.addLine(to: CGPoint(x: r, y: -r * 0.95))
            }
        case .daredevil:
            path.addEllipse(in: CGRect(x: -r * 0.25, y: -r * 0.25, width: r * 0.5, height: r * 0.5))
            path.addArc(center: .zero, radius: r * 0.85, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            path.move(to: CGPoint(x: cos(.pi * 1.15) * r * 0.85, y: sin(.pi * 1.15) * r * 0.85))
            path.addArc(center: .zero, radius: r * 0.85, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        case .chainKeeper:
            path.addEllipse(in: CGRect(x: -r, y: -r * 0.4, width: r * 1.2, height: r * 0.8))
            path.addEllipse(in: CGRect(x: -r * 0.2, y: -r * 0.4, width: r * 1.2, height: r * 0.8))
        case .armor:
            path.move(to: CGPoint(x: 0, y: -r * 0.8))
            path.addLine(to: CGPoint(x: 0, y: r * 0.8))
            path.move(to: CGPoint(x: -r * 0.8, y: 0))
            path.addLine(to: CGPoint(x: r * 0.8, y: 0))
        case .arsenal:
            for a in [-0.45, 0, 0.45] as [CGFloat] {
                path.move(to: CGPoint(x: 0, y: -r * 0.8))
                path.addLine(to: CGPoint(x: sin(a) * r * 1.1, y: -r * 0.8 + cos(a) * r * 1.7))
            }
        case .roundShield:
            for i in 0...6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 6
                let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        case .magnet:
            path.move(to: CGPoint(x: -r * 0.7, y: r * 0.8))
            path.addLine(to: CGPoint(x: -r * 0.7, y: -r * 0.1))
            path.addArc(center: CGPoint(x: 0, y: -r * 0.1), radius: r * 0.7,
                        startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: r * 0.7, y: r * 0.8))
        }
        return path
    }
}
