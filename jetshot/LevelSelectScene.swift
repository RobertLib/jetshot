//
//  LevelSelectScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

/// The level grid, laid out as the route the films fly: each page is two sectors of
/// five levels, each sector a strip headed with its name, the world behind flying on to
/// the sector the page opens on.
///
/// Pages used to be an arbitrary dozen levels in a 3×4 grid, which cut sectors in half
/// — a page started on level 13, the third of a sector — so the names the level card
/// and the backdrop are built around never appeared here at all.
class LevelSelectScene: SKScene {

    private let levelManager = LevelManager.shared
    private var levelButtons: [SKNode] = []
    private var currentPage = 0
    /// The outgoing tiles are removed before their press actions could finish, so
    /// input waits until both halves of a page change have finished.
    private var isChangingPage = false

    /// Levels in a sector — the route's unit, see `BackdropLook.forLevel`.
    static let levelsPerSector = 5
    /// Sectors on one page.
    static let sectorsPerPage = 2
    /// Not private, so the tests can derive the page arithmetic from the scene instead
    /// of keeping their own copy of it.
    static let levelsPerPage = levelsPerSector * sectorsPerPage
    private var levelsPerPage: Int { Self.levelsPerPage }

    /// Everything but the world and the frame: drawn larger on a wide screen, and laid
    /// out in its own points against `layoutSize`.
    private var content: SKNode!
    private var layoutSize: CGSize = .zero

    private var pageContainer: SKNode!
    private var gridCentre: CGPoint = .zero
    private var leftArrow: SKNode?
    private var rightArrow: SKNode?
    private var pageLabel: SKLabelNode?
    private var pageSegments: [SKSpriteNode] = []

    private var safeAreaTop: CGFloat = 0
    private var safeAreaBottom: CGFloat = 0
    private var isInitialized = false
    /// A level tile and BACK leave this screen, once. See `FilmUI.Exit`.
    private let exit = FilmUI.Exit()

    /// Where the reset confirmation is in its life. It owns every touch from the moment
    /// it opens until it has *gone* — and, after YES, until the grid has been rebuilt on
    /// the cleared progress — not merely until it starts to fade. See `isConfirmingReset`.
    private enum ResetDialogState {
        case closed, open, closing
    }
    private var resetDialog: ResetDialogState = .closed

    /// A locked tile's padlock at rest. The refusal flash restores this rather than
    /// whatever colour the padlock had when it was tapped, which during a flash already
    /// in progress is the flash's own red.
    private static let padlockColor = UIColor(white: 0.62, alpha: 0.6)

    // Swipe gesture tracking
    private var touchStartLocation: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var hasMoved = false

