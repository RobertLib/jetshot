//
//  StoryScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.01.2026.
//

import SpriteKit

enum StoryType {
    case opening
    case ending
}

class StoryScene: SKScene {

    private let storyType: StoryType
    private let targetLevel: Int?
    private var scrollContainer: SKNode!
    private var isSkipped = false
    private var skipLabel: SKLabelNode!
    /// Only the bottom inset is kept: the crawl scrolls in from above `size.height`
    /// rather than being pinned near the notch, so nothing in this scene has a top
    /// margin to honour. The top inset used to be stored here and never read.
    private var safeAreaBottom: CGFloat = 0

    // Touch tracking for tap vs swipe detection
    private var touchStartLocation: CGPoint?
    private var touchStartTime: TimeInterval = 0

    init(size: CGSize, type: StoryType, targetLevel: Int? = nil) {
        self.storyType = type
        self.targetLevel = targetLevel
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        // Get safe area inset for the skip label
        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)

        // Add starfield background
        StarfieldHelper.addDepthLayers(to: self)
        addChild(StarfieldHelper.createStarfield(for: self))
        NeonFX.attachGrade(to: self, zPosition: -5)
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))

        setupStory()
        setupSkipButton()

        // Start story music
        SoundManager.shared.playSpecificMusic(named: SoundManager.storyMusicTrack)
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
        scrollContainer?.removeAllActions()
        scrollContainer?.removeAllChildren()
    }

    private func setupStory() {
        scrollContainer = SKNode()
        scrollContainer.position = CGPoint(x: size.width / 2, y: size.height)
        addChild(scrollContainer)

        let storyText: [String]
        let title: String

        switch storyType {
        case .opening:
            title = "END OF AGES"
            storyText = [
                "We stand at the very end of time...",
                "",
                "The universe has reached its critical point. Stars are living their final moments, black holes have consumed most matter, and the very fabric of spacetime is beginning to collapse.",
                "",
                "Quantum mechanics, once strictly separated from the macroscopic world, now bleeds into reality. Dimensions overlap, time flows chaotically, and physical laws lose their meaning.",
                "",
                "You are the pilot of the experimental ship Singularity-7, civilization's last hope. Your mission is not to save this dying universe, that is no longer possible.",
                "",
                "Your mission is to escape.",
                "",
                "Gather enough quantum energy from collapsing regions of space, penetrate through dimensional rifts, and reach the epicenter of the collapse.",
                "",
                "There, in the very heart of the dying universe, you must activate protocol Big Bang Zero, ignite a new singularity, a new universe, a new beginning.",
                "",
                "The path will not be easy. Remnants of ancient civilizations, transformed into hostile quantum entities, guard the last fragments of energy. Cosmic anomalies will seek to consume you. Reality itself will resist.",
                "",
                "But there is no other way.",
                "",
                "Either you successfully penetrate into the new singularity...",
                "",
                "...or you perish along with this universe."
            ]
        case .ending:
            title = "NEW BEGINNING"
            storyText = [
                "You did it...",
                "",
                "You flew through collapsing dimensions, overcame quantum entities of ancient civilizations, survived the collapse of spacetime itself.",
                "",
                "At the epicenter of the dying universe, where time stopped and reality lost its meaning, you activated protocol Big Bang Zero.",
                "",
                "Your ship Singularity-7 became the catalyst for new creation. The quantum energy you gathered forms the seed of a new universe.",
                "",
                "Around you forms a new singularity, an infinitesimal point of infinite density, from which space, time, matter and energy will be born.",
                "",
                "You see the first flashes of new stars being born from the dust of the old universe. You feel new dimensions forming around you, new physical laws, new possibilities.",
                "",
                "Your mission was successful. The old universe died, but its legacy will survive in the new creation.",
                "",
                "Perhaps someday, billions of years in the future, when this new universe grows and matures, someone will ask:",
                "",
                "\"How did it all begin?\"",
                "",
                "And the answer will be hidden in the quantum foam of space, the story of a pilot who risked everything to give life a new chance.",
                "",
                "∞",
                "",
                "Thank you for playing!",
                "",
                "You saved not only the universe,",
                "but existence itself."
            ]
        }

        // Create title
        let titleLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        titleLabel.text = title
        titleLabel.fontSize = UITheme.Typography.sizeLarge
        titleLabel.fontColor = UITheme.Colors.primaryGold
        titleLabel.position = CGPoint(x: 0, y: -150)

        // Add glow effect to title
        if let glowTitle = titleLabel.copy() as? SKLabelNode {
            glowTitle.fontColor = UITheme.Colors.primaryGold
            glowTitle.alpha = 0.5
            glowTitle.setScale(1.05)
            scrollContainer.addChild(glowTitle)

            // Pulse animation
            glowTitle.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.3, duration: 1.5),
                SKAction.fadeAlpha(to: 0.7, duration: 1.5)
            ])))
        }

        scrollContainer.addChild(titleLabel)

        // Create story paragraphs
        let maxWidth = min(size.width - 80, 600)
        let leftEdge = -(maxWidth / 2)
        var currentY: CGFloat = -200

        for paragraph in storyText {
            let paragraphLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
            paragraphLabel.text = paragraph
            paragraphLabel.fontSize = UITheme.Typography.sizeRegular
            paragraphLabel.fontColor = paragraph.isEmpty ? .clear : UITheme.Colors.textPrimary
            paragraphLabel.preferredMaxLayoutWidth = maxWidth
            paragraphLabel.numberOfLines = 0
            paragraphLabel.lineBreakMode = .byWordWrapping
            paragraphLabel.verticalAlignmentMode = .top
            paragraphLabel.horizontalAlignmentMode = .left
            paragraphLabel.position = CGPoint(x: leftEdge, y: currentY)
            scrollContainer.addChild(paragraphLabel)

            // Calculate actual height based on frame after text is laid out
            if paragraph.isEmpty {
                currentY -= 20 // Empty line spacing
            } else {
                let labelHeight = paragraphLabel.frame.height
                currentY -= labelHeight + 15 // Add spacing between paragraphs
            }
        }

        // Calculate scroll duration based on content length
        let totalHeight = abs(currentY) + size.height
        let scrollDuration: TimeInterval

        switch storyType {
        case .opening:
            scrollDuration = 80.0 // Opening story scrolls in 80 seconds
        case .ending:
            scrollDuration = 90.0 // Ending story scrolls in 90 seconds
        }

        // Start scrolling animation
        let waitBeforeScroll = SKAction.wait(forDuration: 3.0) // Wait 3 seconds so title is visible
        let scrollAction = SKAction.moveTo(y: totalHeight, duration: scrollDuration)
        let completeAction = SKAction.run { [weak self] in
            self?.storyComplete()
        }

        scrollContainer.run(SKAction.sequence([waitBeforeScroll, scrollAction, completeAction]))
    }

    private func setupSkipButton() {
        skipLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        skipLabel.text = "Tap anywhere to skip"
        skipLabel.fontSize = UITheme.Typography.sizeSmall
        skipLabel.fontColor = UITheme.Colors.textSecondary
        skipLabel.position = CGPoint(x: size.width / 2, y: safeAreaBottom + 40)
        skipLabel.alpha = 0
        addChild(skipLabel)

        // Fade in skip label after a moment
        skipLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeIn(withDuration: 1.0),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.4, duration: 1.0),
                SKAction.fadeAlpha(to: 1.0, duration: 1.0)
            ]))
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isSkipped, let touch = touches.first else { return }

        touchStartLocation = touch.location(in: self)
        touchStartTime = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isSkipped, let touch = touches.first, let startLocation = touchStartLocation else { return }

        let endLocation = touch.location(in: self)
        let distance = hypot(endLocation.x - startLocation.x, endLocation.y - startLocation.y)
        let duration = touch.timestamp - touchStartTime

        // Only skip if it's a tap (small movement, short duration)
        if distance < 20 && duration < 0.3 {
            SoundManager.shared.playButtonClickSound(on: self)
            storyComplete()
        }

        touchStartLocation = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartLocation = nil
    }

    private func storyComplete() {
        guard !isSkipped else { return }
        isSkipped = true

        // Stop story music and return to normal background music
        SoundManager.shared.stopBackgroundMusic()
        SoundManager.shared.startBackgroundMusic()

        // Remove all actions
        scrollContainer?.removeAllActions()
        skipLabel?.removeAllActions()

        // Transition to next scene
        let transition = SKTransition.fade(withDuration: 1.0)

        guard let view = view else { return }

        switch storyType {
        case .opening:
            // Record that the intro has been seen, so replaying level 1 goes straight
            // into the game. This is the single exit point for both the natural end of
            // the crawl and the tap-to-skip, so it covers both.
            LevelManager.shared.hasSeenOpeningStory = true

            // Start the game
            if let level = targetLevel {
                let gameScene = GameScene(size: view.bounds.size)
                gameScene.scaleMode = .resizeFill
                gameScene.currentLevel = level

                // For level 1, always start with default weapons
                // For other levels (if story can be shown), load from previous level
                if level > 1 {
                    let weapons = LevelManager.shared.getLevelWeapons(level: level - 1)
                    gameScene.startingBulletCount = weapons.bulletCount
                    gameScene.startingSideMissileCount = weapons.sideMissileCount
                }

                view.presentScene(gameScene, transition: transition)
            }
        case .ending:
            // Hand off to the victory screen, which owns the total score and the
            // play-again / levels / menu choices. This used to bounce straight to the
            // level select, which is why GameCompletionScene never appeared.
            let completionScene = GameCompletionScene(
                size: view.bounds.size,
                totalScore: LevelManager.shared.getTotalScore()
            )
            completionScene.scaleMode = .resizeFill
            view.presentScene(completionScene, transition: transition)
        }
    }
}
