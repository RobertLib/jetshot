//
//  GameOverScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class GameOverScene: SKScene {

    /// Shared vertical rhythm for the results panels. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    /// How far the figure block rises during its entrance. It starts this far below
    /// its laid-out position and ends exactly on it.
    private static let figuresRise: CGFloat = 10

    private let finalScore: Int
    private let currentLevel: Int
    private let isEndless: Bool
    private let endlessRound: Int
    /// Whether this run beat the stored endless best. Decided by `GameScene.gameOver()`,
    /// which records the run — by the time this scene exists the store already holds the
    /// new figure, so comparing here would compare the run against itself.
    private let isEndlessRecord: Bool
    private var isInitialized = false

    init(
        size: CGSize,
        score: Int,
        level: Int = 1,
        isEndless: Bool = false,
        endlessRound: Int = 0,
        isEndlessRecord: Bool = false
    ) {
        self.finalScore = score
        self.currentLevel = level
        self.isEndless = isEndless
        self.endlessRound = endlessRound
        self.isEndlessRecord = isEndlessRecord
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        NeonFX.attachGrade(to: self, zPosition: -5)
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupUI()
        isInitialized = true

        // Continue background music
        SoundManager.shared.resumeMusic()
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
        // Add red warning particles in background
        addWarningParticles()

        // Main panel background with rounded corners and glow
        let panelWidth: CGFloat = min(size.width - 60, UITheme.Dimensions.panelWidthMax)

        // Content is built and measured *before* the panel, because the panel is sized
        // to hold it. The fixed 420/460 heights this replaces were tuned by eye and left
        // ~40pt of dead space above the icon and ~35pt below the buttons, while the
        // figures underneath the score sat on a tighter pitch than anything around them.
        // See `UITheme.PanelStack`.
        let defeatIcon = createDefeatIcon()
        defeatIcon.setScale(0.8) // Make it smaller
        let iconHeight = defeatIcon.calculateAccumulatedFrame().height

        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = L10n.GameOver.title
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.dangerRed
        title.horizontalAlignmentMode = .center
        let titleHeight = UITheme.capBandHeight(of: title)

        let figures = createScoreDisplay()
        let buttonHeight = UITheme.Dimensions.buttonHeight

        var stack = UITheme.PanelStack()
        stack.add(gapAbove: Rhythm.edge, height: iconHeight)
        stack.add(gapAbove: Rhythm.emblemToTitle, height: titleHeight)
        stack.add(gapAbove: Rhythm.aroundFigures, height: figures.height)
        stack.add(gapAbove: Rhythm.aroundFigures, height: buttonHeight)
        stack.add(gapAbove: Rhythm.buttonRow, height: buttonHeight)

        let panelHeight = stack.height
        let panel = UITheme.createPanel(
            width: panelWidth,
            height: panelHeight,
            borderColor: UITheme.Colors.dangerRed
        )
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.alpha = 0

        // Add outer glow effect
        if let glowPanel = panel.copy() as? SKShapeNode {
            glowPanel.fillColor = .clear
            glowPanel.strokeColor = UITheme.Colors.dangerRedLight
            glowPanel.lineWidth = UITheme.Dimensions.lineWidthGlowStrong
            glowPanel.setScale(1.02)
            glowPanel.alpha = 0
            addChild(glowPanel)

            // Pulse animation for glow
            glowPanel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.6),
                SKAction.fadeIn(withDuration: UITheme.Animations.durationMedium),
                UITheme.createGlowPulseAnimation()
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

        // X mark icon (defeat symbol)
        defeatIcon.position = CGPoint(
            x: 0,
            y: stack.next(gapAbove: Rhythm.edge, height: iconHeight)
        )
        defeatIcon.alpha = 0
        panel.addChild(defeatIcon)

        // Animated icon entrance with shake
        defeatIcon.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.sequence([
                    SKAction.scale(to: 0.9, duration: 0.15),
                    SKAction.scale(to: 0.8, duration: 0.15)
                ]),
                SKAction.sequence([
                    SKAction.rotate(byAngle: 0.2, duration: UITheme.Animations.durationFast),
                    SKAction.rotate(byAngle: -0.4, duration: UITheme.Animations.durationFast),
                    SKAction.rotate(byAngle: 0.2, duration: UITheme.Animations.durationFast)
                ])
            ])
        ]))

        // "LEVEL FAILED" title
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
                    SKAction.scale(to: 1.2, duration: UITheme.Animations.durationQuick),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
                ])
            ])
        ]))

        // Score display
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
            SKAction.wait(forDuration: 0.7),
            SKAction.group([
                SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                SKAction.moveBy(x: 0, y: Self.figuresRise, duration: UITheme.Animations.durationNormal)
            ])
        ]))

        // Buttons
        setupButtons(
            on: panel,
            retryY: stack.next(gapAbove: Rhythm.aroundFigures, height: buttonHeight),
            secondaryY: stack.next(gapAbove: Rhythm.buttonRow, height: buttonHeight)
        )
    }

    /// The figures under the title, spaced by `UITheme.PanelRhythm` and centred on the
    /// returned node's origin, with the optical height the outer stack needs.
    private func createScoreDisplay() -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        // Score label "SCORE" with icon
        let scoreLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.text = L10n.Common.score
        scoreLabel.fontSize = UITheme.Typography.sizeRegular
        scoreLabel.fontColor = UITheme.Colors.textSecondary

        // Score value
        let scoreValue = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        scoreValue.horizontalAlignmentMode = .center
        scoreValue.text = "\(finalScore)"
        scoreValue.fontSize = UITheme.Typography.sizeLarge
        scoreValue.fontColor = UITheme.Colors.primaryGold

        // The caption rides tight against the number it labels; anything further down
        // is a separate figure and gets the wider gap.
        var rows: [(label: SKLabelNode, gapAbove: CGFloat)] = [
            (scoreLabel, 0),
            (scoreValue, Rhythm.captionToValue)
        ]

        // Endless has no completion screen, so the run's result is reported here or
        // nowhere: how deep it got, and whether it beat the standing record.
        if isEndless {
            let roundLine = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            roundLine.horizontalAlignmentMode = .center
            roundLine.fontSize = 16
            roundLine.text = L10n.GameOver.reachedRound(endlessRound)
            roundLine.fontColor = UITheme.Colors.primaryCyanLight
            rows.append((roundLine, Rhythm.figureLine))

            let recordLine = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
            recordLine.horizontalAlignmentMode = .center
            recordLine.fontSize = 15

            let records = LevelManager.shared.getEndlessRecords()
            if isEndlessRecord {
                recordLine.text = L10n.GameOver.newRecord
                recordLine.fontColor = UITheme.Colors.successGreenLight
                recordLine.run(.repeatForever(.sequence([
                    .scale(to: 1.08, duration: 0.5),
                    .scale(to: 1.0, duration: 0.5)
                ])))
            } else {
                recordLine.text = L10n.Common.endlessRecord(score: records.bestScore, round: records.bestRound)
                recordLine.fontColor = UITheme.Colors.textSecondary
            }
            rows.append((recordLine, Rhythm.figureLine))
        }

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime.
        container.name = "figureBlock"

        let height = UITheme.stackLabels(rows, in: container)
        return (container, height)
    }

    private func setupButtons(on panel: SKShapeNode, retryY: CGFloat, secondaryY: CGFloat) {
        let buttonY = retryY

        // Retry button
        let retryButton = UITheme.createButton(
            text: L10n.Common.retry,
            color: UITheme.Colors.successGreen,
            width: UITheme.Dimensions.buttonWidthXLarge,
            name: "retryButton"
        )
        retryButton.position = CGPoint(x: 0, y: buttonY)
        retryButton.alpha = 0
        panel.addChild(retryButton)

        retryButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.9),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

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
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))

        menuButton.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.1),
            SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal)
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name ?? touchedNode.parent?.name {
            switch nodeName {
            case "retryButton":
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleRetryButton()
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

    private func handleRetryButton() {
        // Button press animation
        if let retryButton = childNode(withName: "//retryButton") as? SKShapeNode {
            retryButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.restartGame()
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

    private func restartGame() {
        guard let view = view else { return }
        let gameScene = GameScene(size: view.bounds.size)
        gameScene.scaleMode = scaleMode
        gameScene.currentLevel = currentLevel // Restart the same level
        // RETRY on an endless run starts another endless run, not the campaign.
        gameScene.isEndless = isEndless

        // Load weapon arsenal from previous level when restarting. Endless always starts
        // from the default loadout — carrying an arsenal into an unbounded score chase
        // would make the record depend on campaign progress rather than on the run.
        if !isEndless, currentLevel > 1 {
            let weapons = LevelManager.shared.getLevelWeapons(level: currentLevel - 1)
            gameScene.startingBulletCount = weapons.bulletCount
            gameScene.startingSideMissileCount = weapons.sideMissileCount
        }

        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(gameScene, transition: transition)
    }

    private func goToLevelSelect() {
        guard let view = view else { return }
        let levelSelectScene = LevelSelectScene(size: view.bounds.size, startLevel: currentLevel)
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

    private func createDefeatIcon() -> SKNode {
        let container = SKNode()

        // Red circle background
        let circle = SKShapeNode(circleOfRadius: 35)
        circle.fillColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 1.0)
        circle.strokeColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        circle.lineWidth = 4
        container.addChild(circle)

        // Add inner glow circle
        let glowCircle = SKShapeNode(circleOfRadius: 32)
        glowCircle.fillColor = .clear
        glowCircle.strokeColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 0.5)
        glowCircle.lineWidth = 6
        glowCircle.alpha = 0.6
        container.addChild(glowCircle)

        // Pulse animation for glow
        glowCircle.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 0.8, duration: 0.8)
        ])))

        // Sad face emoji
        // Left eye
        let leftEye = SKShapeNode(circleOfRadius: 4)
        leftEye.fillColor = .white
        leftEye.strokeColor = .white
        leftEye.lineWidth = 2
        leftEye.position = CGPoint(x: -10, y: 6)
        container.addChild(leftEye)

        // Right eye
        let rightEye = SKShapeNode(circleOfRadius: 4)
        rightEye.fillColor = .white
        rightEye.strokeColor = .white
        rightEye.lineWidth = 2
        rightEye.position = CGPoint(x: 10, y: 6)
        container.addChild(rightEye)

        // Frowning mouth (upward arc, angry expression)
        let mouthPath = CGMutablePath()
        mouthPath.move(to: CGPoint(x: -12, y: -10))
        mouthPath.addQuadCurve(
            to: CGPoint(x: 12, y: -10),
            control: CGPoint(x: 0, y: -2)
        )

        let mouth = SKShapeNode(path: mouthPath)
        mouth.strokeColor = .white
        mouth.lineWidth = 3
        mouth.lineCap = .round
        container.addChild(mouth)

        return container
    }

    private func addWarningParticles() {
        // Red fire effect from bottom
        let particles = SKEmitterNode()

        particles.particleTexture = ParticleTexture.softCircle(diameter: 32)

        // Fire color sequence: white-hot -> yellow -> orange -> red -> dark
        let colorSequence = SKKeyframeSequence(keyframeValues: [
            UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0),   // Hot white
            UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0),   // Yellow
            UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0),   // Orange
            UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.8),   // Red
            UIColor(red: 0.2, green: 0.0, blue: 0.0, alpha: 0.0)    // Dark fade
        ], times: [0, 0.2, 0.4, 0.7, 1.0])
        particles.particleColorSequence = colorSequence

        particles.particleBirthRate = 50
        particles.particleLifetime = 2.5
        particles.particleLifetimeRange = 1.0
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
        particles.name = "warningParticles"
        addChild(particles)
    }
}
