//
//  BossManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 26.10.2025.
//

import SpriteKit

/// Manages boss spawning, attacks, and defeat animations.
/// Handles boss-specific combat mechanics and visual effects.
class BossManager {
    private weak var scene: GameScene?
    private var boss: Boss?
    private var isAttacking: Bool = false
    private weak var player: Player?

    /// Act the fight is currently in, so a crossing can be detected on the damage that
    /// causes it. See `BossPhaseRules`.
    private var currentPhase: Int = 0

    /// Index into the boss's available patterns of the attack that just fired, so the
    /// next draw can avoid repeating it.
    ///
    /// A plain `randomElement()` over a long list still lands the same attack twice in
    /// a row now and then, and a repeated barrage reads as the fight glitching rather
    /// than as bad luck.
    private var lastPatternIndex: Int?

    /// Draws since the boss last used its signature move. Past a few, the signature is
    /// drawn on purpose: it is what makes this machine recognisably itself, and a fair
    /// random draw can starve it for half a fight.
    private var drawsSinceSignature = 0

    /// Hosts the attack sequences in flight, so a phase change can stop all of them at
    /// once. A child of the boss, so it pauses and dies with it.
    private var volleys: SKNode?

    /// Node names for what an attack leaves on the playfield besides bullets: beams
    /// (which kill), and warnings, portals and markers (which do not). Swept on a phase
    /// change, on the kill and on teardown.
    private static let beamName = "bosslaser"
    private static let effectName = "bossFX"

    /// The ring a wind-up collapses onto the boss. A child of the boss rather than of the
    /// playfield, so `clearHazards()` never reached it: it used to keep closing for up to
    /// 0.6 s into a phase change, and over the exploding boss.
    private static let telegraphName = "bossTelegraphRing"

    /// How fast the fight runs: 1 normally, less under SLOW MO. See `setTimeScale(_:)`.
    private(set) var timeScale: CGFloat = 1

    /// The boss's rounds in flight, so a change of time scale can reach them. Weak: a
    /// round that has left the scene drops out on its own.
    private let rounds = NSHashTable<SKNode>.weakObjects()

    init(scene: GameScene) {
        self.scene = scene
    }

    func setPlayer(_ player: Player) {
        self.player = player
        boss?.target = player
    }

    func spawnBoss(level: Int, completion: @escaping () -> Void) {
        guard let scene = scene else { return }

        let config = BossConfig.config(for: level)
        let newBoss = Boss(config: config, sceneSize: scene.size)
        newBoss.target = player
        // A boss arriving in the middle of SLOW MO arrives slowed.
        newBoss.speed = timeScale
        boss = newBoss
        drawsSinceSignature = 0

        let host = SKNode()
        host.name = "bossVolleys"
        newBoss.addChild(host)
        volleys = host

        scene.gameContentNode.addChild(newBoss)
        newBoss.addHealthBarToScene(scene)

        // Weak capture: the closure is retained by an action on the boss, which this
        // manager owns — capturing self strongly closed a manager → boss → closure →
        // manager cycle for the length of the fight.
        newBoss.enterScene { [weak self] in
            self?.startAttacking()
            completion()
        }
    }

    func startAttacking() {
        isAttacking = true
        currentPhase = boss?.currentPhase ?? 0
        scheduleNextAttack()
    }

