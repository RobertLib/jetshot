//
//  DebugLaunch.swift
//  jetshot
//

#if DEBUG

import SpriteKit
import UIKit

/// Launch-argument harness for the App Store media pipeline.
///
/// `Tools/appstore_media.sh` has to put the game into states that are hours of real
/// play apart — level 40's boss in its third act, an eight-barrel arsenal, a x8
/// chain, round 25 of an endless run — and it has to do it deterministically, twice
/// per locale, on two devices, eight shots and six clips at a time. Playing there is
/// not an option, and neither is hand-editing the save, which is the thing this type
/// exists to avoid.
///
/// The whole file sits inside `#if DEBUG`, so none of it reaches a Release build and
/// the arguments cannot be reached on a shipped app however they are passed. The
/// `GameScene` and `CloudStorageManager` seams it calls are `#if DEBUG` too.
///
/// **Nothing written here reaches disk.** `-unlockall` seeds an in-memory store and
/// switches every write in `CloudStorageManager` into a no-op for the life of the
/// process — see `CloudStorageManager.installDemoStore(_:)`. Without that, one
/// screenshot run would overwrite the real save and then push the demo progress up to
/// iCloud, wiping it on every other device signed into the same account. That is a
/// mistake you get to make exactly once, so it is designed out rather than remembered.
///
/// ## Arguments
///
/// Where to start (`-levelselect` and `-endless` win over `-level`; the default is
/// the menu):
///
///     -levelselect            the level grid, on the page holding `-level`
///     -level <1...50>         straight into a campaign level
///     -endless                straight into an endless run
///
/// What the run starts as:
///
///     -unlockall              in-memory progress: all 50 levels, stars, records
///     -guns <1...8>           barrels on the ship
///     -missiles <0...2>       side missile launchers
///     -round <n>              endless: begin at round n
///     -banner                 endless: keep the round banner up, for a screenshot
///     -chain <n>              seed the kill chain, and hold it lit (see `holdPose`)
///     -powerups a,b,c         activate power-ups on entry (see `powerUp(named:)`)
///     -boss [fraction]        skip to the boss, damaged to `fraction` health (0.3)
///
/// How it plays itself:
///
///     -autopilot              a bot flies the ship and dodges
///     -invincible             damage is refused, so a 25 s clip cannot end in a death
///     -nointro                run the level-intro card at 25x instead of watching it
///
/// Note that the level is started regardless of `-nointro` — see
/// `GameScene.debugReleaseIntro(fastForward:)`, which explains the deadlock this
/// route would otherwise hit every time.
///
enum DebugLaunch {

    // MARK: - Options

    enum Destination {
        case menu
        case levelSelect
        case level(Int)
        case endless
    }

    struct Options {
        var unlockAll = false
        var destination: Destination = .menu
        /// Which level `-level` named, kept even when the destination is the grid:
        /// `-levelselect -level 25` opens the page holding level 25 rather than the
        /// first one. Twelve tiles numbered 1 to 12 undersell a fifty-level game.
        var anchorLevel: Int?
        var guns: Int?
        var missiles: Int?
        var round: Int?
        /// Hold the endless round banner up. Wanted by the screenshot, *not* by the
        /// preview clip: the banner lives about 1.65 s, so holding it means a new one
        /// fades in as the last fades out, and five seconds of video containing three
        /// of those cycles reads as a flicker rather than as a label.
        var holdBanner = false
        var chain: Int?
        var powerUps: [PowerUpType] = []
        var bossFraction: CGFloat?
        var autopilot = false
        var invincible = false
        var skipIntro = false

        /// Whether anything at all was asked for. A normal launch from Xcode passes
        /// none of these, and everything in this type then stays out of the way.
        var isActive: Bool {
            if case .menu = destination {} else { return true }
            return unlockAll || anchorLevel != nil || guns != nil || missiles != nil
                || round != nil || holdBanner
                || chain != nil || !powerUps.isEmpty || bossFraction != nil
                || autopilot || invincible || skipIntro
        }
    }