    /// Number of pages the grid spans. Derived rather than restated: the same ceiling
    /// division was written out at four separate call sites.
    private var totalPages: Int {
        return max(1, (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage)
    }

    // Initialize with optional level to navigate to
    init(size: CGSize, startLevel: Int? = nil) {
        super.init(size: size)
        // Calculate page based on start level if provided.
        //
        // Clamped, because an unclamped page is a crash rather than a blank grid:
        // `loadPage` iterates `startLevel...endLevel`, and a page past the end of the
        // grid makes `startLevel` exceed `endLevel` (which is capped at `totalLevels`),
        // which traps on the invalid range. `LevelSelectScene(startLevel: 61)` was enough
        // to do it. Every caller passes a level it read back from stored progress, and
        // `LevelManager` already defends that same "saved level outruns totalLevels" case
        // in `getLevelConfig(for:)` and `getLevelWeapons(level:)`.
        if let level = startLevel, level > 0 {
            currentPage = min((level - 1) / levelsPerPage, totalPages - 1)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        readSafeArea(from: view)
        buildScene(animated: true)
        isInitialized = true

        // `safeAreaInsets` is still zero during didMove(to:), so re-lay the scene
        // once the view has been through a layout pass. Without this the title
        // ends up tucked under the Dynamic Island.
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self = self, let view = view, self.view != nil, !self.exit.isTaken else { return }
            let previousTop = self.safeAreaTop
            let previousBottom = self.safeAreaBottom
            self.readSafeArea(from: view)
            if self.safeAreaTop != previousTop || self.safeAreaBottom != previousBottom {
                self.removeAllChildren()
                self.buildScene(animated: false)
            }
        }

        SoundManager.shared.startBackgroundMusic()
    }

    private func readSafeArea(from view: SKView) {
        safeAreaTop = GameConfiguration.safeAreaTop(in: view)
        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Not while leaving — see `LevelCompleteScene.didChangeSize(_:)`.
        guard isInitialized, !exit.isTaken, let view = view else { return }
        readSafeArea(from: view)
        removeAllChildren()
        buildScene(animated: false)
    }

    override func willMove(from view: SKView) {
        removeAllActions()
        removeAllChildren()
    }

    // MARK: - Layout

    private func buildScene(animated: Bool) {
        // Every rebuild starts from `removeAllChildren()`, which takes an open or closing
        // reset dialog with it — so its state has to go too, or the grid would stay
        // locked behind a dialog that no longer exists.
        resetDialog = .closed
        // Rebuilding also removes the node running the page-change completion.
        isChangingPage = false
        touchStartLocation = nil
        hasMoved = false

        GameBackdrop.attachAmbient(to: self, look: .forLevel(currentPage * levelsPerPage + 1))
        NeonFX.attachGrade(to: self, zPosition: 5)

        let depths = FilmUI.Letterbox.depths(size: size, safeTop: safeAreaTop, safeBottom: safeAreaBottom)
        let frame = FilmUI.Letterbox(size: size, top: depths.top, bottom: depths.bottom, closing: animated)
        frame.zPosition = 40
        addChild(frame)

        // The campaign's running total and where the player is on the route, printed
        // over the picture the way the films print their timecode and shot counter.
        let total = levelManager.totalLevels
        let current = (1...total).last(where: { levelManager.isLevelUnlocked($0) }) ?? 1
        frame.addFurniture(left: "\(L10n.Common.score)  \(levelManager.getTotalScore().formatted())",
                           right: String(format: "%02d / %02d", current, total),
                           recording: true)

        let scale = FilmUI.uiScale(for: size)
        layoutSize = CGSize(width: size.width / scale, height: size.height / scale)
        content = SKNode()
        content.setScale(scale)
        content.zPosition = 10
        addChild(content)

        let picture = CGRect(x: frame.picture.minX / scale, y: frame.picture.minY / scale,
                             width: frame.picture.width / scale, height: frame.picture.height / scale)
        let titleBottom = setupTitle(picture: picture)
        let transportTop = setupBottomControls(picture: picture)

        pageContainer = SKNode()
        gridCentre = CGPoint(x: layoutSize.width / 2, y: ((titleBottom - 14) + (transportTop + 14)) / 2)
        pageContainer.position = gridCentre
        content.addChild(pageContainer)

        loadPage(currentPage)
        updatePaging()
    }

    /// The title, its hairline and the campaign's medal tally under it. Returns the
    /// lowest y the block reaches, for the grid to hang beneath.
    private func setupTitle(picture: CGRect) -> CGFloat {
        let x = layoutSize.width / 2
        let titleY = picture.maxY - 44

        let title = FilmUI.title(L10n.LevelSelect.title, size: 34, color: UITheme.Colors.primaryGold,
                                 glow: StoryPalette.gold, tracking: 7, maxWidth: layoutSize.width - 48)
        title.position = CGPoint(x: x, y: titleY)
        content.addChild(title)

        let rule = FilmUI.drawnRule(width: min(layoutSize.width - 80, 240), color: UITheme.Colors.primaryGold,
                                    alpha: 0.7, delay: 0.2)
        rule.position = CGPoint(x: x, y: titleY - 26)
        content.addChild(rule)

        // The campaign-wide medal tally: the one number that says how much of the game
        // is still left to master after it is beaten. A pip of each medal's colour leads
        // it, as the key to the pips on the tiles.
        let held = levelManager.getTotalMedalCount()
        let possible = GameConfiguration.totalLevels * MedalSet.ordered.count
        let tally = SKNode()
        tally.name = "medalTally"
        tally.position = CGPoint(x: x, y: titleY - 46)
        content.addChild(tally)

        let label = FilmUI.mono(L10n.LevelSelect.medals(held, of: possible), size: 11,
                                color: held > 0 ? UITheme.Colors.textBody : UITheme.Colors.textSecondary,
                                tracking: 2)
        let pipsWidth: CGFloat = 26
        label.position = CGPoint(x: (pipsWidth + 8) / 2, y: 0)
        tally.addChild(label)
        for (index, medal) in MedalSet.ordered.enumerated() {
            let pip = MedalBadge.pip(for: medal, earned: true)
            pip.position = CGPoint(x: label.position.x - label.frame.width / 2 - 8 - CGFloat(2 - index) * 10 - 4, y: 0)
            tally.addChild(pip)
        }

        return tally.position.y - 8
    }

    /// The transport bar — chevrons either side of the page, with a scrubber under it —
    /// and BACK / RESET below. Returns the top of the transport bar.
    private func setupBottomControls(picture: CGRect) -> CGFloat {
        let x = layoutSize.width / 2
        let buttonHeight = UITheme.Dimensions.buttonHeightSecondary
        let buttonsY = picture.minY + 20 + buttonHeight / 2
        let half = UITheme.Dimensions.buttonWidthHalf
        let offset = (half + UITheme.Dimensions.buttonPairGap) / 2

        let backButton = UITheme.createButton(text: L10n.Common.back, color: FilmUI.neutral,
                                              width: half, name: "backButton")
        backButton.position = CGPoint(x: x - offset, y: buttonsY)
        content.addChild(backButton)

        // Destructive, so it is red — and quiet, so it never reads as the way on.
        let resetButton = UITheme.createButton(text: L10n.LevelSelect.reset,
                                               color: StoryPalette.red.withAlphaComponent(0.75),
                                               width: half, name: "resetButton")
        resetButton.position = CGPoint(x: x + offset, y: buttonsY)
        content.addChild(resetButton)

        for (index, button) in [backButton, resetButton].enumerated() {
            button.alpha = 0
            button.run(.sequence([.wait(forDuration: 0.3 + Double(index) * 0.06), .fadeIn(withDuration: 0.3)]))
        }

        // Transport.
        let transportY = buttonsY + buttonHeight / 2 + 34
        let label = FilmUI.mono("", size: 11, color: UITheme.Colors.textBody, tracking: 2)
        label.position = CGPoint(x: x, y: transportY + 6)
        content.addChild(label)
        pageLabel = label

        pageSegments.removeAll()
        let segment: CGFloat = 16, gap: CGFloat = 6
        let scrubWidth = CGFloat(totalPages) * segment + CGFloat(totalPages - 1) * gap
        for page in 0..<totalPages {
            let left = x - scrubWidth / 2 + CGFloat(page) * (segment + gap)
            let tube = FilmUI.tube(CGPoint(x: left, y: transportY - 10), CGPoint(x: left + segment, y: transportY - 10),
                                   width: 1.4, color: StoryPalette.cyan)
            content.addChild(tube)
            pageSegments.append(tube)
        }

        let arrowOffset = min(130, layoutSize.width / 2 - 34)
        let left = FilmUI.chevron(pointingLeft: true, size: 11, color: StoryPalette.cyan)
        left.position = CGPoint(x: x - arrowOffset, y: transportY)
        left.name = "leftArrow"
        content.addChild(left)
        leftArrow = left

        let right = FilmUI.chevron(pointingLeft: false, size: 11, color: StoryPalette.cyan)
        right.position = CGPoint(x: x + arrowOffset, y: transportY)
        right.name = "rightArrow"
        content.addChild(right)
        rightArrow = right

        return transportY + 18
    }

    private func updatePaging() {
        leftArrow?.alpha = currentPage > 0 ? 1 : 0.2
        rightArrow?.alpha = currentPage < totalPages - 1 ? 1 : 0.2
        if let label = pageLabel {
            FilmUI.set(label, L10n.LevelSelect.page(currentPage + 1, of: totalPages).uppercased(),
                       font: UITheme.Typography.fontNumeric, size: 11, color: UITheme.Colors.textBody, tracking: 2)
        }
        for (page, segment) in pageSegments.enumerated() {
            segment.alpha = page == currentPage ? 1 : 0.22
        }
    }

    // MARK: - Page

    private func loadPage(_ page: Int) {
        pageContainer.removeAllChildren()
        levelButtons.removeAll()

        let startLevel = page * levelsPerPage + 1
        let endLevel = min(startLevel + levelsPerPage - 1, levelManager.totalLevels)

        // The world behind the grid flies on to the sector the page opens on.
        (childNode(withName: GameBackdrop.nodeName) as? GameBackdrop)?.transition(to: .forLevel(startLevel))

        // Second line of defence for the ranges below, which trap rather than yield
        // nothing when the bounds cross. The page is clamped at both entry points
        // (`init` and `changePage`), so reaching here means one of them grew a new path.
        guard startLevel <= endLevel else { return }

        let perSector = Self.levelsPerSector
        let stripWidth = min(layoutSize.width - 36, 440)
        let gap: CGFloat = 10
        let tileWidth = min(((stripWidth - gap * CGFloat(perSector - 1)) / CGFloat(perSector)).rounded(.down), 84)
        let tileHeight = (tileWidth * 1.3).rounded()
        let rowWidth = tileWidth * CGFloat(perSector) + gap * CGFloat(perSector - 1)

        let headerHeight: CGFloat = 14
        let headerGap: CGFloat = 12
        let stripHeight = headerHeight + headerGap + tileHeight
        let sectors = Array(stride(from: startLevel, through: endLevel, by: perSector))
        let stripGap: CGFloat = 40
        let blockHeight = CGFloat(sectors.count) * stripHeight + CGFloat(max(0, sectors.count - 1)) * stripGap

        var index = 0
        for (row, firstLevel) in sectors.enumerated() {
            let top = blockHeight / 2 - CGFloat(row) * (stripHeight + stripGap)
            let sector = (firstLevel - 1) / perSector + 1
            let lastLevel = min(firstLevel + perSector - 1, endLevel)

            let header = sectorHeader(sector: sector, levels: firstLevel...lastLevel, width: rowWidth)
            header.position = CGPoint(x: 0, y: top - headerHeight / 2)
            header.alpha = 0
            header.run(.sequence([.wait(forDuration: Double(row) * 0.12), .fadeIn(withDuration: 0.3)]))
            pageContainer.addChild(header)

            let tileY = top - headerHeight - headerGap - tileHeight / 2
            for (column, level) in (firstLevel...lastLevel).enumerated() {
                let tile = createLevelTile(level: level, size: CGSize(width: tileWidth, height: tileHeight))
                tile.position = CGPoint(x: -rowWidth / 2 + tileWidth / 2 + CGFloat(column) * (tileWidth + gap), y: tileY)
                tile.alpha = 0
                tile.setScale(0.92)
                pageContainer.addChild(tile)
                levelButtons.append(tile)

                let arrive = SKAction.scale(to: 1, duration: 0.3)
                arrive.timingMode = .easeOut
                tile.run(.sequence([
                    .wait(forDuration: 0.08 + Double(index) * 0.04),
                    .group([.fadeIn(withDuration: 0.25), arrive])
                ]))
                index += 1
            }
        }
    }

    /// "SECTOR 3 · DIMENSIONAL RIFT", a hairline running on from it, and how much of the
    /// sector is cleared — the strip's caption, set like the films' HUD tags.
    private func sectorHeader(sector: Int, levels: ClosedRange<Int>, width: CGFloat) -> SKNode {
        let node = SKNode()
        node.name = "sectorHeader_\(sector)"
        let isOpen = levelManager.isLevelUnlocked(levels.lowerBound)
        let cleared = levels.filter { levelManager.isLevelCompleted($0) }.count

        let count = FilmUI.mono("\(cleared)/\(levels.count)", size: 10,
                                color: cleared == levels.count ? StoryPalette.cyan : UITheme.Colors.textSecondary,
                                tracking: 1)
        count.horizontalAlignmentMode = .right
        count.position = CGPoint(x: width / 2, y: 0)
        node.addChild(count)

        let label = FilmUI.mono(L10n.Sector.label(sector), size: 11, color: StoryPalette.cyan, tracking: 2)
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -width / 2, y: 0)
        node.addChild(label)

        let nameX = label.position.x + label.frame.width + 8
        let room = width / 2 - count.frame.width - 14 - nameX
        let name = FilmUI.mono("·  \(L10n.Sector.name(sector))", size: 11,
                               color: UITheme.Colors.textSecondary, tracking: 1.5, maxWidth: max(40, room))
        name.horizontalAlignmentMode = .left
        name.position = CGPoint(x: nameX, y: 0)
        node.addChild(name)

        let ruleStart = name.position.x + name.frame.width + 8
        let ruleEnd = width / 2 - count.frame.width - 8
        if ruleEnd - ruleStart > 12 {
            let rule = FilmUI.hairline(width: ruleEnd - ruleStart, color: StoryPalette.cyan, alpha: 0.22)
            rule.position = CGPoint(x: (ruleStart + ruleEnd) / 2, y: 0)
            node.addChild(rule)
        }

        node.alpha = isOpen ? 1 : 0.45
        return node
    }

