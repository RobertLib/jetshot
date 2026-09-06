//
//  LevelCompleteScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class LevelCompleteScene: SKScene {

    /// Shared vertical rhythm for the results panels. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    /// How far the figure block rises during its entrance. It starts this far below
    /// its laid-out position and ends exactly on it.
    private static let figuresRise: CGFloat = 10

    private let level: Int
    private let score: Int
    private let coinsCollected: Int
    private let totalCoins: Int
    private let bulletCount: Int
    private let sideMissileCount: Int
    private let bestChain: Int
    private var isInitialized = false

    /// This level's stored best score as it stood *before* this run was recorded, and
    /// whether the run beat it.
    ///
    /// Both are captured in `didMove(to:)` ahead of `completeLevel`, which is the call
    /// that writes the new best. Reading the store afterwards would compare the run
    /// against itself and could never report a record.
    private var previousBest: Int = 0
    private var isNewBest: Bool = false

    /// Computed once and reused. `calculateStarsEarned()` was previously called both
    /// here-equivalent (didMove, to persist progress) and again in createStarRating(),
    /// so the rating was derived twice per scene — and once more on every resize, each
    /// time re-logging the result in debug builds.
    private lazy var starsEarned: Int = calculateStarsEarned()

    init(size: CGSize, level: Int, score: Int, coinsCollected: Int = 0, totalCoins: Int = 0, bulletCount: Int = 1, sideMissileCount: Int = 0, bestChain: Int = 0) {
        self.level = level
        self.score = score
        self.coinsCollected = coinsCollected
        self.totalCoins = totalCoins
        self.bulletCount = bulletCount
        self.sideMissileCount = sideMissileCount
        self.bestChain = bestChain
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        // Read the standing record before `completeLevel` replaces it. See `previousBest`.
        previousBest = LevelManager.shared.getLevelScore(level: level) ?? 0
        isNewBest = previousBest > 0 && score > previousBest

        // Mark level as completed with score, stars, and weapon arsenal
        LevelManager.shared.completeLevel(level, score: score, stars: starsEarned, bulletCount: bulletCount, sideMissileCount: sideMissileCount)

        // Add starfield first (lightweight)
        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        NeonFX.attachGrade(to: self, zPosition: -5)
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))

        // Setup UI immediately
        setupUI()

        // Mark as initialized after scene setup completes using SKAction
        let wait = SKAction.wait(forDuration: 0.1)
        let initialize = SKAction.run { [weak self] in
            self?.isInitialized = true
        }
        run(SKAction.sequence([wait, initialize]))

        // Continue background music
        SoundManager.shared.resumeMusic()
    }

    private func calculateStarsEarned() -> Int {
        let stars = StarRating.stars(coinsCollected: coinsCollected, totalCoins: totalCoins)

        #if DEBUG
        if totalCoins > 0 {
            let percentage = Int(Double(coinsCollected) / Double(totalCoins) * 100)
            print("🌟 Level \(level): collected \(coinsCollected)/\(totalCoins) coins (\(percentage)%) → \(stars) stars")
        } else {
            print("🌟 Level \(level): no coins in level → \(stars) stars")
        }
        #endif

        return stars
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Only handle resize after initial setup
        guard isInitialized else { return }

        // Remove and recreate all elements
        removeAllChildren()

        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        NeonFX.attachGrade(to: self, zPosition: -5)
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupUI()
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
    }

    private func setupUI() {
        // Add golden success particles in background
        addSuccessParticles()

        // Main panel background with rounded corners and golden glow
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)

        // Measured before the panel exists, so the panel is sized to its content rather
        // than to a number picked by eye — see `UITheme.PanelStack`, and `GameOverScene`,
        // which is the same layout and used to carry the same hand-tuned offsets.
        let starsHeight = UITheme.Dimensions.starOuterRadius * 2

        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = L10n.LevelComplete.title
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.primaryGold
        title.horizontalAlignmentMode = .center
        let titleHeight = UITheme.capBandHeight(of: title)

        let figures = createScoreDisplay()
        let buttonHeight = UITheme.Dimensions.buttonHeight

        var stack = UITheme.PanelStack()
        stack.add(gapAbove: Rhythm.edge, height: starsHeight)
        stack.add(gapAbove: Rhythm.emblemToTitle, height: titleHeight)
        stack.add(gapAbove: Rhythm.aroundFigures, height: figures.height)
        stack.add(gapAbove: Rhythm.aroundFigures, height: buttonHeight)
        stack.add(gapAbove: Rhythm.buttonRow, height: buttonHeight)

        let panelHeight = stack.height
        let panel = UITheme.createPanel(
            width: panelWidth,
            height: panelHeight,
            borderColor: UITheme.Colors.primaryGold
        )
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer golden glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.6)
            glowPanel.lineWidth = UITheme.Dimensions.lineWidthGlowStrong
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.4, duration: UITheme.Animations.durationGlowPulse),
                    SKAction.fadeAlpha(to: 0.8, duration: UITheme.Animations.durationGlowPulse)
                ]))
            ]))
        }

        addChild(panel)

        // Animate panel entrance
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: UITheme.Animations.durationQuick),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationMedium)
            ])
        ]))
        panel.setScale(0.8)

        // Placement pass, walking the same rows back down from the panel's top edge.
        stack.start(panelHeight: panelHeight)

        // Stars decoration at top
        createStarRating(on: panel, y: stack.next(gapAbove: Rhythm.edge, height: starsHeight))

        // "LEVEL COMPLETE" title - clean and simple
        UITheme.centerOnCapBand(
            title,
            centerY: stack.next(gapAbove: Rhythm.emblemToTitle, height: titleHeight)
        )
        title.alpha = 0
        panel.addChild(title)

        // Animated title entrance
        title.run(SKAction.sequence([
            SKAction.wait(forDuration: UITheme.Animations.durationSlow),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: UITheme.Animations.durationQuick),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
                ])
            ])
        ]))

        // Score display with icon
        let scoreContainer = figures.node
        scoreContainer.position = CGPoint(
            x: 0,
            y: stack.next(gapAbove: Rhythm.aroundFigures, height: figures.height)
        )
        // The entrance rises *into* the slot rather than out of it. `moveBy` is
        // relative and permanent, so running it from the laid-out position left the
        // block sitting 10pt above where the stack put it for the rest of the scene's
        // life — which is what tipped the figures off centre between the title and the
        // button. Starting the same 10pt low makes the animation land on the layout.
        scoreContainer.position.y -= Self.figuresRise
        scoreContainer.alpha = 0
        panel.addChild(scoreContainer)
        scoreContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: Self.figuresRise, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons
        setupButtons(
            on: panel,
            primaryY: stack.next(gapAbove: Rhythm.aroundFigures, height: buttonHeight),
            secondaryY: stack.next(gapAbove: Rhythm.buttonRow, height: buttonHeight)
        )

        // Celebration particles
        createCelebrationParticles()
    }

    private func createStarRating(on panel: SKShapeNode, y: CGFloat) {
        let starSpacing = UITheme.Dimensions.spacingMedium
        for i in 0..<3 {
            let starContainer = SKNode()
            starContainer.position = CGPoint(x: CGFloat(i - 1) * starSpacing, y: y)
            panel.addChild(starContainer)

            // Determine if this star should be filled
            let isEarned = i < starsEarned

            // Halo behind the star. Additive on purpose: the old opaque yellow
            // star scaled up behind the real one produced a dark olive fringe
            // that made the whole rating look muddy.
            let glowStar = NeonFX.radialGlow(
                radius: UITheme.Dimensions.starOuterRadius * 1.9,
                color: UIColor(red: 1.0, green: 0.82, blue: 0.28, alpha: 1.0)
            )
            glowStar.alpha = 0
            glowStar.zPosition = -1
            starContainer.addChild(glowStar)

            // Main star
            let star = UITheme.createStar()
            if isEarned {
                // Filled gold star for earned
                star.fillColor = UITheme.Colors.primaryGold
                star.strokeColor = UIColor(red: 1.0, green: 0.98, blue: 0.78, alpha: 1.0)
            } else {
                // Empty gray star for not earned
                star.fillColor = UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.5)
                star.strokeColor = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.8)
            }
            star.lineWidth = UITheme.Dimensions.lineWidthRegular
            star.setScale(0)
            star.zPosition = 2
            starContainer.addChild(star)

            // Pop-in animation with delay
            let popAnimation = SKAction.sequence([
                SKAction.wait(forDuration: UITheme.Animations.durationNormal + Double(i) * 0.15),
                SKAction.group([
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationNormal),
                    SKAction.sequence([
                        SKAction.rotate(byAngle: .pi / 4, duration: 0.15),
                        SKAction.rotate(byAngle: -.pi / 4, duration: 0.15)
                    ])
                ])
            ])
            star.run(popAnimation)

            // Glow pulse animation (only for earned stars)
            if isEarned {
                glowStar.run(SKAction.sequence([
                    SKAction.wait(forDuration: UITheme.Animations.durationNormal + Double(i) * 0.15),
                    SKAction.fadeAlpha(to: 0.6, duration: UITheme.Animations.durationNormal),
                    SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: UITheme.Animations.alphaFadedLow, duration: UITheme.Animations.durationGlowPulse),
                        SKAction.fadeAlpha(to: UITheme.Animations.alphaFadedHigh, duration: UITheme.Animations.durationGlowPulse)
                    ]))
                ]))
            }


            // Add sparkle particles around stars - now with fixed texture
            let sparkle = SKEmitterNode()

            sparkle.particleTexture = ParticleTexture.solidCircle(diameter: 24)

            sparkle.particleBirthRate = 5 // More sparkles
            sparkle.particleLifetime = 1.5
            // Emitted in a ring outside the star, not over its face — big
            // sparkles on top of the star were what blurred the gold shape.
            sparkle.particlePositionRange = CGVector(dx: 42, dy: 42)
            sparkle.particleSpeed = 15
            sparkle.particleSpeedRange = 10
            sparkle.emissionAngleRange = .pi * 2
            sparkle.particleAlpha = 0.9
            sparkle.particleAlphaSpeed = -0.7
            sparkle.particleScale = 0.16
            sparkle.particleScaleSpeed = -0.1
            sparkle.particleColor = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            sparkle.particleColorBlendFactor = 1.0
            sparkle.particleBlendMode = .add
            sparkle.alpha = 0
            sparkle.zPosition = 1
            starContainer.addChild(sparkle)

            sparkle.run(SKAction.sequence([
                SKAction.wait(forDuration: UITheme.Animations.durationSlow + Double(i) * 0.15),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationQuick)
            ]))
        }
    }

    /// The figures under the title, spaced by `UITheme.PanelRhythm` and centred on the
    /// returned node's origin, with the optical height the outer stack needs.
    private func createScoreDisplay() -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        // Score label
        let scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.text = L10n.Common.score
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textSecondary

        // Score value
        let scoreValue = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreValue.horizontalAlignmentMode = .center
        scoreValue.text = "\(score)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGoldLight

        // The caption rides tight against the number it labels; the lines below are
        // separate figures and get the wider gap.
        var rows: [(label: SKLabelNode, gapAbove: CGFloat)] = [
            (scoreLabel, 0),
            (scoreValue, Rhythm.captionToValue)
        ]

        // The record line. A cleared level used to report a bare number with nothing to
        // compare it against, so there was no reason to replay one and no way to tell a
        // great run from a scraped-through one. Beating the stored best is now called
        // out; falling short of it prints the target instead, which is the same hook
        // from the other side.
        let recordLine = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        recordLine.horizontalAlignmentMode = .center
        recordLine.fontSize = 15

        if isNewBest {
            recordLine.text = L10n.LevelComplete.newBest(improvement: score - previousBest)
            recordLine.fontColor = UITheme.Colors.successGreenLight
            recordLine.run(.repeatForever(.sequence([
                .scale(to: 1.08, duration: 0.5),
                .scale(to: 1.0, duration: 0.5)
            ])))
        } else if previousBest > 0 {
            recordLine.text = L10n.Common.best(previousBest)
            recordLine.fontColor = UITheme.Colors.textSecondary
        } else {
            recordLine.text = L10n.LevelComplete.personalBestSet
            recordLine.fontColor = UITheme.Colors.successGreenLight
        }
        rows.append((recordLine, Rhythm.figureLine))

        // Best chain of the run, when there was one worth reporting. This is the only
        // place the chain's peak is shown after the meter itself disappears, and it is
        // the number a player who wants a higher score has to attack next time.
        if bestChain >= ComboRules.tiers[0].chain {
            let chainLine = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
            chainLine.horizontalAlignmentMode = .center
            chainLine.fontSize = 14
            chainLine.text = L10n.LevelComplete.bestChain(
                length: bestChain,
                multiplier: ComboRules.multiplier(forChain: bestChain)
            )
            chainLine.fontColor = ComboSystem.tierColor(
                forMultiplier: ComboRules.multiplier(forChain: bestChain)
            )
            rows.append((chainLine, Rhythm.figureLine))
        }

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime.
        container.name = "figureBlock"

        let height = UITheme.stackLabels(rows, in: container)
        return (container, height)
    }

    private func setupButtons(on panel: SKShapeNode, primaryY: CGFloat, secondaryY: CGFloat) {
        let buttonY = primaryY

        // Check if this is the last level
        let isLastLevel = level >= LevelManager.shared.totalLevels

        // Next level button (if not last level) - highlighted as primary action
        if !isLastLevel {
            let nextButton = UITheme.createButton(
                text: L10n.LevelComplete.next,
                color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0),
                width: UITheme.Dimensions.buttonWidthXLarge,
                name: "nextButton"
            )
            nextButton.position = CGPoint(x: 0, y: buttonY)
            nextButton.alpha = 0
            panel.addChild(nextButton)

            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.1),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
            ]))

            // Add subtle pulse to next button
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: UITheme.Animations.durationButtonPulse),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationButtonPulse)
            ])
            nextButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.repeatForever(pulse)
            ]))
        } else {
            // If last level, show "Continue to Victory" button
            let victoryButton = UITheme.createButton(
                text: L10n.LevelComplete.continue,
                color: UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0), // Golden color
                width: UITheme.Dimensions.buttonWidthXLarge,
                name: "victoryButton"
            )
            victoryButton.position = CGPoint(x: 0, y: buttonY)
            victoryButton.alpha = 0
            panel.addChild(victoryButton)

            victoryButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.1),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
            ]))

            // Add golden pulse to victory button
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: UITheme.Animations.durationButtonPulse),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationButtonPulse)
            ])
            victoryButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.repeatForever(pulse)
            ]))
        }

        // Secondary buttons container
        let secondaryButtonY = secondaryY

        let levelsButton = UITheme.createButton(
            text: L10n.Common.levels,
            color: UITheme.Colors.buttonLevels,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "levelsButton"
        )
        levelsButton.position = CGPoint(x: -67, y: secondaryButtonY)
        levelsButton.alpha = 0
        panel.addChild(levelsButton)

        let menuButton = UITheme.createButton(
            text: L10n.Common.menu,
            color: UITheme.Colors.buttonMenu,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: "menuButton"
        )
        menuButton.position = CGPoint(x: 67, y: secondaryButtonY)
        menuButton.alpha = 0
        panel.addChild(menuButton)

        levelsButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))
    }

    private func createCelebrationParticles() {
        // Create confetti-like particles (reduced for better performance)
        for _ in 0..<12 {  // Reduced from 20
            let particle = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 2)
            let colors: [UIColor] = [.red, .yellow, .green, .cyan, .magenta]
            particle.fillColor = colors.randomElement() ?? .yellow
            particle.strokeColor = .clear
            particle.position = CGPoint(x: size.width / 2, y: size.height - 100)
            particle.zPosition = 10
            addChild(particle)

            let randomX = CGFloat.random(in: -150...150)
            let randomY = CGFloat.random(in: -200...100)
            let duration = Double.random(in: 1.0...2.0)

            let move = SKAction.moveBy(x: randomX, y: randomY, duration: duration)
            let rotate = SKAction.rotate(byAngle: .pi * 4, duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)

            particle.run(SKAction.group([move, rotate, fade])) {
                particle.removeFromParent()
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "nextButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleNextButton()
            case "victoryButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleVictoryButton()
            case "levelsButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleLevelsButton()
            case "menuButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleMenuButton()
            default:
                break
            }
        }
    }

    private func handleNextButton() {
        // Button press animation
        if let nextButton = childNode(withName: "//nextButton") as? SKShapeNode {
            nextButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.startNextLevel()
            })
        }
    }

    private func handleVictoryButton() {
        // Button press animation
        if let victoryButton = childNode(withName: "//victoryButton") as? SKShapeNode {
            victoryButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.showGameCompletion()
            })
        }
    }

    private func handleLevelsButton() {
        // Button press animation
        if let levelsButton = childNode(withName: "//levelsButton") as? SKShapeNode {
            levelsButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToLevelSelect()
            })
        }
    }

    private func handleMenuButton() {
        // Button press animation
        if let menuButton = childNode(withName: "//menuButton") as? SKShapeNode {
            menuButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToMenu()
            })
        }
    }

    private func startNextLevel() {
        guard let view = view else { return }
        let nextLevel = level + 1
        if nextLevel <= LevelManager.shared.totalLevels {
            let gameScene = GameScene(size: view.bounds.size)
            gameScene.scaleMode = scaleMode
            gameScene.currentLevel = nextLevel

            // Load weapon arsenal from previous level (current completed level)
            let weapons = LevelManager.shared.getLevelWeapons(level: level)
            gameScene.startingBulletCount = weapons.bulletCount
            gameScene.startingSideMissileCount = weapons.sideMissileCount

            let transition = SKTransition.fade(withDuration: 0.5)
            view.presentScene(gameScene, transition: transition)
        }
    }

    /// Finishing the last level runs the ending crawl, which then hands off to
    /// `GameCompletionScene`.
    ///
    /// This used to present `GameCompletionScene` directly, but that scene's
    /// `didMove(to:)` forwarded straight on to the crawl without ever building itself —
    /// so the victory screen was skipped entirely. Going through `StoryScene` first
    /// keeps the same order the player saw (crawl, then payoff) and makes the payoff
    /// actually appear. It reads its own total from `LevelManager`, which is where the
    /// value came from anyway.
    private func showGameCompletion() {
        guard let view = view else { return }
        let storyScene = StoryScene(size: view.bounds.size, type: .ending)
        storyScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 1.0)
        view.presentScene(storyScene, transition: transition)
    }

    private func goToLevelSelect() {
        guard let view = view else { return }
        let levelSelectScene = LevelSelectScene(size: view.bounds.size, startLevel: level)
        levelSelectScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(levelSelectScene, transition: transition)
    }

    private func goToMenu() {
        guard let view = view else { return }
        let menuScene = MenuScene(size: view.bounds.size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(menuScene, transition: transition)
    }

    // MARK: - Visual Effects

    private func addSuccessParticles() {
        // Golden fire effect from bottom
        let particles = SKEmitterNode()

        particles.particleTexture = ParticleTexture.softCircle(diameter: 32)

        // Golden fire color sequence: white-hot -> bright yellow -> golden -> orange -> dark
        let colorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0),   // Hot white
            UIColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0),  // Bright yellow
            UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),  // Golden
            UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.8),   // Orange
            UIColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 0.0)    // Dark fade
        ], times: [0, 0.2, 0.4, 0.7, 1.0])
        particles.particleColorSequence = colorSequence

        particles.particleBirthRate = 30  // Reduced from 50
        particles.particleLifetime = 2.0  // Reduced from 2.5
        particles.particleLifetimeRange = 0.8  // Reduced from 1.0
        particles.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 10)
        particles.particleSpeed = 80
        particles.particleSpeedRange = 40
        particles.emissionAngle = .pi / 2  // Upward
        particles.emissionAngleRange = .pi / 6
        particles.particleAlpha = 0.8
        particles.particleAlphaSpeed = -0.3
        particles.particleScale = 0.4
        particles.particleScaleRange = 0.3
        particles.particleScaleSpeed = -0.1
        particles.particleRotation = 0
        particles.particleRotationSpeed = 3.0
        particles.particleBlendMode = .add
        particles.yAcceleration = 20
        particles.xAcceleration = 0
        particles.particleColorBlendFactor = 1.0
        particles.position = CGPoint(x: size.width / 2, y: -20)
        particles.zPosition = -1
        particles.name = "successParticles"

        addChild(particles)
    }
}
