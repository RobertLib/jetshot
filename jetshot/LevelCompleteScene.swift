//
//  LevelCompleteScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class LevelCompleteScene: SKScene {

    /// Shared vertical rhythm for the results screens. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    private let level: Int
    private let score: Int
    private let coinsCollected: Int
    private let totalCoins: Int
    private let bulletCount: Int
    private let sideMissileCount: Int
    private let bestChain: Int
    /// Hostile rounds grazed this level. See `GrazeRules`.
    private let grazes: Int
    /// Medals this run earned, and what the level held before it.
    private let medals: MedalSet
    private var previousMedals: MedalSet = []
    private var newMedals: MedalSet = []
    private var isInitialized = false
    /// Every button here leaves the screen, once. See `FilmUI.Exit`.
    private let exit = FilmUI.Exit()

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

    init(size: CGSize, level: Int, score: Int, coinsCollected: Int = 0, totalCoins: Int = 0, bulletCount: Int = 1, sideMissileCount: Int = 0, bestChain: Int = 0, grazes: Int = 0, medals: MedalSet = []) {
        self.level = level
        self.score = score
        self.coinsCollected = coinsCollected
        self.totalCoins = totalCoins
        self.bulletCount = bulletCount
        self.sideMissileCount = sideMissileCount
        self.bestChain = bestChain
        self.grazes = grazes
        self.medals = medals
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

        // Medals are a union over every run: read what the level held, then add this
        // run's, keeping which ones are new so the row can celebrate only those.
        previousMedals = LevelManager.shared.getLevelMedals(level: level)
        newMedals = LevelManager.shared.recordMedals(medals, level: level)

        GameBackdrop.attachAmbient(to: self, look: .forLevel(level)).pulse()
        NeonFX.attachGrade(to: self, zPosition: -5)

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
        // Not while leaving: the rebuild would take the pressed button, and the press
        // animation whose completion is the way out, with it — stranding the screen with
        // its input already switched off.
        guard !exit.isTaken else { return }

        // Remove and recreate all elements
        removeAllChildren()

        GameBackdrop.attachAmbient(to: self, look: .forLevel(level)).pulse()
        NeonFX.attachGrade(to: self, zPosition: -5)
        setupUI()
    }

    override func willMove(from view: SKView) {
        // Clean up all resources before scene is removed
        removeAllActions()
        removeAllChildren()
    }

    private func setupUI() {
        let card = ResultsCard(sceneWidth: size.width)
        let gold = StoryPalette.gold

        let sector = (level - 1) / 5 + 1
        let tag = card.tag("\(L10n.HUD.level(level))  ·  \(L10n.Sector.name(sector))",
                           color: StoryPalette.cyan, delay: 0.2)
        card.add(tag, gapAbove: Rhythm.edge, height: 14, reveal: false)

        let stars = createStarRating()
        card.add(stars, gapAbove: 18, height: 40, reveal: false)

        let title = FilmUI.title(L10n.LevelComplete.title, size: 34, color: UITheme.Colors.primaryGold,
                                 glow: gold, tracking: 6, maxWidth: card.width)
        title.alpha = 0
        title.setScale(1.1)
        let settle = SKAction.scale(to: 1, duration: 0.8)
        settle.timingMode = .easeOut
        title.run(.sequence([.wait(forDuration: 0.35), .group([.fadeIn(withDuration: 0.35), settle])]))
        card.add(title, gapAbove: 18, height: title.frame.height, reveal: false)

        let rule = FilmUI.drawnRule(width: min(card.width, 240), color: UITheme.Colors.primaryGold,
                                    alpha: 0.7, delay: 0.55)
        card.add(rule, gapAbove: 14, height: 1, reveal: false)

        let figures = createScoreDisplay(card: card)
        card.add(figures.node, gapAbove: Rhythm.aroundFigures, height: figures.height)

        // The way on is cyan, as it is everywhere; the last level's way on is the ending,
        // and that one is gold.
        let isLastLevel = level >= LevelManager.shared.totalLevels
        let primary = UITheme.createButton(
            text: isLastLevel ? L10n.LevelComplete.continue : L10n.LevelComplete.next,
            color: isLastLevel ? gold : StoryPalette.cyan,
            width: card.primaryButtonWidth,
            name: isLastLevel ? "victoryButton" : "nextButton",
            primary: true
        )
        let levelsButton = UITheme.createButton(text: L10n.Common.levels, color: FilmUI.neutral,
                                                width: card.pairButtonWidth, name: "levelsButton")
        let menuButton = UITheme.createButton(text: L10n.Common.menu, color: FilmUI.neutral,
                                              width: card.pairButtonWidth, name: "menuButton")
        card.addButtons(primary: primary, pair: (levelsButton, menuButton), gapAbove: Rhythm.aroundFigures)

        card.install(in: self, accent: gold,
                     safeTop: GameConfiguration.safeAreaTop(in: view),
                     safeBottom: GameConfiguration.safeAreaBottom(in: view),
                     revealFrom: 0.85)
    }

    /// Three stars drawn in light. Each one ignites in turn — earned ones with a ring
    /// of light and a burst of sparks, the rest as a dim outline of what was missed.
    private func createStarRating() -> SKNode {
        let row = SKNode()
        let spacing: CGFloat = 56
        let radius: CGFloat = 19

        for i in 0..<3 {
            let earned = i < starsEarned
            let x = CGFloat(i - 1) * spacing
            let star = FilmUI.lightStar(radius: radius, color: UITheme.Colors.primaryGold, lit: earned)
            star.position = CGPoint(x: x, y: 0)
            star.alpha = 0
            star.setScale(earned ? 1.8 : 1.0)
            row.addChild(star)

            let delay = 0.45 + Double(i) * 0.2
            let land = SKAction.scale(to: 1, duration: 0.3)
            land.timingMode = .easeOut
            star.run(.sequence([.wait(forDuration: delay),
                                .group([.fadeAlpha(to: earned ? 1 : 0.8, duration: 0.15), land])]))

            guard earned else { continue }
            // Built when it fires: a shockwave and sparks start animating the moment
            // they exist.
            row.run(.sequence([.wait(forDuration: delay + 0.22), .run { [weak row] in
                guard let row = row else { return }
                row.addChild(NeonFX.shockwave(at: CGPoint(x: x, y: 0), startRadius: radius * 0.6,
                                              endRadius: radius * 2.6, color: StoryPalette.gold,
                                              lineWidth: 2, duration: 0.5))
                row.addChild(NeonFX.sparks(at: CGPoint(x: x, y: 0), count: 10, color: StoryPalette.sun,
                                           speed: 70, length: 6, lifetime: 0.45))
            }]))
            // Then the lit stars breathe.
            if let glow = star.childNode(withName: "starGlow") {
                glow.run(.sequence([
                    .wait(forDuration: delay + 0.4),
                    .repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: 1.1), .fadeAlpha(to: 0.5, duration: 1.1)]))
                ]))
            }
        }
        return row
    }

    /// The figures under the title, spaced by `UITheme.PanelRhythm` and centred on the
    /// returned node's origin, with the height the outer stack needs.
    private func createScoreDisplay(card: ResultsCard) -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        let caption = card.caption(L10n.Common.score)
        let value = card.figure(score, color: UITheme.Colors.primaryGoldLight)

        // The caption rides tight against the number it labels; the lines below are
        // separate figures and get the wider gap.
        var rows: [(label: SKLabelNode, gapAbove: CGFloat)] = [
            (caption, 0),
            (value, Rhythm.captionToValue)
        ]

        // The record line. A cleared level used to report a bare number with nothing to
        // compare it against, so there was no reason to replay one and no way to tell a
        // great run from a scraped-through one. Beating the stored best is now called
        // out; falling short of it prints the target instead, which is the same hook
        // from the other side.
        let recordLine: SKLabelNode
        if isNewBest {
            recordLine = card.line(L10n.LevelComplete.newBest(improvement: score - previousBest),
                                   color: UITheme.Colors.improvement)
            recordLine.run(.sequence([
                .wait(forDuration: 2.0),
                .repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]))
            ]))
        } else if previousBest > 0 {
            recordLine = card.line(L10n.Common.best(previousBest), color: UITheme.Colors.textSecondary)
        } else {
            recordLine = card.line(L10n.LevelComplete.personalBestSet, color: UITheme.Colors.improvement)
        }
        rows.append((recordLine, Rhythm.figureLine))

        // Best chain of the run, when there was one worth reporting. This is the only
        // place the chain's peak is shown after the meter itself disappears, and it is
        // the number a player who wants a higher score has to attack next time.
        if bestChain >= ComboRules.tiers[0].chain {
            let multiplier = ComboRules.multiplier(forChain: bestChain)
            rows.append((card.line(L10n.LevelComplete.bestChain(length: bestChain, multiplier: multiplier),
                                   color: ComboSystem.tierColor(forMultiplier: multiplier)),
                         Rhythm.figureLine))
        }

        // Grazes: the other skill number a run produces, and the one that says how close
        // to the fire the player was willing to fly.
        if grazes > 0 {
            rows.append((card.line(L10n.LevelComplete.grazes(grazes),
                                   color: UIColor(red: 1.0, green: 0.62, blue: 0.82, alpha: 1.0)),
                         Rhythm.figureLine))
        }

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime.
        container.name = "figureBlock"

        // The medals ride inside the figure block rather than in a row of their own, so
        // the block stays centred between the title and the button however many lines
        // the run has to report — the invariant `ResultsPanelCentringTests` holds.
        //
        // The lines stay direct children of the block (the spacing test reads them
        // there); they are stacked as usual and then lifted as one to make room.
        let labelsHeight = UITheme.stackLabels(rows, in: container)
        let medalRow = createMedalRow()
        let gap: CGFloat = 22
        let height = labelsHeight + gap + medalRow.height

        let lift = height / 2 - labelsHeight / 2
        for row in rows {
            row.label.position.y += lift
        }
        medalRow.node.position = CGPoint(x: 0, y: -height / 2 + medalRow.height / 2)
        container.addChild(medalRow.node)

        FilmUI.countUp(value, to: score, delay: 1.0, duration: 0.8, glow: StoryPalette.gold)
        return (container, height)
    }

    /// The level's three medals: held ones lit, the rest dim, and the ones this run won
    /// for the first time tagged and popped in after the score has landed.
    private func createMedalRow() -> (node: SKNode, height: CGFloat) {
        let row = SKNode()
        let held = previousMedals.union(medals)
        let radius: CGFloat = 16
        let spacing: CGFloat = 92
        let tagHeight: CGFloat = newMedals.isEmpty ? 0 : 14
        let labelGap: CGFloat = 9
        let labelSize: CGFloat = 9
        let height = tagHeight + radius * 2 + labelGap + labelSize

        // Centres within the row, top down.
        let badgeY = height / 2 - tagHeight - radius
        let labelY = badgeY - radius - labelGap - labelSize / 2

        for (index, medal) in MedalSet.ordered.enumerated() {
            let x = CGFloat(index - 1) * spacing
            let earned = held.contains(medal)
            let isNew = newMedals.contains(medal)

            let badge = MedalBadge.badge(for: medal, earned: earned, radius: radius, level: level, glow: false)
            badge.position = CGPoint(x: x, y: badgeY)
            row.addChild(badge)

            let label = FilmUI.mono(MedalBadge.label(for: medal, level: level), size: labelSize,
                                    color: earned ? MedalBadge.color(for: medal) : UITheme.Colors.textSecondary.withAlphaComponent(0.7),
                                    tracking: 0.8, maxWidth: spacing - 6)
            label.position = CGPoint(x: x, y: labelY)
            row.addChild(label)

            if isNew {
                let tag = FilmUI.mono(L10n.Medal.new, size: 9, color: .white, tracking: 2)
                tag.position = CGPoint(x: x, y: badgeY + radius + 9)
                row.addChild(tag)
                tag.alpha = 0
                tag.run(.sequence([.wait(forDuration: 2.1 + Double(index) * 0.15), .fadeIn(withDuration: 0.2)]))

                // Pop in after the figures have arrived, with a ring thrown off it.
                badge.setScale(0.01)
                let delay = 1.9 + Double(index) * 0.15
                badge.run(.sequence([
                    .wait(forDuration: delay),
                    .scale(to: 1.25, duration: 0.16),
                    .scale(to: 1.0, duration: 0.12)
                ]))
                // Built when it fires: a shockwave starts animating the moment it exists.
                let color = MedalBadge.color(for: medal)
                run(.sequence([.wait(forDuration: delay + 0.1), .run { [weak self, weak row] in
                    guard let self = self, let row = row else { return }
                    row.addChild(NeonFX.shockwave(at: CGPoint(x: x, y: badgeY), startRadius: radius,
                                                  endRadius: radius * 2.6, color: color,
                                                  lineWidth: 2.5, duration: 0.5))
                    HapticManager.shared.lightTap()
                    SoundManager.shared.playCoinSound(on: self)
                }]))
            }
        }
        return (row, height)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !exit.isTaken, let touch = touches.first else { return }
        let location = touch.location(in: self)

        guard let button = FilmUI.button(at: location, under: self,
                                         names: ["nextButton", "victoryButton", "levelsButton", "menuButton"]),
              exit.take() else { return }
        HapticManager.shared.lightTap()
        SoundManager.shared.playButtonClickSound(on: self)

        let action: () -> Void
        switch button.name {
        case "nextButton": action = { [weak self] in self?.startNextLevel() }
        case "victoryButton": action = { [weak self] in self?.showGameCompletion() }
        case "levelsButton": action = { [weak self] in self?.goToLevelSelect() }
        default: action = { [weak self] in self?.goToMenu() }
        }
        button.run(UITheme.createButtonPressAnimation(completion: action))
    }

    private func startNextLevel() {
        let nextLevel = level + 1
        // NEXT is only offered below the last level; past it the way on is the ending.
        // Going there rather than doing nothing keeps the committed exit from stranding
        // the screen with its input switched off.
        guard nextLevel <= LevelManager.shared.totalLevels else {
            showGameCompletion()
            return
        }
        exit.present(from: self) { size in
            let gameScene = GameScene(size: size)
            gameScene.currentLevel = nextLevel

            // Load weapon arsenal from previous level (current completed level)
            let weapons = LevelManager.shared.getLevelWeapons(level: level)
            gameScene.startingBulletCount = weapons.bulletCount
            gameScene.startingSideMissileCount = weapons.sideMissileCount
            return gameScene
        }
    }

    /// Finishing the last level runs the ending film, which then hands off to
    /// `GameCompletionScene`.
    ///
    /// This used to present `GameCompletionScene` directly, but that scene's
    /// `didMove(to:)` forwarded straight on to the crawl without ever building itself —
    /// so the victory screen was skipped entirely. Going through `StoryScene` first
    /// keeps the same order the player saw (film, then payoff) and makes the payoff
    /// actually appear. It reads its own total from `LevelManager`, which is where the
    /// value came from anyway.
    private func showGameCompletion() {
        exit.present(from: self, fade: 1.0) { StoryScene(size: $0, type: .ending) }
    }

    private func goToLevelSelect() {
        exit.present(from: self) { LevelSelectScene(size: $0, startLevel: level) }
    }

    private func goToMenu() {
        exit.present(from: self) { MenuScene(size: $0) }
    }
}