    /// Schedules the next attack `extra` seconds later than the cadence alone would:
    /// the time the attack just launched is still busy playing out.
    private func scheduleNextAttack(after extra: TimeInterval = 0) {
        guard isAttacking, let boss = boss, boss.isAlive() else { return }

        // A cornered boss presses harder. Scaling the whole range rather than the
        // minimum keeps the rhythm irregular in every act.
        let scale = BossPhaseRules.attackDelayScale(forPhase: currentPhase)
        let delay = TimeInterval.random(
            in: (GameConfiguration.bossAttackDelayMin * scale)...(GameConfiguration.bossAttackDelayMax * scale)
        ) + extra

        guard let pattern = nextAttack() else { return }
        let telegraph = BossPhaseRules.telegraphDuration(for: pattern)

        // Wind up, then fire. The warning comes out of the gap, not after it.
        let leadIn = max(0, delay - telegraph)

        // Use SKAction instead of DispatchQueue to respect pause state
        let sequence = SKAction.sequence([
            SKAction.wait(forDuration: leadIn),
            SKAction.run { [weak self] in
                self?.playTelegraph(duration: telegraph)
            },
            SKAction.wait(forDuration: telegraph),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                let busy = self.performAttack(pattern)
                self.scheduleNextAttack(after: busy)
            }
        ])
        boss.run(sequence, withKey: "bossAttackSchedule")
    }

    #if DEBUG
    /// Set by `DebugLaunch` (`-bossattack`): every attack the boss draws is this one.
    static var debugForcedPattern: BossAttackPattern?
    #endif

    /// Draws the next attack, or nil if the boss has nothing available.
    private func nextAttack() -> BossAttackPattern? {
        guard let boss = boss else { return nil }
        #if DEBUG
        if let forced = Self.debugForcedPattern { return forced }
        #endif

        let available = boss.availableAttackPatterns()
        guard !available.isEmpty else { return nil }

        let signature = boss.config.archetype.signature
        var index = Int.random(in: 0..<available.count)
        if drawsSinceSignature >= 3, let wanted = available.firstIndex(of: signature), wanted != lastPatternIndex {
            index = wanted
        } else if available.count > 1, let last = lastPatternIndex, index == last {
            // One deterministic step aside rather than a re-roll loop: it cannot spin,
            // and over many draws it is indistinguishable from rejection sampling.
            index = (index + 1) % available.count
        }
        lastPatternIndex = index
        drawsSinceSignature = available[index] == signature ? 0 : drawsSinceSignature + 1
        return available[index]
    }

    /// The wind-up: the boss swells, its muzzles gather light and a ring collapses onto
    /// it, then it fires.
    private func playTelegraph(duration: TimeInterval) {
        guard let boss = boss, boss.isAlive() else { return }

        boss.windUp(duration: duration)

        let ring = LightRing(segments: 32, color: boss.telegraphColor)
        ring.name = Self.telegraphName
        let outer = boss.bossSize * 0.95, inner = boss.bossSize * 0.32
        ring.set(radius: outer, width: 1.6)
        ring.zPosition = -1
        ring.alpha = 0
        boss.addChild(ring)
        let close = SKAction.customAction(withDuration: duration) { node, elapsed in
            let f = elapsed / CGFloat(max(0.01, duration))
            let e = f * f
            (node as? LightRing)?.set(radius: outer + (inner - outer) * e, width: 1.6 + 1.2 * f)
            node.alpha = min(1, f * 2.5) * 0.9
        }
        ring.run(SKAction.sequence([close, SKAction.fadeOut(withDuration: 0.1), SKAction.removeFromParent()]))
    }

    /// Runs the escalation when the boss crosses a health threshold: everything stops,
    /// the boss flares, and it comes back attacking faster and with more of its list.
    private func advanceToPhase(_ phase: Int) {
        guard let boss = boss, boss.isAlive() else { return }

        currentPhase = phase
        lastPatternIndex = nil

        // Cancel the pending attack outright, and anything still playing out. Letting a
        // wind-up that started in the previous act land in the middle of the transition
        // is exactly the kind of unreadable moment the telegraph exists to remove.
        boss.removeAction(forKey: "bossAttackSchedule")
        boss.cancelWindUp()
        stopEverything()

        boss.playPhaseTransitionEffect()

        if let scene = scene {
            scene.shakeCamera(intensity: 12.0, duration: 0.4)
            SoundManager.shared.playBossAppearSound(on: scene)
            HapticManager.shared.heavyTap()
        }

        // Resume on the boss's own clock so a pause holds the breather too.
        boss.run(SKAction.sequence([
            SKAction.wait(forDuration: BossPhaseRules.phaseTransitionPause),
            SKAction.run { [weak self] in
                self?.scheduleNextAttack()
            }
        ]), withKey: "bossPhaseResume")
    }

    /// Stops every attack in flight: its sequences, its beams and warnings, and
    /// whatever it was doing to the boss.
    private func stopEverything() {
        volleys?.removeAllActions()
        clearHazards()
        clearTelegraph()
        if let boss = boss, boss.isAlive() { boss.cancelManoeuvre() }
    }

    private func clearTelegraph() {
        guard let boss = boss else { return }
        for ring in boss.children where ring.name == Self.telegraphName {
            ring.removeAllActions()
            ring.removeFromParent()
        }
    }

    private func clearHazards() {
        guard let content = scene?.gameContentNode else { return }
        var doomed: [SKNode] = []
        content.enumerateChildNodes(withName: Self.beamName) { node, _ in doomed.append(node) }
        content.enumerateChildNodes(withName: Self.effectName) { node, _ in doomed.append(node) }
        for node in doomed {
            node.removeAllActions()
            node.removeFromParent()
        }
    }

    /// Fires `pattern` and returns how long it keeps the boss busy beyond its cadence:
    /// until its last round has left, its last beam has gone out and the boss has been
    /// handed back its flight path.
    ///
    /// Every pattern reports its own length. The older ones used to report nothing, so a
    /// 1.7 s double spiral counted as instantaneous and, in the last act, the next attack
    /// was winding up while the spiral was still pouring out.
    ///
    /// Internal rather than private so `jetshotTests` can hold every pattern to that.
    func performAttack(_ pattern: BossAttackPattern) -> TimeInterval {
        guard let boss = boss, scene != nil, boss.isAlive() else { return 0 }
        lastAttackVolleyLength = 0

        switch pattern {
        case .straightShot: return shootStraight()
        case .doubleShot: return shootDouble()
        case .tripleShot: return shootTriple()
        case .spread: return shootSpread()
        case .aimed: return shootAimed()
        case .spiral: return shootSpiral()
        case .wave: return shootWave()
        case .burst: return shootBurst()
        case .homing: return shootHoming()
        case .laser: return shootLaser()
        case .circularBarrage: return shootCircularBarrage()
        case .cascade: return shootCascade()
        case .doubleSpiral: return shootDoubleSpiral()
        case .barrageRain: return shootBarrageRain()
        case .zigzagPattern: return shootZigzagPattern()
        case .sectorSweep: return shootSectorSweep()
        case .podVolley: return podVolley()
        case .eyeLance: return eyeLance()
        case .swoop: return swoop()
        case .scytheArcs: return scytheArcs()
        case .orbitalSpiral: return orbitalSpiral()
        case .ringPulse: return ringPulse()
        case .mineLayer: return mineLayer()
        case .broodSwarm: return broodSwarm()
        case .sweepBeam: return sweepBeam()
        case .prismSplit: return prismSplit()
        case .segmentVolley: return segmentVolley()
        case .coilBurst: return coilBurst()
        case .blink: return blink()
        case .riftPortals: return riftPortals()
        case .latticeWalls: return latticeWalls()
        case .hyperShift: return hyperShift()
        case .implosion: return implosion()
        case .accretion: return accretion()
        }
    }

    /// The length of the longest volley the attack now playing put on the host, for
    /// `jetshotTests`: what `performAttack` has to report at the very least.
    private(set) var lastAttackVolleyLength: TimeInterval = 0

    // MARK: - Time scale

    /// Runs the fight at `scale` of its pace — SLOW MO's 0.5 — or back at 1.
    ///
    /// Slow motion used to set `speed` on enemy rounds and nothing else here, which did
    /// nothing useful: the boss, its cadence and its volleys ran at full pace, its rounds
    /// fly on physics velocity that `speed` does not touch, and slowing only their actions
    /// bent the patterns out of shape — a curving round turned at half the rate over the
    /// same ground, a seeker steered half as often, a mine flew twice as far before it
    /// burst. So action time, velocity and damping are scaled together: every pattern
    /// traces the same shape, only slower.
    ///
    /// Cheap to call every tick: only a change of scale walks the rounds in flight, and
    /// rounds fired while slowed leave slowed.
    func setTimeScale(_ scale: CGFloat) {
        let scale = max(0.05, scale)
        // Every call, so a boss that has arrived since the last one picks it up. Not a
        // dead one: its explosions keep their own pace (see `bossTakeDamage`).
        if let boss = boss, boss.healthFraction > 0 { boss.speed = scale }
        guard scale != timeScale else { return }
        let ratio = scale / timeScale
        timeScale = scale

        for round in rounds.allObjects where round.parent != nil {
            round.speed = scale
            if let body = round.physicsBody {
                body.velocity = CGVector(dx: body.velocity.dx * ratio, dy: body.velocity.dy * ratio)
                body.linearDamping *= ratio
            }
        }
        // Beams and the furniture of attacks keep their own time: how long a warning
        // shows before its beam, when a portal fires.
        guard let content = scene?.gameContentNode else { return }
        for name in [Self.beamName, Self.effectName] {
            content.enumerateChildNodes(withName: name) { node, _ in node.speed = scale }
        }
    }

    /// Whether `node` is one of the boss's rounds, whose velocity `setTimeScale(_:)`
    /// already scales — anything else that scales hostile rounds must leave it alone.
    func ownsRound(_ node: SKNode) -> Bool {
        rounds.contains(node)
    }

    // MARK: - Helpers

    private var tier: Int { boss?.config.tier ?? 0 }

    /// The boss's core muzzle now. Read at the moment each round leaves, not when the
    /// attack began: the boss keeps flying through a long volley, and rounds that
    /// appeared where it used to be read as coming out of empty space.
    private func core() -> CGPoint {
        boss?.coreMuzzle ?? .zero
    }

    /// The live weapon muzzles' current positions, left to right.
    private func weapons() -> [CGPoint] {
        guard let boss = boss else { return [] }
        return boss.liveMuzzles().compactMap { boss.muzzle($0) }
    }

    private func angleToPlayer(from point: CGPoint) -> CGFloat {
        guard let player = player else { return -.pi / 2 }
        return atan2(player.position.y - point.y, player.position.x - point.x)
    }

    private var fighting: Bool { boss?.isAlive() ?? false }

    /// Round `index` of a fan of `count`, `width` radians across, centred on its aim:
    /// the first round on one edge, the last on the other.
    ///
    /// Shared so the divisor cannot drift again. The circular barrage divided by
    /// `count + 2` and the spiral by `count`, which tipped both fans to one side — the
    /// barrage's covered −0.9…+0.41 rad, so the boss's lower right was always safe.
    nonisolated static func fanAngle(_ index: Int, of count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        return (CGFloat(index) / CGFloat(count - 1) - 0.5) * width
    }

    /// Runs `steps` one after another on the volley host, each after its wait, and
    /// returns how long that takes: from now until the last step has run.
    @discardableResult
    private func volley(_ steps: [(TimeInterval, () -> Void)]) -> TimeInterval {
        var actions: [SKAction] = []
        var length: TimeInterval = 0
        for (wait, body) in steps {
            if wait > 0 { actions.append(.wait(forDuration: wait)) }
            length += max(0, wait)
            actions.append(.run { [weak self] in
                guard self?.fighting == true else { return }
                body()
            })
        }
        volleys?.run(.sequence(actions))
        lastAttackVolleyLength = max(lastAttackVolleyLength, length)
        return length
    }

    /// The outermost live gun on each side: the leftmost and the rightmost, or the one
    /// there is. Not `weapons().prefix(2)` — the guns come sorted left to right, so on a
    /// boss with four of them that was both left-hand guns and nothing on the right.
    private func outerGuns() -> [CGPoint] {
        let guns = weapons()
        guard guns.count > 2, let left = guns.first, let right = guns.last else { return guns }
        return [left, right]
    }

    /// A short flash of the boss's light where a round leaves it.
    private func muzzleFlash(at point: CGPoint, radius: CGFloat = 10) {
        guard let content = scene?.gameContentNode, let boss = boss else { return }
        let flash = NeonFX.flashPoint(at: point, radius: radius, color: boss.telegraphColor, duration: 0.12, growTo: 1.6)
        flash.zPosition = 89
        content.addChild(flash)
    }

    private func shootSound() {
        guard let scene = scene else { return }
        SoundManager.shared.playEnemyShootSound(on: scene)
    }

    /// A node for an attack's furniture — a warning, a portal, a marker — swept with
    /// the rest of the boss's hazards.
    private func effectNode(at point: CGPoint = .zero) -> SKNode {
        let node = SKNode()
        node.name = Self.effectName
        node.position = point
        node.zPosition = 84
        node.speed = timeScale
        scene?.gameContentNode.addChild(node)
        return node
    }

    // MARK: - Attack Patterns

    private func shootStraight() -> TimeInterval {
        let from = core()
        createBullet(at: from, angle: -.pi / 2)
        muzzleFlash(at: from)
        shootSound()
        return 0
    }

    /// From the two outermost guns if the boss has them, else either side of its core.
    private func pair(spacing: CGFloat) -> [CGPoint] {
        let guns = outerGuns()
        if guns.count == 2 { return guns }
        let c = core()
        return [CGPoint(x: c.x - spacing, y: c.y), CGPoint(x: c.x + spacing, y: c.y)]
    }

    private func shootDouble() -> TimeInterval {
        for point in pair(spacing: 30) {
            createBullet(at: point, angle: -.pi / 2)
            muzzleFlash(at: point)
        }
        shootSound()
        return 0
    }

    private func shootTriple() -> TimeInterval {
        let points = pair(spacing: 40) + [core()]
        for point in points {
            createBullet(at: point, angle: -.pi / 2)
            muzzleFlash(at: point)
        }
        shootSound()
        return 0
    }

    private func shootSpread() -> TimeInterval {
        let from = core()
        let angles: [CGFloat] = [-0.8, -0.5, -0.2, 0.2, 0.5, 0.8]
        for angle in angles {
            createBullet(at: from, angle: -.pi / 2 + angle)
        }
        muzzleFlash(at: from, radius: 14)
        shootSound()
        return 0
    }

    private func shootAimed() -> TimeInterval {
        let from = core()
        createBullet(at: from, angle: angleToPlayer(from: from), speed: 300)
        if tier >= 3 {
            for gun in outerGuns() {
                createBullet(at: gun, angle: angleToPlayer(from: gun), speed: 270)
            }
        }
        muzzleFlash(at: from)
        shootSound()
        return 0
    }

    private func shootSpiral() -> TimeInterval {
        let bulletCount = 10
        return volley((0..<bulletCount).map { i in
            (0.08, { [weak self] in
                guard let self = self else { return }
                let spiralSpread = Self.fanAngle(i, of: bulletCount, width: 1.2)
                self.createBullet(at: self.core(), angle: -.pi / 2 + spiralSpread, speed: 200)
                if i % 3 == 0 { self.shootSound() }
            })
        })
    }

    private func shootWave() -> TimeInterval {
        let bulletCount = 8
        return volley((0..<bulletCount).map { i in
            (0.1, { [weak self] in
                guard let self = self else { return }
                let angle = Self.fanAngle(i, of: bulletCount, width: 1.6)
                self.createBullet(at: self.core(), angle: -.pi / 2 + angle)
                if i % 2 == 0 { self.shootSound() }
            })
        })
    }

    private func shootBurst() -> TimeInterval {
        return volley((0..<5).map { i in
            (i == 0 ? 0 : 0.1, { [weak self] in
                guard let self = self else { return }
                for point in self.pair(spacing: 40) + [self.core()] {
                    self.createBullet(at: point, angle: -.pi / 2)
                }
                if i % 2 == 0 { self.shootSound() }
            })
        })
    }

    private func shootHoming() -> TimeInterval {
        guard let scene = scene, player != nil else {
            return shootAimed()
        }
        // A seeker from the outermost gun on each side, or from the core if it has none.
        let sources = outerGuns()
        for from in sources.isEmpty ? [core()] : sources {
            launchSeeker(from: from, speed: 150, turn: 0.05, steps: 100)
            muzzleFlash(at: from, radius: 13)
        }
        SoundManager.shared.playPowerUpSound(on: scene)  // Different sound for homing missiles
        return 0
    }

    /// A round that steers towards the ship for `steps` twentieths of a second.
    private func launchSeeker(from point: CGPoint, speed: CGFloat, turn: CGFloat, steps: Int) {
        let bullet = createBullet(at: point, angle: -.pi / 2, speed: speed, kind: .homing)
        let updateAction = SKAction.run { [weak self, weak bullet] in
            guard let self = self,
                  let bullet = bullet,
                  let player = self.player,
                  let bulletBody = bullet.physicsBody else { return }

            let targetAngle = atan2(player.position.y - bullet.position.y, player.position.x - bullet.position.x)
            let currentAngle = atan2(bulletBody.velocity.dy, bulletBody.velocity.dx)
            var angleDiff = targetAngle - currentAngle
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }

            let newAngle = currentAngle + angleDiff * turn
            // At the fight's pace: the steps come on the round's slowed clock, so the
            // path bends exactly as it would at full speed.
            let pace = speed * self.timeScale
            bulletBody.velocity = CGVector(dx: cos(newAngle) * pace, dy: sin(newAngle) * pace)
        }
        bullet?.run(SKAction.repeat(.sequence([updateAction, .wait(forDuration: 0.05)]), count: steps))
    }

    /// The vertical laser: the boss stops dead, a warning line runs down from its core,
    /// and the beam follows it.
    private func shootLaser() -> TimeInterval {
        guard let scene = scene, let boss = boss else { return 0 }
        boss.beginManoeuvre()
        let origin = core()
        let length = origin.y + 40
        warningLine(from: origin, angle: -.pi / 2, length: length, duration: 1.0)
        SoundManager.shared.playLaserChargeSound(on: scene)

        // Until the boss is handed back its flight path, after the beam has gone out.
        return volley([
            (1.0, { [weak self] in
                guard let self = self else { return }
                self.fireBeam(from: origin, angle: -.pi / 2, length: length, hold: 0.42)
            }),
            (0.6, { [weak self] in self?.boss?.endManoeuvre() })
        ])
    }

    private func shootCircularBarrage() -> TimeInterval {
        let bulletRings = 2
        let bulletsPerRing = 9
        return volley((0..<bulletRings).map { ring in
            (ring == 0 ? 0 : 0.4, { [weak self] in
                guard let self = self else { return }
                let from = self.core()
                for i in 0..<bulletsPerRing {
                    let spreadAngle = Self.fanAngle(i, of: bulletsPerRing, width: 1.8)
                    self.createBullet(at: from, angle: -.pi / 2 + spreadAngle, speed: 200)
                }
                self.muzzleFlash(at: from, radius: 16)
                self.shootSound()
                HapticManager.shared.lightTap()
            })
        })
    }

    private func shootCascade() -> TimeInterval {
        guard let scene = scene else { return 0 }
        let columns = 6
        let columnWidth = scene.size.width / CGFloat(columns + 1)
        return volley((0..<columns).map { i in
            (i == 0 ? 0 : 0.12, { [weak self] in
                guard let self = self else { return }
                let bulletPosition = CGPoint(x: columnWidth * CGFloat(i + 1), y: self.core().y)
                self.createBullet(at: bulletPosition, angle: -.pi / 2)
                if i % 3 == 0 {
                    self.createBullet(at: bulletPosition, angle: -.pi / 2 - 0.12)
                } else if i % 3 == 2 {
                    self.createBullet(at: bulletPosition, angle: -.pi / 2 + 0.12)
                }
                if i % 2 == 0 { self.shootSound() }
            })
        })
    }

    private func shootDoubleSpiral() -> TimeInterval {
        let bulletCount = 15
        let spreadIncrement: CGFloat = 0.08
        return volley((0..<bulletCount).map { i in
            (i == 0 ? 0 : 0.12, { [weak self] in
                guard let self = self else { return }
                let from = self.core()
                self.createBullet(at: from, angle: -.pi / 2 - 0.4 + CGFloat(i) * spreadIncrement, speed: 220)
                self.createBullet(at: from, angle: -.pi / 2 + 0.4 - CGFloat(i) * spreadIncrement, speed: 220)
                if i % 4 == 0 { self.shootSound() }
            })
        })
    }

    private func shootBarrageRain() -> TimeInterval {
        let waves = 4
        let bulletsPerWave = 10
        let gapWidth = 3
        // One random safe gap, consistent across all waves, with at least two rounds
        // either side of it. The range used to run one slot further right than left.
        let gapIndex = Int.random(in: 2...(bulletsPerWave - gapWidth - 2))
        // Where the curtain hangs, fixed for the whole attack. Re-read from the core
        // every wave, the gap followed the boss's flight and the ship had to chase it.
        let anchorX = core().x
        return volley((0..<waves).map { w in
            (w == 0 ? 0 : 0.35, { [weak self] in
                guard let self = self, let scene = self.scene else { return }
                let y = self.core().y
                for i in 0..<bulletsPerWave where i < gapIndex || i >= gapIndex + gapWidth {
                    let xOffset = (CGFloat(i) / CGFloat(bulletsPerWave - 1) - 0.5) * scene.size.width * 0.75
                    // The scatter only ever leans away from the gap, and the two rounds
                    // that edge it fall straight. An even ±0.15 rad let both edges drift
                    // ~70 pt into a hole ~130 pt wide on their way down the screen.
                    let randomSpread: CGFloat
                    if i == gapIndex - 1 || i == gapIndex + gapWidth {
                        randomSpread = 0
                    } else if i < gapIndex {
                        randomSpread = CGFloat.random(in: -0.15...0)
                    } else {
                        randomSpread = CGFloat.random(in: 0...0.15)
                    }
                    self.createBullet(at: CGPoint(x: anchorX + xOffset, y: y), angle: -.pi / 2 + randomSpread, speed: 260)
                }
                self.shootSound()
                HapticManager.shared.mediumTap()
            })
        })
    }

    private func shootZigzagPattern() -> TimeInterval {
        let bulletGroups = 8
        return volley((0..<bulletGroups).map { group in
            (group == 0 ? 0 : 0.15, { [weak self] in
                guard let self = self else { return }
                let from = self.core()
                let sideAngle: CGFloat = group % 2 == 0 ? 0.4 : -0.4
                self.createBullet(at: from, angle: -.pi / 2 + sideAngle, speed: 260)
                self.createBullet(at: from, angle: -.pi / 2 + sideAngle * 0.5, speed: 260)
                self.createBullet(at: from, angle: -.pi / 2, speed: 260)
                if group % 2 == 0 { self.shootSound() }
            })
        })
    }

    private func shootSectorSweep() -> TimeInterval {
        let sectors = 12
        let startSpread: CGFloat = -0.7
        let endSpread: CGFloat = 0.7
        return volley((0..<sectors).map { i in
            (i == 0 ? 0 : 0.15, { [weak self] in
                guard let self = self else { return }
                let progress = CGFloat(i) / CGFloat(sectors - 1)
                let centerSpread = startSpread + (endSpread - startSpread) * progress
                let from = self.core()
                for j in 0..<3 {
                    let spreadAngle = (CGFloat(j) - 1) * 0.25
                    self.createBullet(at: from, angle: -.pi / 2 + centerSpread + spreadAngle, speed: 220)
                }
                if i % 3 == 0 { self.shootSound() }
            })
        })
    }

    // MARK: - Signatures

    /// Warden: each gun pod in turn fires a three-round burst aimed at the ship.
    private func podVolley() -> TimeInterval {
        guard let boss = boss else { return 0 }
        let pods = boss.liveMuzzles()
        let rounds = tier >= 3 ? 4 : 3
        if pods.isEmpty {
            let busy = volley((0..<rounds).map { r in
                (r == 0 ? 0 : 0.12, { [weak self] in
                    guard let self = self else { return }
                    let from = self.core()
                    let aim = self.angleToPlayer(from: from)
                    for offset: CGFloat in [-0.18, 0, 0.18] { self.createBullet(at: from, angle: aim + offset, speed: 270) }
                    self.shootSound()
                })
            })
            return max(0.4, busy)
        }
        // Outer pods first, alternating sides, so the volley sweeps in.
        var order: [Int] = []
        var low = 0, high = pods.count - 1
        while low <= high {
            order.append(pods[low])
            if low != high { order.append(pods[high]) }
            low += 1
            high -= 1
        }
        var steps: [(TimeInterval, () -> Void)] = []
        for (n, pod) in order.enumerated() {
            for r in 0..<rounds {
                let wait: TimeInterval = (n == 0 && r == 0) ? 0 : (r == 0 ? 0.16 : 0.09)
                steps.append((wait, { [weak self] in
                    guard let self = self, let from = self.boss?.muzzle(pod) else { return }
                    self.createBullet(at: from, angle: self.angleToPlayer(from: from), speed: 280)
                    self.muzzleFlash(at: from, radius: 8)
                    if r == 0 { self.shootSound() }
                }))
            }
        }
        // Every pod's burst, in turn: over a second and a half for four pods of four.
        return volley(steps)
    }

    /// Warden, heart: the eye locks on to where the ship is, holds a thin warning line
    /// down it, then fires a beam along it. Moving off the line is the whole answer.
    private func eyeLance() -> TimeInterval {
        guard let scene = scene, let boss = boss else { return 0 }
        boss.beginManoeuvre()
        let origin = core()
        let angle = angleToPlayer(from: origin)
        let length = hypot(scene.size.width, scene.size.height) * 1.2
        let warn: TimeInterval = tier >= 3 ? 0.62 : 0.78
        warningLine(from: origin, angle: angle, length: length, duration: warn)
        SoundManager.shared.playLaserChargeSound(on: scene)
        let busy = volley([
            (warn, { [weak self] in self?.fireBeam(from: origin, angle: angle, length: length, hold: 0.3) }),
            (0.5, { [weak self] in self?.boss?.endManoeuvre() })
        ])
        return max(warn + 0.6, busy)
    }

    /// Mantis: sweeps its arms back, dives at the ship and slashes at the bottom of the
    /// dive, then climbs back to its station. Its body is a hazard on the way.
    private func swoop() -> TimeInterval {
        guard let boss = boss, let scene = scene else { return 0 }
        boss.beginManoeuvre()

        let start = boss.position
        let arena = boss.arena
        let playerPoint = player?.position ?? CGPoint(x: start.x, y: 0)
        let targetX = min(max(playerPoint.x, arena.minX), arena.maxX)
        var diveY = max(playerPoint.y + boss.bossSize * 0.55 + 40, scene.size.height * 0.4)
        diveY = min(diveY, start.y - 60)
        let dive = CGPoint(x: targetX, y: diveY)

        // Where it is going: a chevron on the dive point and a dotted line to it.
        let marker = effectNode(at: dive)
        let reticle = Cinematic.lockOn(at: .zero, from: boss.bossSize * 0.9, to: boss.bossSize * 0.45,
                                       color: boss.telegraphColor, duration: 0.35)
        marker.addChild(reticle)
        marker.run(.sequence([.wait(forDuration: 0.85), .fadeOut(withDuration: 0.15), .removeFromParent()]))
        let path = effectNode()
        for k in 1..<8 {
            let f = CGFloat(k) / 8
            let dot = LightSprite.star(size: 9, color: boss.telegraphColor)
            dot.position = CGPoint(x: start.x + (dive.x - start.x) * f, y: start.y + (dive.y - start.y) * f)
            dot.alpha = 0
            dot.run(.sequence([.wait(forDuration: Double(k) * 0.03), .fadeAlpha(to: 0.8, duration: 0.08)]))
            path.addChild(dot)
        }
        path.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.2), .removeFromParent()]))

        let sweepBack = SKAction.customAction(withDuration: 0.35) { node, elapsed in
            (node as? Boss)?.look.sweep = Float(elapsed / 0.35)
        }
        let down = SKAction.move(to: dive, duration: 0.42)
        down.timingMode = .easeIn
        let slash = SKAction.run { [weak self] in self?.slash() }
        let up = SKAction.move(to: CGPoint(x: targetX, y: start.y), duration: 0.62)
        up.timingMode = .easeOut
        let sweepOut = SKAction.customAction(withDuration: 0.5) { node, elapsed in
            (node as? Boss)?.look.sweep = Float(1 - elapsed / 0.5)
        }
        boss.run(.sequence([
            sweepBack, down, slash, .wait(forDuration: 0.1), .group([up, sweepOut]),
            .run { [weak boss] in boss?.endManoeuvre() }
        ]), withKey: "bossManoeuvre")
        scene.shakeCamera(intensity: 4, duration: 0.2)
        return 1.5
    }

    /// The bottom of the mantis's dive: a fan from its jaws and a cut from each side —
    /// from the outermost gun on the left and on the right, however many it carries.
    private func slash() {
        guard let scene = scene else { return }
        let from = core()
        let fan = tier >= 2 ? 9 : 7
        for i in 0..<fan {
            createBullet(at: from, angle: -.pi / 2 + Self.fanAngle(i, of: fan, width: 1.5), speed: 250)
        }
        for blade in outerGuns() {
            let side: CGFloat = blade.x < from.x ? -1 : 1
            for k in 0..<4 {
                createBullet(at: blade, angle: -.pi / 2 + side * (0.5 + CGFloat(k) * 0.28), speed: 230)
            }
            muzzleFlash(at: blade, radius: 14)
        }
        muzzleFlash(at: from, radius: 20)
        SoundManager.shared.playExplosionSound(on: scene)
        HapticManager.shared.mediumTap()
    }

    /// Mantis: streams from the blade tips that bend across each other, weaving a
    /// lattice the ship has to find the holes in.
    private func scytheArcs() -> TimeInterval {
        guard let boss = boss else { return 0 }
        let blades = boss.liveMuzzles()
        let rounds = 7 + min(tier, 3)
        var steps: [(TimeInterval, () -> Void)] = []
        for k in 0..<rounds {
            steps.append((k == 0 ? 0 : 0.08, { [weak self] in
                guard let self = self, let boss = self.boss else { return }
                let c = self.core()
                for index in blades {
                    guard let from = boss.muzzle(index) else { continue }
                    let side: CGFloat = from.x < c.x ? -1 : 1
                    // Leaving outward and down, bending back across the middle.
                    let launch = -.pi / 2 + side * (0.95 - CGFloat(k) * 0.05)
                    self.fireCurving(from: from, angle: launch, speed: 200, turn: -side * 0.9)
                }
                if k % 2 == 0 { self.shootSound() }
            }))
        }
        return max(0.4, volley(steps))
    }

    /// Gyre, heart: the satellites spin up and fire outward from the core as they wheel
    /// round, drawing spiral arms.
    private func orbitalSpiral() -> TimeInterval {
        guard let boss = boss else { return 0 }
        let steps = 9 + tier
        boss.run(.sequence([
            .customAction(withDuration: 0.4) { node, elapsed in (node as? Boss)?.look.spin = 1 + 1.8 * Float(elapsed / 0.4) },
            .wait(forDuration: Double(steps) * 0.15),
            .customAction(withDuration: 0.6) { node, elapsed in (node as? Boss)?.look.spin = 2.8 - 1.8 * Float(elapsed / 0.6) }
        ]), withKey: "bossSpin")

        volley((0..<steps).map { k in
            (k == 0 ? 0.3 : 0.15, { [weak self] in
                guard let self = self else { return }
                let c = self.core()
                let guns = self.weapons()
                if guns.isEmpty {
                    for arm in 0..<3 {
                        let a = CGFloat(k) * 0.35 + CGFloat(arm) * 2 * .pi / 3
                        self.createBullet(at: c, angle: a, speed: 165)
                    }
                } else {
                    for gun in guns {
                        let dx = gun.x - c.x, dy = gun.y - c.y
                        // Rounds that would head straight back up the screen are
                        // wasted on nobody; let the lower arc do the talking.
                        guard dy < abs(dx) * 0.6 else { continue }
                        self.createBullet(at: gun, angle: atan2(dy, dx), speed: 165)
                    }
                }
                if k % 3 == 0 { self.shootSound() }
            })
        })
        return Double(steps) * 0.15 + 0.3
    }

    /// Gyre, maw, heart: a full ring with a gap, then another turned a half-step with
    /// its gap moved along.
    private func ringPulse() -> TimeInterval {
        let pulses = tier >= 2 ? 3 : 2
        let count = min(30, 20 + 2 * tier)
        var gapAngle = -CGFloat.pi / 2 + CGFloat.random(in: -1.0...1.0)
        var steps: [(TimeInterval, () -> Void)] = []
        for p in 0..<pulses {
            let gap = gapAngle
            steps.append((p == 0 ? 0 : 0.5, { [weak self] in
                guard let self = self else { return }
                let from = self.core()
                let step = 2 * CGFloat.pi / CGFloat(count)
                for i in 0..<count {
                    let a = CGFloat(i) * step + CGFloat(p) * step * 0.5
                    var diff = a - gap
                    while diff > .pi { diff -= 2 * .pi }
                    while diff < -.pi { diff += 2 * .pi }
                    if abs(diff) < step * 1.6 { continue }
                    self.createBullet(at: from, angle: a, speed: 150)
                }
                self.muzzleFlash(at: from, radius: 22)
                self.shootSound()
                HapticManager.shared.lightTap()
            }))
            gapAngle += CGFloat.random(in: 0.35...0.6) * (Bool.random() ? 1 : -1)
        }
        volley(steps)
        return Double(pulses) * 0.5
    }

    /// Hive, heart: slow mines out of every bay that drift down, flash, and burst.
    private func mineLayer() -> TimeInterval {
        guard let scene = scene else { return 0 }
        let perBay = tier >= 3 ? 2 : 1
        var steps: [(TimeInterval, () -> Void)] = []
        for wave in 0..<perBay {
            steps.append((wave == 0 ? 0 : 0.45, { [weak self] in
                guard let self = self else { return }
                // Out of the bays still there as the wave leaves, or with every one shot
                // off, either side of the core now. The fallback used to be the bays
                // as they were when the attack began, so a wave laid after the last
                // bay went came out of empty space where the boss had been.
                var sources = self.weapons()
                if sources.isEmpty {
                    let c = self.core()
                    sources = [CGPoint(x: c.x - 30, y: c.y), CGPoint(x: c.x + 30, y: c.y)]
                }
                for from in sources {
                    self.layMine(from: from)
                }
                SoundManager.shared.playMineArmSound(on: scene)
            }))
        }
        // Until the last mine laid has burst.
        return volley(steps) + Self.mineFuse.upperBound + Self.mineFlash
    }

    /// How long a mine drifts before it starts to flash, and how long it flashes.
    private static let mineFuse: ClosedRange<TimeInterval> = 1.0...1.35
    private static let mineFlash: TimeInterval = 0.32

    private func layMine(from point: CGPoint) {
        guard let mine = createBullet(at: point, angle: -.pi / 2 + CGFloat.random(in: -0.35...0.35),
                                      speed: CGFloat.random(in: 120...160), kind: .heavy) else { return }
        mine.setScale(1.5)
        // Scaled with the fight's pace, like its velocity, so a slowed mine still
        // drifts the same distance before its slowed fuse runs out.
        mine.physicsBody?.linearDamping = 0.9 * timeScale
        muzzleFlash(at: point, radius: 12)

        let shards = 8 + min(tier, 4)
        let fuse = TimeInterval.random(in: Self.mineFuse)
        let flash = Self.mineFlash / 4
        mine.run(.sequence([
            .wait(forDuration: fuse),
            .repeat(.sequence([.scale(to: 2.0, duration: flash), .scale(to: 1.5, duration: flash)]), count: 2),
            .run { [weak self, weak mine] in
                guard let self = self, let mine = mine, mine.parent != nil else { return }
                let origin = mine.position
                let turn = CGFloat.random(in: 0...(2 * .pi))
                for i in 0..<shards {
                    let a = turn + CGFloat(i) / CGFloat(shards) * 2 * .pi
                    self.createBullet(at: origin, angle: a, speed: 140)
                }
                self.muzzleFlash(at: origin, radius: 16)
                mine.removeFromParent()
            }
        ]), withKey: "mineFuse")
    }

    /// Hive: a pair of slow seekers out of every bay.
    private func broodSwarm() -> TimeInterval {
        guard let scene = scene else { return 0 }
        volley((0..<2).map { k in
            (k == 0 ? 0 : 0.25, { [weak self] in
                guard let self = self else { return }
                // The core as the pair leaves, not where the bays were when the attack
                // began; see `mineLayer()`.
                let bays = self.weapons()
                for from in bays.isEmpty ? [self.core()] : bays {
                    self.launchSeeker(from: from, speed: 135, turn: 0.04, steps: 48)
                    self.muzzleFlash(at: from, radius: 10)
                }
            })
        })
        SoundManager.shared.playPowerUpSound(on: scene)
        return 0.5
    }

    /// Lancer, heart: a beam sweeps one side of the screen — the ship's side, so it has
    /// to cross under the boss before it fires. From the fourth meeting it may instead
    /// close two beams in from the edges onto a corridor under the boss.
    private func sweepBeam() -> TimeInterval {
        guard let scene = scene, let boss = boss else { return 0 }
        boss.beginManoeuvre()
        let pivot = core()
        let length = hypot(scene.size.width, scene.size.height) * 1.2
        let down = -CGFloat.pi / 2
        let playerX = player?.position.x ?? pivot.x

        var arcs: [(from: CGFloat, to: CGFloat)]
        if tier >= 3 && Bool.random() {
            arcs = [(down - 0.95, down - 0.14), (down + 0.95, down + 0.14)]
        } else {
            let side: CGFloat = playerX < pivot.x - 8 ? -1 : (playerX > pivot.x + 8 ? 1 : (Bool.random() ? 1 : -1))
            arcs = [(down, down + side * 0.85)]
        }

        // Show the whole sector it will cover before it fires.
        let warn: TimeInterval = 0.85
        for arc in arcs {
            let fan = effectNode(at: pivot)
            for k in 0...6 {
                let a = arc.from + (arc.to - arc.from) * CGFloat(k) / 6
                let edge = k == 0 || k == 6
                let line = LightSprite.tube(from: .zero, to: CGPoint(x: cos(a) * length, y: sin(a) * length),
                                            width: edge ? 2.4 : 1.2, color: ProjectileFX.hostile)
                line.alpha = edge ? 0.95 : 0.32
                fan.addChild(line)
            }
            fan.run(.sequence([
                .repeat(.sequence([.fadeAlpha(to: 0.35, duration: 0.09), .fadeAlpha(to: 1, duration: 0.09)]), count: 4),
                .wait(forDuration: warn - 0.72),
                .removeFromParent()
            ]))
        }
        SoundManager.shared.playLaserChargeSound(on: scene)

        let sweep: TimeInterval = 1.1
        volley([
            (warn, { [weak self] in
                guard let self = self else { return }
                for arc in arcs {
                    let beam = self.fireBeam(from: pivot, angle: arc.from, length: length, hold: sweep + 0.1)
                    let span = arc.to - arc.from
                    beam?.run(.customAction(withDuration: sweep) { node, elapsed in
                        let f = elapsed / CGFloat(sweep)
                        node.zRotation = arc.from + span * f * f * (3 - 2 * f)
                    })
                }
            }),
            (sweep + 0.35, { [weak self] in self?.boss?.endManoeuvre() })
        ])
        return warn + sweep + 0.4
    }

    /// Lancer: slow prisms that split, halfway down, into fans aimed at the ship.
    private func prismSplit() -> TimeInterval {
        var sources = weapons()
        if tier >= 2 || sources.isEmpty { sources.append(core()) }
        let fan = 5 + tier / 2
        for from in sources {
            let aim = angleToPlayer(from: from)
            let launch = -.pi / 2 + max(-0.35, min(0.35, aim + .pi / 2)) * 0.5
            guard let prism = createBullet(at: from, angle: launch, speed: 150, kind: .heavy) else { continue }
            prism.setScale(1.4)
            muzzleFlash(at: from, radius: 12)
            prism.run(.sequence([
                .wait(forDuration: Self.prismFuse),
                .run { [weak self, weak prism] in
                    guard let self = self, let prism = prism, prism.parent != nil else { return }
                    let origin = prism.position
                    let centre = self.angleToPlayer(from: origin)
                    for i in 0..<fan {
                        self.createBullet(at: origin, angle: centre + Self.fanAngle(i, of: fan, width: 0.9), speed: 230)
                    }
                    self.muzzleFlash(at: origin, radius: 14)
                    prism.removeFromParent()
                }
            ]), withKey: "prismFuse")
        }
        shootSound()
        // Until the prisms have split.
        return Self.prismFuse
    }

    /// How long a prism flies before it splits.
    private static let prismFuse: TimeInterval = 0.75

    /// Serpent: every segment fires down in turn, head to tail, then back again aimed.
    private func segmentVolley() -> TimeInterval {
        guard let boss = boss else { return 0 }
        // Head to tail is muzzle order: segment 0 is the one behind the head.
        let segments = (0..<boss.muzzleCount).filter { boss.muzzle($0) != nil }
        guard !segments.isEmpty else {
            return shootSpread()
        }
        var steps: [(TimeInterval, () -> Void)] = []
        for (n, index) in segments.enumerated() {
            steps.append((n == 0 ? 0 : 0.07, { [weak self] in
                guard let self = self, let from = self.boss?.muzzle(index) else { return }
                if self.tier >= 2 {
                    self.createBullet(at: from, angle: -.pi / 2 - 0.18, speed: 220)
                    self.createBullet(at: from, angle: -.pi / 2 + 0.18, speed: 220)
                } else {
                    self.createBullet(at: from, angle: -.pi / 2, speed: 220)
                }
                self.muzzleFlash(at: from, radius: 8)
                if n % 2 == 0 { self.shootSound() }
            }))
        }
        if tier >= 1 {
            for (n, index) in segments.reversed().enumerated() {
                steps.append((n == 0 ? 0.3 : 0.07, { [weak self] in
                    guard let self = self, let from = self.boss?.muzzle(index) else { return }
                    self.createBullet(at: from, angle: self.angleToPlayer(from: from), speed: 240)
                    if n % 2 == 0 { self.shootSound() }
                }))
            }
        }
        return volley(steps)
    }

    /// Serpent: alternate segments release rings, then the others.
    private func coilBurst() -> TimeInterval {
        guard let boss = boss else { return 0 }
        let segments = (0..<boss.muzzleCount).filter { boss.muzzle($0) != nil }
        guard !segments.isEmpty else {
            return shootCircularBarrage()
        }
        let spokes = tier >= 3 ? 6 : 5
        volley((0..<2).map { half in
            (half == 0 ? 0 : 0.45, { [weak self] in
                guard let self = self, let boss = self.boss else { return }
                for (n, index) in segments.enumerated() where n % 2 == half {
                    guard let from = boss.muzzle(index) else { continue }
                    let turn = CGFloat(n) * 0.4
                    for k in 0..<spokes {
                        self.createBullet(at: from, angle: turn + CGFloat(k) / CGFloat(spokes) * 2 * .pi, speed: 150)
                    }
                    self.muzzleFlash(at: from, radius: 10)
                }
                self.shootSound()
            })
        })
        return 0.6
    }

    /// Wraith: fades out of the world, a rift opens where it will be, and it steps out
    /// of it in a burst.
    private func blink() -> TimeInterval {
        guard let boss = boss, let scene = scene else { return 0 }
        boss.beginManoeuvre()
        let arena = boss.arena
        var generator = SystemRandomNumberGenerator()
        let destination = CGPoint(x: Self.blinkX(from: boss.position.x, minX: arena.minX, maxX: arena.maxX,
                                                 using: &generator),
                                  y: arena.baseY - CGFloat.random(in: 0...28))

        // The rift it will come out of.
        let rift = effectNode(at: destination)
        let ring = LightRing(segments: 24, color: StoryPalette.violet)
        ring.set(radius: 4, width: 2, squash: 0.35)
        rift.addChild(ring)
        let glow = NeonFX.radialGlow(radius: boss.bossSize * 0.4, color: StoryPalette.violet)
        glow.alpha = 0
        rift.addChild(glow)
        let size = boss.bossSize
        ring.run(.customAction(withDuration: 0.5) { node, elapsed in
            (node as? LightRing)?.set(radius: 4 + size * 0.5 * elapsed / 0.5, width: 2, squash: 0.35)
        })
        glow.run(.fadeAlpha(to: 0.5, duration: 0.5))
        rift.run(.sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.25), .removeFromParent()]))

        SoundManager.shared.playTeleportSound(on: scene)
        let out = SKAction.customAction(withDuration: 0.22) { node, elapsed in
            (node as? Boss)?.look.fade = Float(1 - elapsed / 0.22)
        }
        let back = SKAction.customAction(withDuration: 0.16) { node, elapsed in
            (node as? Boss)?.look.fade = Float(elapsed / 0.16)
        }
        boss.run(.sequence([
            .run { [weak boss] in boss?.setTangible(false) },
            out,
            .wait(forDuration: 0.3),
            .run { [weak boss] in boss?.position = destination },
            back,
            .run { [weak self, weak boss] in
                boss?.look.fade = 1
                boss?.setTangible(true)
                self?.blinkBurst()
                boss?.endManoeuvre()
            }
        ]), withKey: "bossManoeuvre")
        return 0.9
    }

    /// Where along its arena the wraith blinks to from `x`: a random spot far enough
    /// away to read as a move, or, when no spot is, the arena's far end.
    ///
    /// The fallback used to be staying put. The only exemption was an arena under 100 pt
    /// wide, and the late wraiths on a phone fly 159–179 pt: from near the middle of that
    /// nothing is 90 pt away, every try failed, and the boss faded out and back in on
    /// the spot it left.
    nonisolated static func blinkX<G: RandomNumberGenerator>(from x: CGFloat, minX: CGFloat, maxX: CGFloat,
                                                              using generator: inout G) -> CGFloat {
        guard maxX > minX else { return minX }
        let reach = max(90, (maxX - minX) * 0.3)
        for _ in 0..<8 {
            let candidate = CGFloat.random(in: minX...maxX, using: &generator)
            if abs(candidate - x) > reach { return candidate }
        }
        return x - minX > maxX - x ? minX : maxX
    }

    private func blinkBurst() {
        let from = core()
        let ring = 10 + 2 * min(tier, 4)
        let turn = CGFloat.random(in: 0...1)
        for i in 0..<ring {
            createBullet(at: from, angle: turn + CGFloat(i) / CGFloat(ring) * 2 * .pi, speed: 165)
        }
        let aim = angleToPlayer(from: from)
        for offset: CGFloat in [-0.12, 0, 0.12] { createBullet(at: from, angle: aim + offset, speed: 280) }
        muzzleFlash(at: from, radius: 24)
        shootSound()
        HapticManager.shared.mediumTap()
    }

    /// Wraith, heart: rifts open at the sides of the screen and fire streams across it
    /// at the ship.
    private func riftPortals() -> TimeInterval {
        guard let scene = scene else { return 0 }
        let width = scene.size.width, height = scene.size.height
        let count = tier >= 2 ? 3 : 2
        let leftFirst = Bool.random()
        var points: [CGPoint] = []
        for i in 0..<count {
            let left = (i % 2 == 0) == leftFirst
            let band = CGFloat(i) / CGFloat(max(1, count - 1))
            points.append(CGPoint(x: left ? 34 : width - 34, y: height * (0.6 - 0.26 * band) + CGFloat.random(in: -20...20)))
        }
        let shots = 5 + tier / 2

        for (i, point) in points.enumerated() {
            let portal = effectNode(at: point)
            let ring = LightRing(segments: 24, color: StoryPalette.violet)
            ring.zRotation = .pi / 2
            ring.set(radius: 3, width: 2.2, squash: 0.42)
            portal.addChild(ring)
            let glow = NeonFX.radialGlow(radius: 30, color: StoryPalette.violet)
            glow.alpha = 0
            portal.addChild(glow)
            let core = LightSprite.star(size: 26, color: .white)
            core.alpha = 0
            portal.addChild(core)

            let open = SKAction.customAction(withDuration: 0.55) { node, elapsed in
                (node as? LightRing)?.set(radius: 3 + 25 * elapsed / 0.55, width: 2.2, squash: 0.42)
            }
            ring.run(.sequence([.wait(forDuration: Double(i) * 0.15), open]))
            glow.run(.sequence([.wait(forDuration: Double(i) * 0.15), .fadeAlpha(to: 0.6, duration: 0.55)]))
            core.run(.sequence([.wait(forDuration: Double(i) * 0.15 + 0.3), .fadeAlpha(to: 0.8, duration: 0.25)]))

            var fire: [SKAction] = [.wait(forDuration: 0.75 + Double(i) * 0.15)]
            for s in 0..<shots {
                fire.append(.run { [weak self, weak portal] in
                    guard let self = self, self.fighting, let portal = portal else { return }
                    self.createBullet(at: portal.position, angle: self.angleToPlayer(from: portal.position), speed: 215)
                    self.muzzleFlash(at: portal.position, radius: 12)
                    if s % 2 == 0 { self.shootSound() }
                })
                fire.append(.wait(forDuration: 0.15))
            }
            fire.append(.run { [weak ring] in
                ring?.run(.customAction(withDuration: 0.25) { node, elapsed in
                    (node as? LightRing)?.set(radius: 28 * (1 - elapsed / 0.25), width: 2.2, squash: 0.42)
                })
            })
            fire.append(.fadeOut(withDuration: 0.25))
            fire.append(.removeFromParent())
            portal.run(.sequence(fire))
        }
        SoundManager.shared.playTeleportSound(on: scene)
        return 0.75 + Double(count) * 0.15 + Double(shots) * 0.15
    }

    /// Tesseract: walls of rounds across the whole screen, each with a gap a little way
    /// along from the last, so the ship is led through them.
    private func latticeWalls() -> TimeInterval {
        guard let scene = scene else { return 0 }
        let width = scene.size.width
        let walls = min(6, 4 + tier / 2)
        let spacing: CGFloat = 30
        let slots = Int((width - 24) / spacing) + 1
        let gapWidth = 3
        var gap = Int.random(in: 1...max(1, slots - gapWidth - 1))
        var gaps: [Int] = []
        for _ in 0..<walls {
            gaps.append(gap)
            gap = min(max(0, gap + Int.random(in: -3...3)), slots - gapWidth)
        }

        volley(gaps.enumerated().map { n, gapStart in
            (n == 0 ? 0 : 0.55, { [weak self] in
                guard let self = self, let boss = self.boss else { return }
                let y = boss.position.y - boss.bossSize * 0.45
                for i in 0..<slots where i < gapStart || i >= gapStart + gapWidth {
                    self.createBullet(at: CGPoint(x: 12 + CGFloat(i) * spacing, y: y), angle: -.pi / 2, speed: 165)
                }
                // A line of light where the wall is drawn.
                let flash = LightSprite.tube(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y), width: 1.4,
                                             color: boss.telegraphColor)
                flash.name = Self.effectName
                flash.zPosition = 84
                self.scene?.gameContentNode.addChild(flash)
                flash.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
                self.shootSound()
            })
        })
        return Double(walls) * 0.55
    }

    /// Tesseract: folds out of space, unfolds at another station and fires a cross —
    /// dashed lines of rounds down and out, and a shot from each corner at the ship.
    private func hyperShift() -> TimeInterval {
        guard let boss = boss, let scene = scene else { return 0 }
        boss.beginManoeuvre()
        let destination = boss.distantStation()
        let fold = SKAction.customAction(withDuration: 0.16) { node, elapsed in
            (node as? Boss)?.look.fade = Float(1 - 0.95 * elapsed / 0.16)
        }
        let unfold = SKAction.customAction(withDuration: 0.16) { node, elapsed in
            (node as? Boss)?.look.fade = Float(0.05 + 0.95 * elapsed / 0.16)
        }
        SoundManager.shared.playTeleportSound(on: scene)
        boss.run(.sequence([
            .run { [weak boss] in boss?.setTangible(false) },
            fold,
            .run { [weak boss] in boss?.position = destination },
            unfold,
            .run { [weak self, weak boss] in
                boss?.look.fade = 1
                boss?.setTangible(true)
                self?.crossFire()
                boss?.endManoeuvre()
            }
        ]), withKey: "bossManoeuvre")
        return 0.6
    }

    private func crossFire() {
        let from = core()
        var angles: [CGFloat] = [-.pi / 2, -.pi / 2 - 0.55, -.pi / 2 + 0.55]
        if tier >= 2 { angles += [-.pi / 2 - 1.05, -.pi / 2 + 1.05] }
        for angle in angles {
            for (k, speed) in [170, 210, 250, 290].enumerated() where k < 3 || tier >= 1 {
                createBullet(at: from, angle: angle, speed: CGFloat(speed))
            }
        }
        for gun in weapons() {
            createBullet(at: gun, angle: angleToPlayer(from: gun), speed: 260)
            muzzleFlash(at: gun, radius: 9)
        }
        muzzleFlash(at: from, radius: 22)
        shootSound()
    }

    /// Maw, heart: a ring of rounds appears around the ship, holds as a warning, then
    /// collapses on where the ship was — open on one side.
    private func implosion() -> TimeInterval {
        guard let scene = scene, let player = player, let boss = boss else { return 0 }
        let margin: CGFloat = 20
        let centre = CGPoint(x: min(max(player.position.x, margin), scene.size.width - margin),
                             y: min(max(player.position.y, margin), scene.size.height - margin))
        let radius: CGFloat = 150
        let count = min(18, 14 + tier)
        let slots = count + 3
        // The way out faces the open screen rather than a wall.
        let toMiddle = atan2(scene.size.height * 0.4 - centre.y, scene.size.width / 2 - centre.x)
        let gapAngle = toMiddle + CGFloat.random(in: -0.6...0.6)

        var angles: [CGFloat] = []
        for i in 0..<slots {
            let a = gapAngle + CGFloat(i + 2) * 2 * .pi / CGFloat(slots)
            angles.append(a)
        }
        angles = Array(angles.prefix(count))

        let marker = effectNode(at: centre)
        let ring = LightRing(segments: 36, color: boss.telegraphColor)
        ring.set(radius: radius, width: 1.4)
        ring.alpha = 0.55
        marker.addChild(ring)
        for a in angles {
            let dot = LightSprite.star(size: 22, color: ProjectileFX.hostile)
            dot.position = CGPoint(x: cos(a) * radius, y: sin(a) * radius)
            dot.alpha = 0
            dot.run(.sequence([.fadeAlpha(to: 0.85, duration: 0.12),
                               .repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.12),
                                                         .fadeAlpha(to: 0.85, duration: 0.12)]))]))
            marker.addChild(dot)
        }
        SoundManager.shared.playWarningSound(on: scene)

        marker.run(.sequence([
            .wait(forDuration: 0.85),
            .run { [weak self] in
                guard let self = self, self.fighting else { return }
                for a in angles {
                    let p = CGPoint(x: centre.x + cos(a) * radius, y: centre.y + sin(a) * radius)
                    self.createBullet(at: p, angle: a + .pi, speed: 125)
                }
                self.shootSound()
                HapticManager.shared.mediumTap()
            },
            .removeFromParent()
        ]))
        return 1.4
    }

    /// Maw, heart: spiral arms of rounds that bend as they fly, as if caught in the
    /// hole's pull.
    private func accretion() -> TimeInterval {
        guard let boss = boss else { return 0 }
        let arms = min(4, 2 + tier / 2)
        let steps = 16
        let turn: CGFloat = Bool.random() ? 0.7 : -0.7
        boss.run(.sequence([
            .customAction(withDuration: 0.3) { node, elapsed in (node as? Boss)?.look.spin = 1 + 1.2 * Float(elapsed / 0.3) },
            .wait(forDuration: Double(steps) * 0.1),
            .customAction(withDuration: 0.5) { node, elapsed in (node as? Boss)?.look.spin = 2.2 - 1.2 * Float(elapsed / 0.5) }
        ]), withKey: "bossSpin")
        return volley((0..<steps).map { k in
            (0.1, { [weak self] in
                guard let self = self else { return }
                let from = self.core()
                for arm in 0..<arms {
                    let a = CGFloat(k) * 0.32 * (turn > 0 ? 1 : -1) + CGFloat(arm) * 2 * .pi / CGFloat(arms) - .pi / 2
                    self.fireCurving(from: from, angle: a, speed: 145, turn: turn)
                }
                if k % 4 == 0 { self.shootSound() }
            })
        })
    }

    // MARK: - Beams

    /// A thin flickering line down the path a beam is about to take. It is furniture,
    /// not a hazard: it has no physics body.
    @discardableResult
    private func warningLine(from origin: CGPoint, angle: CGFloat, length: CGFloat, duration: TimeInterval) -> SKNode {
        let node = effectNode(at: origin)
        node.zRotation = angle
        let haze = LightSprite.tube(from: .zero, to: CGPoint(x: length, y: 0), width: 7, color: ProjectileFX.hostile)
        haze.alpha = 0.18
        node.addChild(haze)
        let line = LightSprite.tube(from: .zero, to: CGPoint(x: length, y: 0), width: 2, color: ProjectileFX.hostile)
        node.addChild(line)
        let spark = LightSprite.star(size: 26, color: .white)
        node.addChild(spark)
        spark.run(.repeatForever(.sequence([.scale(to: 1.4, duration: 0.08), .scale(to: 0.9, duration: 0.08)])))
        line.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.08), .fadeAlpha(to: 0.95, duration: 0.08)])))
        node.run(.sequence([.wait(forDuration: duration), .removeFromParent()]))
        return node
    }

    /// A beam from `origin` along `angle`, live for `hold` seconds. The node is named
    /// `bosslaser`: `GameScene` leaves it in place when it hits the ship.
    @discardableResult
    private func fireBeam(from origin: CGPoint, angle: CGFloat, length: CGFloat, hold: TimeInterval) -> SKNode? {
        guard let scene = scene, fighting else { return nil }

        // The shape is the hit volume only; the beam is drawn in light. A shape node's
        // `glowWidth` is one of the most expensive things SpriteKit can draw, and it
        // still came out a flat red bar.
        let laser = SKNode()
        laser.name = Self.beamName
        laser.position = origin
        laser.zRotation = angle
        laser.zPosition = 85
        // Its hold and its sweep on the fight's clock, like the warning before it.
        laser.speed = timeScale

        let end = CGPoint(x: length, y: 0)
        let halo = LightSprite.tube(from: .zero, to: end, width: 16, color: ProjectileFX.hostile)
        let body = LightSprite.tube(from: .zero, to: end, width: 7, color: ProjectileFX.hostileRim)
        let core = LightSprite.tube(from: .zero, to: end, width: 2.5, color: .white)
        for beam in [halo, body, core] { laser.addChild(beam) }
        halo.run(.repeatForever(.sequence([.scaleY(to: 1.25, duration: 0.05), .scaleY(to: 0.9, duration: 0.05)])))
        let source = LightSprite.flare(length: 160, thickness: 8, color: ProjectileFX.hostile)
        source.zRotation = -angle
        laser.addChild(source)
        laser.addChild(LightSprite.star(size: 70, color: .white))
        laser.alpha = 0
        laser.run(.fadeIn(withDuration: 0.06))

        let physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: length, height: 14), center: CGPoint(x: length / 2, y: 0))
        physicsBody.categoryBitMask = PhysicsCategory.enemyBullet
        physicsBody.contactTestBitMask = PhysicsCategory.player
        physicsBody.collisionBitMask = PhysicsCategory.none
        physicsBody.isDynamic = false
        laser.physicsBody = physicsBody

        scene.gameContentNode.addChild(laser)

        SoundManager.shared.playLaserFireSound(on: scene)
        HapticManager.shared.heavyTap()
        scene.shakeCamera(intensity: 3, duration: 0.2)

        laser.run(.sequence([.wait(forDuration: hold), .fadeOut(withDuration: 0.08), .removeFromParent()]))
        return laser
    }

    // MARK: - Bullet Creation

    /// A round whose heading turns at `turn` radians a second for its first few
    /// seconds. Stateless: the heading is a function of time alone, so nothing has to be
    /// remembered between frames.
    ///
    /// Time is the round's own, slowed with the fight, and the speed is the fight's pace
    /// as of this frame: the two together keep the curve's shape under SLOW MO.
    private func fireCurving(from point: CGPoint, angle: CGFloat, speed: CGFloat, turn: CGFloat) {
        guard let bullet = createBullet(at: point, angle: angle, speed: speed) else { return }
        bullet.run(.customAction(withDuration: 2.4) { [weak self] node, elapsed in
            let a = angle + turn * elapsed
            let pace = speed * (self?.timeScale ?? 1)
            node.physicsBody?.velocity = CGVector(dx: cos(a) * pace, dy: sin(a) * pace)
        }, withKey: "curve")
    }

    @discardableResult
    private func createBullet(at position: CGPoint, angle: CGFloat, speed: CGFloat = 250,
                              kind: ProjectileFX.HostileKind = .boss) -> SKSpriteNode? {
        guard let scene = scene else { return nil }

        // One pre-lit sprite in the hostile palette; see `ProjectileFX`. A boss barrage is
        // the densest fire in the game.
        //
        // The name must match the spelling every other producer and every sweep uses.
        // SpriteKit name matching is case-sensitive, and this once read "enemybullet":
        // boss bullets carry no move action, so cleanupOffScreenBullets() was their only
        // route out of the scene and it could never match them.
        let bullet = ProjectileFX.hostileRound(kind)
        bullet.position = position
        // At the fight's pace; see `setTimeScale(_:)`.
        let pace = speed * timeScale
        bullet.physicsBody?.velocity = CGVector(dx: cos(angle) * pace, dy: sin(angle) * pace)
        bullet.speed = timeScale
        rounds.add(bullet)

        scene.gameContentNode.addChild(bullet)

        // Hard lifetime cap, so a boss bullet can never outlive the fight even if it
        // somehow stalls on screen. A plain wait rather than a move+remove sequence — a
        // move action would fight the velocity. The off-screen sweep still does the
        // routine cleanup; this is only the backstop.
        bullet.run(SKAction.sequence([
            SKAction.wait(forDuration: 8.0),
            SKAction.removeFromParent()
        ]), withKey: "bulletLifetime")

        return bullet
    }

    // MARK: - Boss Management

    func bossTakeDamage(amount: Int = 1, part: BossPart? = nil)
        -> (defeated: Bool, points: Int, phaseChanged: Bool, partBonus: Int) {
        // A boss still flying in, or already dead, is not a target. `Boss.takeDamage`
        // refuses it as well; refusing here too keeps a late round from so much as
        // touching a part, and makes "defeated" something that can only be said once.
        guard let boss = boss, boss.isAlive() else { return (false, 0, false, 0) }

        var partBonus = 0
        if let part = part, boss.damagePart(part, amount: amount) {
            partBonus = Self.partBonus(for: boss)
        }

        let phaseBefore = boss.currentPhase
        let defeated = boss.takeDamage(amount: amount)
        var phaseChanged = false

        // Checked before the defeat branch returns, and only while the boss lives: a
        // dying boss crosses every remaining threshold on its way to zero, and firing a
        // transition into the defeat animation would fight it for the same nodes.
        if !defeated {
            let phaseAfter = boss.currentPhase
            if phaseAfter > phaseBefore {
                advanceToPhase(phaseAfter)
                phaseChanged = true
            }
        }

        if defeated {
            isAttacking = false
            volleys?.removeAllActions()
            clearHazards()
            // A wind-up the kill interrupted: its ring and the hull's swell.
            clearTelegraph()
            boss.cancelWindUp()
            // The explosions keep their own pace even under SLOW MO, so they finish
            // inside `GameScene`'s wait for them.
            boss.speed = 1
            let points = boss.getPoints()

            // The defeat animation itself is `Boss.die()`, run by the killing hit.
            // Trigger camera shake effects during boss explosion sequence using SKAction
            guard let scene = scene else { return (true, points, false, partBonus) }

            var shakeActions: [SKAction] = []

            // Small shakes for each explosion. Weak captures: the sequence is retained
            // by the host node, and a strong `self` would keep this manager alive
            // through the whole defeat animation.
            for i in 0..<8 {
                let shake = SKAction.run { [weak self] in
                    self?.scene?.shakeCamera(intensity: 8.0, duration: 0.2)
                }
                if i > 0 { shakeActions.append(.wait(forDuration: 0.2)) }
                shakeActions.append(shake)
            }

            shakeActions.append(.wait(forDuration: 0.2))
            shakeActions.append(.run { [weak self] in
                self?.scene?.shakeCamera(intensity: 20.0, duration: 0.5)
            })

            // Hosted on gameContentNode, not the scene: the scene keeps ticking while
            // the game is paused, so this shake timeline used to run on behind the
            // pause menu, out of step with the explosions it is meant to accompany.
            scene.gameContentNode.run(SKAction.sequence(shakeActions), withKey: "bossCameraShakes")

            return (true, points, false, partBonus)
        }

        return (false, 0, phaseChanged, partBonus)
    }

    /// What shooting one part off a boss pays: a share of its bounty, rounded to tens.
    static func partBonus(for boss: Boss) -> Int {
        let count = max(1, boss.parts.count)
        let raw = boss.getPoints() / (3 * count)
        return max(50, (raw / 10) * 10)
    }

    func isBossActive() -> Bool {
        return boss?.isAlive() ?? false
    }

    func getBoss() -> Boss? {
        return boss
    }

    func getBossPosition() -> CGPoint? {
        return boss?.position
    }

    func cleanup() {
        isAttacking = false
        currentPhase = 0
        lastPatternIndex = nil
        drawsSinceSignature = 0
        volleys?.removeAllActions()
        volleys = nil
        clearHazards()
        clearTelegraph()
        boss?.removeAction(forKey: "bossPhaseResume")
        boss?.cancelWindUp()
        boss?.removeAction(forKey: "bossAttackSchedule")
        boss?.removeAction(forKey: "bossManoeuvre")
        boss?.removeFromParent()
        boss?.removeHealthBarFromScene()
        boss = nil
    }

    // No deinit here on purpose.
    //
    // It used to call `cleanup()`, which is the one genuine actor-isolation violation
    // in the project: with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor this type is
    // MainActor-isolated, but `deinit` is not, so touching SKNode state from it is
    // unsound — and a hard error under the Swift 6 language mode. Deallocation is also
    // the wrong moment for it: it happens whenever the last reference happens to drop.
    // GameScene.willMove(from:) now calls `cleanup()` explicitly, on the main actor, at
    // a point where teardown order is actually known.
}