    /// One level, as a frame on the strip: its number, the stars and medals it has
    /// given up, and its state in the colour of its light.
    ///
    /// - Cleared levels are cyan, the colour of the way on.
    /// - The next level to fly is gold, its brackets breathing — the one the player is
    ///   being asked to pick.
    /// - Locked levels are an unlit hairline with a padlock; the number stays legible
    ///   as a teaser of how far the route goes.
    private func createLevelTile(level: Int, size: CGSize) -> SKNode {
        let container = SKNode()
        container.name = "levelButton_\(level)"
        container.zPosition = 10

        let isUnlocked = levelManager.isLevelUnlocked(level)
        let isCompleted = levelManager.isLevelCompleted(level)
        let tone: UIColor = isCompleted ? StoryPalette.cyan : (isUnlocked ? StoryPalette.gold : FilmUI.neutral)

        // The glass and its tint sit below everything else on the tile. The view sets
        // `ignoresSiblingOrder`, so siblings sharing a z draw in no defined order, and a
        // 72%-opaque frame drawn after the number would all but hide it.
        let frame = SKShapeNode(rectOf: size)
        frame.fillColor = FilmUI.glass.withAlphaComponent(isUnlocked ? 0.72 : 0.5)
        frame.strokeColor = tone.withAlphaComponent(isUnlocked ? 0.3 : 0.16)
        frame.lineWidth = 1
        frame.zPosition = -2
        container.addChild(frame)

        if isUnlocked {
            let wash = SKSpriteNode(color: tone, size: CGSize(width: size.width - 2, height: size.height - 2))
            wash.alpha = isCompleted ? 0.06 : 0.12
            wash.zPosition = -1
            container.addChild(wash)

            let brackets = FilmUI.addBrackets(to: container, size: size, arm: 9, color: tone,
                                              width: isCompleted ? 1.2 : 1.5)
            if !isCompleted {
                for tube in brackets {
                    let dim = SKAction.fadeAlpha(to: 0.35, duration: 0.9)
                    dim.timingMode = .easeInEaseOut
                    let lift = SKAction.fadeAlpha(to: 1, duration: 0.9)
                    lift.timingMode = .easeInEaseOut
                    tube.run(.repeatForever(.sequence([dim, lift])))
                }
            }
        }

        let numberColor: UIColor = isCompleted ? UIColor(white: 0.95, alpha: 1)
            : (isUnlocked ? StoryPalette.mix(StoryPalette.gold, .white, 0.35) : UIColor(white: 0.5, alpha: 0.7))
        let number = FilmUI.mono(String(format: "%02d", level), size: min(24, size.width * 0.34),
                                 color: numberColor, tracking: 1)
        number.position = CGPoint(x: 0, y: isCompleted ? 1 : 4)
        container.addChild(number)

        if isCompleted {
            // Stars across the top of the frame, medals along its foot.
            let stars = levelManager.getLevelStars(level: level)
            for i in 0..<3 {
                let star = SKShapeNode(path: FilmUI.starPath(radius: 5))
                let earned = i < stars
                star.fillColor = earned ? UITheme.Colors.primaryGold : .clear
                star.strokeColor = earned ? StoryPalette.sun : UIColor(white: 0.6, alpha: 0.45)
                star.lineWidth = 1
                star.position = CGPoint(x: CGFloat(i - 1) * 13, y: size.height / 2 - 13)
                container.addChild(star)
            }

            let held = levelManager.getLevelMedals(level: level)
            for (index, medal) in MedalSet.ordered.enumerated() {
                let pip = MedalBadge.pip(for: medal, earned: held.contains(medal))
                pip.position = CGPoint(x: CGFloat(index - 1) * 11, y: -size.height / 2 + 12)
                container.addChild(pip)
            }
        } else if isUnlocked {
            // A play mark where the medals will go.
            let mark = SKShapeNode(path: {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -3.5, y: 5))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: -3.5, y: -5))
                path.closeSubpath()
                return path
            }())
            mark.fillColor = StoryPalette.gold
            mark.strokeColor = .clear
            mark.position = CGPoint(x: 0, y: -size.height / 2 + 13)
            container.addChild(mark)
        } else {
            let lock = FilmUI.padlock(height: 11, color: Self.padlockColor)
            lock.position = CGPoint(x: 0, y: -size.height / 2 + 13)
            lock.name = "padlock"
            container.addChild(lock)
        }

        return container
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !exit.isTaken, !isChangingPage, let touch = touches.first else { return }
        touchStartLocation = touch.location(in: self)
        touchStartTime = touch.timestamp
        hasMoved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let startLocation = touchStartLocation else { return }

        let currentLocation = touch.location(in: self)
        if abs(currentLocation.x - startLocation.x) > 10 || abs(currentLocation.y - startLocation.y) > 10 {
            hasMoved = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            touchStartLocation = nil
            hasMoved = false
        }
        // Once a level or BACK has been chosen the grid is on its way out: no second
        // level, no paging, no dialog. A moving page answers nothing either.
        guard !exit.isTaken, !isChangingPage,
              let touch = touches.first,
              let startLocation = touchStartLocation else { return }

        let endLocation = touch.location(in: self)
        let deltaX = endLocation.x - startLocation.x
        let deltaY = endLocation.y - startLocation.y
        let duration = touch.timestamp - touchStartTime

        // Swipe detection parameters
        let minSwipeDistance: CGFloat = 50
        let maxSwipeDuration: TimeInterval = 0.5
        let maxVerticalDeviation: CGFloat = 100

        // A horizontal swipe pages the grid.
        //
        // Suppressed while the reset confirmation is up: it is modal, and a swipe across
        // it used to page the grid behind it just as a tap on the arrow zones did.
        if !isConfirmingReset &&
           abs(deltaX) > minSwipeDistance &&
           abs(deltaY) < maxVerticalDeviation &&
           duration < maxSwipeDuration {

            if deltaX < 0 && currentPage < totalPages - 1 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage + 1)
                return
            }

            if deltaX > 0 && currentPage > 0 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage - 1)
                return
            }
        }

        // If no swipe detected and no significant movement, treat as tap
        if !hasMoved {
            handleTap(at: endLocation)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartLocation = nil
        hasMoved = false
    }

    /// Whether the reset confirmation owns input: every touch, from the moment it opens
    /// until it has gone and anything it set off has finished.
    ///
    /// This used to be "a node named confirmationDialog exists", and dismissing renamed
    /// the dialog at once so it would stop answering. But it stayed on screen for its
    /// 0.2s fade, scrim and all, and the grid behind it is hit-tested with `nodes(at:)`,
    /// which no scrim can block — so the second tap of a double-tap on NO started
    /// whichever level sat under the button, and a swipe paged the grid behind a dialog
    /// that still looked modal.
    private var isConfirmingReset: Bool {
        return resetDialog != .closed
    }

    private func handleTap(at location: CGPoint) {
        // The confirmation dialog is modal, so it answers first and nothing behind it
        // can be reached — the arrows' hot zones in particular, which are measured in
        // scene space rather than against any node.
        if isConfirmingReset {
            handleConfirmationTap(at: location)
            return
        }

        let arrowTouchRadius: CGFloat = 36
        // The arrows live in the scaled content, so the tap is measured in its points.
        let point = convert(location, to: content)

        if let arrow = leftArrow, hypot(point.x - arrow.position.x, point.y - arrow.position.y) < arrowTouchRadius {
            if currentPage > 0 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage - 1)
            }
            return
        }

        if let arrow = rightArrow, hypot(point.x - arrow.position.x, point.y - arrow.position.y) < arrowTouchRadius {
            if currentPage < totalPages - 1 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage + 1)
            }
            return
        }

        if let button = FilmUI.button(at: location, under: self, names: ["backButton", "resetButton"]) {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            if button.name == "backButton" {
                handleBackButton()
            } else {
                handleResetButton()
            }
            return
        }

        // A tile: any node under the finger that belongs to one. Asked of every node at
        // the point, not just the topmost — the frame's viewfinder and the grade sit
        // above the grid and would otherwise answer for it.
        for node in nodes(at: location) {
            if let tile = FilmUI.namedAncestor(of: node, where: { $0.hasPrefix("levelButton_") }),
               let levelString = tile.name?.split(separator: "_").last,
               let level = Int(levelString) {
                handleLevelTap(level: level)
                return
            }
        }
    }

    /// Touch handling while the reset confirmation is up: YES, NO, or nothing at all.
    /// Once either has been chosen, nothing — the dialog is going, and is still modal
    /// until it has gone.
    private func handleConfirmationTap(at location: CGPoint) {
        guard resetDialog == .open,
              let dialog = childNode(withName: "confirmationDialog") else { return }

        switch FilmUI.button(at: location, under: dialog, names: ["confirmYes", "confirmNo"])?.name {
        case "confirmYes":
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            confirmReset()
        case "confirmNo":
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)
            dismissConfirmationDialog()
        default:
            // Swallowed. A destructive confirmation should not be dismissible by a
            // stray tap on the scrim, so unlike the settings panel there is no
            // tap-outside-to-close here.
            break
        }
    }

    private func changePage(_ newPage: Int) {
        guard !exit.isTaken, !isChangingPage, newPage != currentPage,
              (0..<totalPages).contains(newPage), let container = pageContainer else { return }
        isChangingPage = true
        touchStartLocation = nil
        hasMoved = false

        let isMovingForward = newPage > currentPage
        let travel = layoutSize.width * 0.6

        let slideOut = SKAction.moveBy(x: isMovingForward ? -travel : travel, y: 0, duration: 0.25)
        slideOut.timingMode = .easeIn
        let fadeOut = SKAction.fadeOut(withDuration: 0.25)

        container.run(SKAction.group([slideOut, fadeOut])) { [weak self, weak container] in
            guard let self = self, let container = container,
                  self.pageContainer === container else { return }
            self.currentPage = newPage
            container.position = CGPoint(
                x: self.gridCentre.x + (isMovingForward ? travel : -travel),
                y: self.gridCentre.y
            )
            self.loadPage(newPage)
            self.updatePaging()

            let slideIn = SKAction.moveTo(x: self.gridCentre.x, duration: 0.3)
            slideIn.timingMode = .easeOut
            container.run(SKAction.group([slideIn, SKAction.fadeIn(withDuration: 0.3)])) { [weak self, weak container] in
                guard let self = self, let container = container,
                      self.pageContainer === container else { return }
                self.isChangingPage = false
            }
        }
    }

    private func handleLevelTap(level: Int) {
        guard let button = levelButtons.first(where: { $0.name == "levelButton_\(level)" }) else { return }

        if levelManager.isLevelUnlocked(level) {
            exit.take()
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)

            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            button.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.startLevel(level)
            }
        } else {
            HapticManager.shared.warning()
            SoundManager.shared.playHitSound(on: self)

            // Refused: a shake, and the padlock flares red. Both are keyed and restart
            // from rest, so a second tap mid-refusal replays the feedback rather than
            // stacking a second one on top of the first.
            let shake = SKAction.sequence([
                SKAction.rotate(byAngle: -0.1, duration: 0.05),
                SKAction.rotate(byAngle: 0.2, duration: 0.1),
                SKAction.rotate(byAngle: -0.2, duration: 0.1),
                SKAction.rotate(byAngle: 0.1, duration: 0.05)
            ])
            button.removeAction(forKey: "refuse")
            button.zRotation = 0
            button.run(shake, withKey: "refuse")
            if let lock = button.childNode(withName: "padlock") as? SKShapeNode {
                lock.removeAction(forKey: "refuse")
                lock.strokeColor = StoryPalette.red
                lock.run(.sequence([
                    .wait(forDuration: 0.35),
                    .run { [weak lock] in lock?.strokeColor = Self.padlockColor }
                ]), withKey: "refuse")
            }
        }
    }

    private func handleBackButton() {
        exit.take()
        content.childNode(withName: "backButton")?.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.goToMenu()
        })
    }

    private func handleResetButton() {
        content.childNode(withName: "resetButton")?.run(UITheme.createButtonPressAnimation { [weak self] in
            self?.showConfirmationDialog()
        })
    }

    // MARK: - Reset confirmation

    /// A red-alert frame, the boss warning's language: red corners, the question in
    /// tracked red type, the consequence spelled out under it, and NO on the left where
    /// the thumb lands first.
    ///
    /// Layered explicitly, scrim → glass → everything on it. The view ignores sibling
    /// order, and the title's bloom hangs a step *below* its lettering, so with the glass
    /// on the same z as the type the bloom drew underneath the 92%-opaque glass and
    /// never showed.
    private func showConfirmationDialog() {
        guard !isConfirmingReset, !exit.isTaken else { return }
        resetDialog = .open

        let red = StoryPalette.red
        let overlay = SKSpriteNode(color: .black, size: CGSize(width: size.width + 4, height: size.height + 4))
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 100
        overlay.name = "confirmationOverlay"
        overlay.alpha = 0
        addChild(overlay)

        let scale = FilmUI.uiScale(for: size)
        let width = min(size.width / scale - 48, 330)
        // The pair is cut from the dialog's own width, the way the results card and the
        // pause menu cut theirs from their column. At the fixed half-column width the two
        // buttons came to 280pt, which overran the 272pt dialog a 320pt screen gets.
        let inset: CGFloat = 24
        let pairWidth = min(UITheme.Dimensions.buttonWidthHalf,
                            (width - inset * 2 - UITheme.Dimensions.buttonPairGap) / 2)
        let buttonHeight = UITheme.Dimensions.buttonHeightSecondary

        let title = FilmUI.title(L10n.LevelSelect.resetTitle, size: 26, color: StoryPalette.mix(red, .white, 0.25),
                                 glow: red, tracking: 4, maxWidth: width - 40)
        let message = FilmUI.label(L10n.LevelSelect.resetMessage, font: UITheme.Typography.fontRegular, size: 17,
                                   color: UITheme.Colors.textBody, tracking: 0.3, maxWidth: width - 36, minimumSize: 12)
        let warning = FilmUI.mono(L10n.LevelSelect.resetWarning.uppercased(), size: 11,
                                  color: red.withAlphaComponent(0.9), tracking: 1.5, maxWidth: width - 36)

        // Top to bottom: gap above, height.
        let rows: [(node: SKNode, gap: CGFloat, height: CGFloat)] = [
            (title, 28, title.frame.height),
            (message, 22, message.frame.height),
            (warning, 10, warning.frame.height)
        ]
        let height = rows.reduce(0) { $0 + $1.gap + $1.height } + 26 + buttonHeight + inset

        // Well clear of the scrim, so the glass can sit a few steps below the type
        // without dropping under the scrim itself.
        let dialog = SKNode()
        dialog.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dialog.zPosition = overlay.zPosition + 10
        dialog.name = "confirmationDialog"
        dialog.alpha = 0
        dialog.setScale(scale * 0.96)
        addChild(dialog)

        let glass = SKSpriteNode(color: FilmUI.glass, size: CGSize(width: width, height: height))
        glass.alpha = 0.92
        glass.zPosition = -3
        glass.name = "confirmationGlass"
        dialog.addChild(glass)
        let wash = SKSpriteNode(color: red, size: CGSize(width: width, height: height))
        wash.alpha = 0.05
        wash.zPosition = -2.5
        dialog.addChild(wash)
        let frame = SKShapeNode(rectOf: CGSize(width: width, height: height))
        frame.fillColor = .clear
        frame.strokeColor = red.withAlphaComponent(0.22)
        frame.lineWidth = 1
        dialog.addChild(frame)
        let brackets = FilmUI.addBrackets(to: dialog, size: CGSize(width: width, height: height), arm: 18,
                                          color: red, width: 1.5)
        for tube in brackets {
            tube.run(.repeat(.sequence([.fadeAlpha(to: 0.3, duration: 0.12), .fadeAlpha(to: 1, duration: 0.12)]), count: 3))
        }

        var cursor = height / 2
        for row in rows {
            cursor -= row.gap + row.height / 2
            row.node.position = CGPoint(x: 0, y: cursor)
            dialog.addChild(row.node)
            cursor -= row.height / 2
        }

        let buttonY = -height / 2 + inset + buttonHeight / 2
        let offset = (pairWidth + UITheme.Dimensions.buttonPairGap) / 2
        let noButton = UITheme.createButton(text: L10n.Common.no, color: StoryPalette.cyan,
                                            width: pairWidth, name: "confirmNo")
        noButton.position = CGPoint(x: -offset, y: buttonY)
        dialog.addChild(noButton)

        let yesButton = UITheme.createButton(text: L10n.Common.yes, color: red,
                                             width: pairWidth, name: "confirmYes")
        yesButton.position = CGPoint(x: offset, y: buttonY)
        dialog.addChild(yesButton)

        overlay.run(SKAction.fadeAlpha(to: 0.75, duration: 0.2))
        let open = SKAction.scale(to: scale, duration: 0.2)
        open.timingMode = .easeOut
        dialog.run(SKAction.group([SKAction.fadeIn(withDuration: 0.2), open]))
        dialog.run(FilmUI.glitchIn(dialog, delay: 0, amount: 4))
    }

    /// Fades the dialog out and hands input back only once it has gone — after running
    /// `then`, which is where YES rebuilds the grid, so no tap ever reaches a grid still
    /// showing the progress that was just cleared.
    private func dismissConfirmationDialog(then: (() -> Void)? = nil) {
        guard resetDialog == .open,
              let overlay = childNode(withName: "confirmationOverlay"),
              let dialog = childNode(withName: "confirmationDialog") else { return }
        resetDialog = .closing

        overlay.run(SKAction.fadeOut(withDuration: 0.2))
        dialog.run(SKAction.group([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.scale(to: dialog.xScale * 0.96, duration: 0.2)
        ])) { [weak self, weak overlay, weak dialog] in
            overlay?.removeFromParent()
            dialog?.removeFromParent()
            then?()
            self?.resetDialog = .closed
        }
    }

    private func confirmReset() {
        HapticManager.shared.warning()

        levelManager.resetProgress()

        // Rebuild once the dialog has gone, so the furniture, the tally and every tile
        // show the cleared progress.
        dismissConfirmationDialog { [weak self] in
            guard let self = self else { return }
            self.currentPage = 0
            self.removeAllChildren()
            self.buildScene(animated: false)
        }
    }

    #if DEBUG
    /// Puts the reset confirmation up, for the screenshot harness.
    func debugShowResetDialog() {
        showConfirmationDialog()
    }
    #endif

    private func startLevel(_ level: Int) {
        exit.present(from: self) { size in
            // Show the opening story for level 1, but only the first time — see
            // LevelManager.hasSeenOpeningStory.
            if level == 1 && !LevelManager.shared.hasSeenOpeningStory {
                return StoryScene(size: size, type: .opening, targetLevel: level)
            }

            let gameScene = GameScene(size: size)
            gameScene.currentLevel = level

            // Load weapon arsenal from previous level
            let weapons = LevelManager.shared.getLevelWeapons(level: level - 1)
            gameScene.startingBulletCount = weapons.bulletCount
            gameScene.startingSideMissileCount = weapons.sideMissileCount
            return gameScene
        }
    }

    private func goToMenu() {
        exit.present(from: self) { MenuScene(size: $0) }
    }
}