    /// Parsed once. `ProcessInfo.arguments` does not change during a run, and the
    /// parse is reached from `update(_:)` at 60 Hz once the autopilot is flying.
    static let options: Options = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ args: [String]) -> Options {
        var options = Options()

        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.count > index + 1 else { return nil }
            let next = args[index + 1]
            // A bare flag followed by another flag has no value — `-boss` on its own
            // is legal and means "the default fraction".
            return next.hasPrefix("-") ? nil : next
        }

        options.unlockAll = args.contains("-unlockall")
        options.autopilot = args.contains("-autopilot")
        options.invincible = args.contains("-invincible")
        options.skipIntro = args.contains("-nointro")
        options.holdBanner = args.contains("-banner")

        if let raw = value(after: "-level"), let level = Int(raw),
           (1...GameConfiguration.totalLevels).contains(level) {
            options.anchorLevel = level
        }

        if args.contains("-levelselect") {
            options.destination = .levelSelect
        } else if args.contains("-endless") {
            options.destination = .endless
        } else if let level = options.anchorLevel {
            options.destination = .level(level)
        }

        options.guns = value(after: "-guns").flatMap(Int.init)
            .map { min(max($0, 1), GameConfiguration.maxBulletCount) }
        options.missiles = value(after: "-missiles").flatMap(Int.init)
            .map { min(max($0, 0), GameConfiguration.maxSideMissileCount) }
        options.round = value(after: "-round").flatMap(Int.init).map { max($0, 1) }
        options.chain = value(after: "-chain").flatMap(Int.init).map { max($0, 0) }

        if let list = value(after: "-powerups") {
            options.powerUps = list.split(separator: ",").compactMap { powerUp(named: String($0)) }
        }

        if args.contains("-boss") {
            let fraction = value(after: "-boss").flatMap(Double.init) ?? 0.3
            options.bossFraction = CGFloat(min(max(fraction, 0.05), 1.0))
        }

        return options
    }

    /// The names `-powerups` accepts, lower-cased and without punctuation. Only the
    /// ones worth photographing are listed — a nuke clears the screen, which is the
    /// opposite of what a screenshot wants.
    static func powerUp(named name: String) -> PowerUpType? {
        switch name.lowercased() {
        case "shield": return .shield
        case "barrier": return .barrier
        case "rapidfire": return .rapidFire
        case "magnet": return .magnet
        case "lightning": return .lightning
        case "slowmotion", "slowmo": return .slowMotion
        case "scorex2", "score": return .scoreMultiplier
        default: return nil
        }
    }

    // MARK: - Launch

    /// Called from `AppDelegate` before anything touches `CloudStorageManager.shared`.
    ///
    /// The ordering is load bearing: `CloudStorageManager` starts its iCloud merge from
    /// its own initialiser, so the demo store has to be installed before the singleton
    /// is first resolved or the merge will have already read — and, worse, be about to
    /// write — the real account's progress.
    static func prepare() {
        guard options.unlockAll else { return }
        CloudStorageManager.installDemoStore(demoProgress())
        print("[DEBUG] Demo progress installed — all writes to UserDefaults and iCloud are no-ops")
    }

    /// A finished game, in memory. Fifty levels cleared, three stars on most of them,
    /// a full arsenal from level 5 on, and an endless record worth putting on a card.
    ///
    /// The numbers are shaped rather than uniform, because a grid of identical
    /// three-star tiles is the one thing that reads as fake in a screenshot.
    private static func demoProgress() -> [String: Any] {
        var scores: [String: Int] = [:]
        var stars: [String: Int] = [:]
        var weapons: [String: [String: Int]] = [:]

        for level in 1...GameConfiguration.totalLevels {
            // Rising, with the boss payout stepping up every fifth level.
            scores["\(level)"] = 4_200 + level * 1_850 + (level % 5 == 0 ? 6_000 : 0)
            // Three stars almost everywhere, two on a scattered few — the coin rate
            // that decides a rating is not something anyone holds at 70% for fifty
            // levels running.
            stars["\(level)"] = (level % 7 == 3) ? 2 : 3
            weapons["\(level)"] = [
                "bulletCount": min(GameConfiguration.maxBulletCount, 2 + level),
                "sideMissileCount": min(GameConfiguration.maxSideMissileCount, level / 4)
            ]
        }

        return [
            CloudStorageManager.Keys.completedLevels: Array(1...GameConfiguration.totalLevels),
            CloudStorageManager.Keys.levelScores: scores,
            CloudStorageManager.Keys.levelStars: stars,
            CloudStorageManager.Keys.levelWeapons: weapons,
            CloudStorageManager.Keys.endlessRecords: ["bestScore": 486_300, "bestRound": 27]
        ]
    }

    /// The scene to present instead of the menu, or nil for an ordinary launch.
    @MainActor
    static func makeInitialScene(size: CGSize) -> SKScene? {
        let options = self.options
        guard options.isActive else { return nil }

        switch options.destination {
        case .menu:
            return nil

        case .levelSelect:
            // `LevelSelectScene` opens on the page holding `startLevel`, so `-level`
            // doubles as the page anchor here. Defaults to the first page.
            return LevelSelectScene(size: size, startLevel: options.anchorLevel ?? 1)

        case .level(let level):
            let scene = GameScene(size: size)
            scene.currentLevel = level
            applyArsenal(to: scene, level: level)
            return scene

        case .endless:
            let scene = GameScene(size: size)
            scene.isEndless = true
            applyArsenal(to: scene, level: 1)
            return scene
        }
    }

    /// The ship the run starts with. `-guns` / `-missiles` win; otherwise the arsenal
    /// the player would have carried in from the previous level, which with
    /// `-unlockall` is a full one from level 6 on.
    @MainActor
    private static func applyArsenal(to scene: GameScene, level: Int) {
        let carried = LevelManager.shared.getLevelWeapons(level: max(1, level - 1))
        scene.startingBulletCount = options.guns ?? carried.bulletCount
        scene.startingSideMissileCount = options.missiles ?? carried.sideMissileCount
    }

    // MARK: - Posing a scene

    /// Applies everything that can only be done once the scene has finished building
    /// itself: the chain, the power-ups, the boss, the endless round.
    ///
    /// Called from the tail of `GameScene.didMove(to:)`'s deferred setup, which is the
    /// first moment `player`, the managers and the HUD all exist.
    @MainActor
    static func apply(to scene: GameScene) {
        let options = self.options
        guard options.isActive else { return }

        // Unconditional, and `debugReleaseIntro` explains why: without it this route
        // never starts the level at all. `-nointro` only decides whether the card is
        // also fast-forwarded.
        scene.debugReleaseIntro(
            fastForward: options.skipIntro || options.autopilot || options.bossFraction != nil
        )

        if let round = options.round, scene.isEndless {
            scene.debugSetEndlessRound(round)
        }

        for type in options.powerUps {
            scene.debugActivatePowerUp(type)
        }

        if let chain = options.chain, chain > 0 {
            scene.debugSeedChain(chain)
        }

        if let fraction = options.bossFraction {
            scene.debugForceBoss(healthFraction: fraction)
        }

        if options.invincible {
            scene.debugSetInvulnerable(true)
        }
    }

    // MARK: - Autopilot

    /// Nodes that end a run, and how far the bot insists on staying from each. A bullet
    /// is small and fast, a boss is enormous and stationary — one radius for all of them
    /// had the ship either grazing bullets or refusing to approach the bottom third.
    private static let threats: [(name: String, clearance: CGFloat)] = [
        ("enemyBullet", 78),
        ("enemy", 92),
        ("asteroid", 96),
        ("obstacle", 104),
        ("bosslaser", 130),
        ("laserBeam", 130)
    ]

    /// Nodes worth steering into when nothing is shooting at the lane.
    private static let pickups = ["powerup", "coin"]

    /// Clocks for the three states that decay faster than a screenshot can be taken.
    ///
    /// A chain lapses after 1.8 s without a kill, a shield lasts five seconds and the
    /// round banner is gone in under two — so a shot posed at launch and captured ten
    /// seconds later would show none of them. These hold the pose instead. Everything
    /// they re-assert is true of the run: the chain is rebuilt by registering kills, the
    /// power-ups go through their real activators, and the banner prints the run's own
    /// `endlessRound`.
    ///
    /// Main-actor state, mutated only from `steer`, which is `@MainActor`.
    @MainActor private static var chainClock: TimeInterval = 0
    @MainActor private static var powerUpClock: TimeInterval = 0
    @MainActor private static var bannerClock: TimeInterval = 0

    /// Flies the ship for one frame.
    ///
    /// Called from `GameScene.update(_:)` *before* the firing block, because it drives
    /// the ship through the same `isTouching` / `touchLocation` pair a real drag sets —
    /// which is what keeps auto-fire, weapon heat and the chain behaving exactly as they
    /// do for a player. A bot that moved the node directly would record footage of a
    /// ship that never shoots.
    ///
    /// The policy is deliberately simple and stateless: sample the width at a fixed
    /// pitch, score every candidate lane by how far the nearest threat is from it,
    /// break ties towards pickups and towards standing still, and drag one step that
    /// way. It does not plan, and it does not need to — a preview clip is 25 seconds
    /// and `-invincible` covers the frames where it is wrong.
    @MainActor
    static func steer(_ scene: GameScene, deltaTime: TimeInterval) {
        let options = self.options
        guard options.autopilot else { return }

        // Held true rather than set once: the damage path clears `isInvulnerable` on a
        // timer of its own, and re-asserting it every frame is cheaper than threading a
        // second flag through four collision guards.
        if options.invincible {
            scene.debugSetInvulnerable(true)
        }

        holdPose(scene, deltaTime: deltaTime)

        let player = scene.debugPlayer
        let width = scene.size.width
        let flightY = scene.debugSafeAreaBottom + 110

        // Threats and pickups, gathered once for the whole scan. Only what is still
        // above the ship can reach it, so everything below the flight line is dropped.
        var hazards: [(point: CGPoint, clearance: CGFloat)] = []
        for entry in threats {
            for point in scene.debugPositions(named: entry.name, above: flightY - 40) {
                hazards.append((point, entry.clearance))
            }
        }
        let wanted = pickups.flatMap { scene.debugPositions(named: $0, above: flightY - 60) }

        // Score each lane. `danger` is how far inside a threat's clearance the lane
        // sits, summed — so a lane with two near misses loses to one with a single
        // wider one, which is the behaviour that keeps the ship out of crossfire.
        let step: CGFloat = 24
        var bestX = player.position.x
        var bestScore = -CGFloat.greatestFiniteMagnitude
        var x = step
        while x < width - step {
            var score: CGFloat = 0
            for hazard in hazards {
                let dx = x - hazard.point.x
                let dy = flightY - hazard.point.y
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < hazard.clearance {
                    score -= (hazard.clearance - distance) * 4
                }
            }
            for target in wanted {
                let dx = abs(x - target.x)
                if dx < 140 { score += (140 - dx) * 0.35 }
            }
            // Prefer not to cross the screen for a marginal gain: a bot that
            // teleports between lanes looks like a bug in the recording.
            score -= abs(x - player.position.x) * 0.25
            if score > bestScore {
                bestScore = score
                bestX = x
            }
            x += step
        }

        // Move a bounded distance per frame, so the drag reads as a hand rather than a
        // cut. 620 pt/s is a brisk but human sweep across a 400 pt-wide phone.
        let maxTravel = CGFloat(deltaTime) * 620
        let dx = max(-maxTravel, min(maxTravel, bestX - player.position.x))
        let targetX = player.position.x + dx

        // `moveToInstant` lifts the ship 50 points above the touch, the same offset a
        // thumb gets, so the touch point is placed that far below the flight line.
        scene.debugDrag(to: CGPoint(x: targetX, y: flightY - 50))
    }

    /// Keeps the chain lit, the power-ups running and the round banner up, so that a
    /// screenshot taken whenever the shell gets round to it still shows what the launch
    /// arguments asked for. See `chainClock`.
    @MainActor
    private static func holdPose(_ scene: GameScene, deltaTime: TimeInterval) {
        let options = self.options

        // One kill every 1.2 s, comfortably inside `ComboRules.minWindow` of 1.8 s, so
        // the chain never lapses. It also creeps upwards, which is why the shell's
        // settle times are short on the chain shot: `-chain 40` captured six seconds
        // later reads about 45, and x8 either way.
        if options.chain != nil {
            chainClock += deltaTime
            if chainClock >= 1.2 {
                chainClock = 0
                scene.debugSeedChain(1)
            }
        }

        // Re-activated well inside the shortest duration in the set (`shield`, at five
        // seconds), so every bar in the power-up HUD stays on screen.
        if !options.powerUps.isEmpty {
            powerUpClock += deltaTime
            if powerUpClock >= 3.0 {
                powerUpClock = 0
                for type in options.powerUps { scene.debugActivatePowerUp(type) }
            }
        }

        if options.holdBanner, scene.isEndless {
            bannerClock += deltaTime
            // 1.5 s, and the number is the banner's own lifetime rather than a round
            // one: `announceEndlessRound()` fades in over 0.2 s, holds 0.9 s and fades
            // out over 0.4 s. Re-announcing just inside that has the next label fading
            // in as the last fades out, so there is always one on screen — at 3.5 s the
            // capture landed in the gap about half the time.
            if bannerClock >= 1.5 {
                bannerClock = 0
                scene.debugAnnounceEndlessRound()
            }
        }
    }
}

#endif
