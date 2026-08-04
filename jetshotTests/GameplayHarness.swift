//
//  GameplayHarness.swift
//  jetshotTests
//

import XCTest
import SpriteKit
@testable import jetshot

/// Brings a real, *running* `GameScene` up inside the test host so gameplay can be
/// exercised end to end: real `SKPhysicsBody` contacts dispatched through
/// `GameScene.didBegin(_:)`, real `Player.shoot()` bullets, real manager teardown.
///
/// Two things about this environment are worth knowing before adding tests.
///
/// **The window has to belong to a `UIWindowScene`.** A bare `UIWindow(frame:)` never
/// becomes key under the UIScene life cycle, and an `SKView` in a non-key window gets
/// no display link — so no action, no physics step, nothing advances and every test
/// silently passes by doing nothing. `makeHostedView()` adopts the host app's scene and
/// installs a `rootViewController`, which is what actually gets frames flowing.
///
/// **The level intro cannot be waited out here, so gameplay is unpaused directly.**
/// `showLevelIntro()` ends by animating the player up from below and calling
/// `startGame()` from that action's completion — but the player lives inside
/// `gameContentNode`, which the intro has just paused, so the action is frozen and the
/// completion never fires. In the shipped app it runs anyway: every route into
/// `GameScene` presents it with an `SKTransition`, SpriteKit pauses the incoming scene
/// for the duration, and unpausing the *scene* afterwards clears `isPaused` on its
/// descendants — `gameContentNode` included. That transition needs a real drawable and
/// never completes in a unit-test host, so waiting for the intro here hangs forever.
/// `startPlaying()` therefore reproduces `setGameplayPaused(false)` from the outside.
///
/// Unpausing has one more consequence, and it is the useful one: it un-freezes the
/// player, so the intro's entry animation *does* run and *does* call `startGame()`.
/// `startPlayingWithControl()` waits for exactly that, which makes `isGameStarted` true
/// and puts the whole input path — `touchesBegan`, the firing cadence in `update(_:)`,
/// overheat, the pause button — under test. Use `startPlaying()` when a test only needs
/// collisions and can skip the ~3 s intro.
///
/// **`SWIFT_DEFAULT_ACTOR_ISOLATION` is deliberately *not* set on the `jetshotTests`
/// target, unlike the `jetshot` target which sets it to `MainActor`.** This asymmetry is
/// load-bearing, not an oversight, so please do not "fix" it: `XCTestCase` declares
/// `init()`, `init(invocation:)` and `init(selector:)` as `nonisolated`, so defaulting
/// test classes to the main actor makes every subclass's inherited initializer
/// main-actor-isolated and the whole target stops compiling with "main actor-isolated
/// initializer 'init()' has different actor isolation from nonisolated overridden
/// declaration" — three times over (one per initializer) for every one of the 21
/// `XCTestCase` subclasses in the target. Verified by trying it.
///
/// The consequence is that test code is `nonisolated` by default while the code it
/// exercises is main-actor by default, which is why `@MainActor` is written out
/// explicitly on the classes and helpers that touch `SKNode` state, and why the gameplay
/// suites build their scene per test instead of in `setUp()`/`tearDown()` — those are
/// `nonisolated` and cannot reach a main-actor `GameScene`.

// MARK: - Harness input

/// A touch reporting a scene-space location of our choosing.
///
/// `UITouch` cannot be built with a position, but SpriteKit's `location(in:)` arrives as
/// an Objective-C category method, so it is dispatched dynamically and a subclass can
/// override it. `GameScene`'s touch handlers only ever ask a touch where it is, which is
/// what makes real input reachable from a test at all.
final class HarnessTouch: UITouch {
    private let point: CGPoint

    init(_ point: CGPoint) {
        self.point = point
        super.init()
    }

    override func location(in node: SKNode) -> CGPoint { return point }
    override func previousLocation(in node: SKNode) -> CGPoint { return point }
}

@MainActor
final class GameplayHarness {

    let view: SKView
    /// Held so the window outlives the test; a released window takes the display link
    /// with it and the scene stops advancing mid-test.
    private let window: UIWindow
    private(set) var scene: GameScene!

    init(size: CGSize = CGSize(width: 390, height: 844)) {
        view = SKView(frame: CGRect(origin: .zero, size: size))

        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        window = windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: view.frame)
        window.frame = view.frame

        let host = UIViewController()
        host.view.addSubview(view)
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    /// Presents `GameScene` and runs it far enough that the deferred setup in
    /// `didMove(to:)` has built the player and every manager, then hands control over.
    @discardableResult
    func startPlaying(
        level: Int = 2,
        bulletCount: Int = 1,
        sideMissileCount: Int = 0
    ) -> GameScene {
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        scene.currentLevel = level
        scene.startingBulletCount = bulletCount
        scene.startingSideMissileCount = sideMissileCount

        // Deliberately no transition: with one the scene never finishes transitioning
        // in this environment and stays paused forever (see the type comment).
        view.presentScene(scene)
        self.scene = scene

        // didMove(to:) defers manager construction to DispatchQueue.main.async, so the
        // run loop has to turn before the scene is fully built.
        spin(0.8)

        // Stand in for setGameplayPaused(false), which is private.
        scene.gameContentNode?.isPaused = false
        scene.physicsWorld.speed = 1.0

        return scene
    }

    /// Presents the level and then waits for the intro to hand control over for real:
    /// the ship flies in from below and the completion of that animation calls
    /// `startGame()`. Once it returns, `isGameStarted` is true and input works.
    ///
    /// Level 2 by default, not 1 — level 1 adds the "3 2 1" countdown, which puts about
    /// seven more seconds on every test that uses it.
    @discardableResult
    func startPlayingWithControl(
        level: Int = 2,
        bulletCount: Int = 1,
        sideMissileCount: Int = 0,
        timeout: TimeInterval = 8.0
    ) -> GameScene {
        let scene = startPlaying(
            level: level, bulletCount: bulletCount, sideMissileCount: sideMissileCount
        )

        // The intro parks the ship at y = -50 and animates it up to its resting spot;
        // `startGame()` is that animation's *completion*, so control only arrives once the
        // ship has come to rest. Waiting for `y > 0` alone is not enough — it goes
        // positive part-way through the 0.8 s glide, and breaking there leaves
        // `isGameStarted` false and every touch ignored.
        //
        // Resting is detected by the y position repeating exactly: while the action runs
        // it changes every frame, and once it is done nothing else moves the ship until
        // the player touches the screen.
        var previousY = player.position.y
        var settled = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            spin(0.12)
            let y = player.position.y
            if y > 0 && y == previousY {
                settled = true
                break
            }
            previousY = y
        }

        XCTAssertTrue(
            settled,
            "the level intro never handed control to the player (ship at y=\(player.position.y)), "
            + "so nothing input-driven can be tested"
        )
        return scene
    }

    /// Presents any scene in the hosted view and lets it run.
    ///
    /// For the non-gameplay scenes — level complete, game over, level select — whose real
    /// work happens in `didMove(to:)`: `LevelCompleteScene` is where a finished run is
    /// persisted, so nothing about progress saving is observable without presenting it.
    /// Deliberately no `SKTransition`, for the reason in this type's comment: one never
    /// completes in a unit-test host and leaves the incoming scene paused forever.
    ///
    /// Note this leaves `scene`/`player` pointing at whatever `startPlaying()` last built,
    /// so don't mix the two in one test.
    func present(_ scene: SKScene, settle: TimeInterval = 0.6) {
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        spin(settle)
    }

    /// Lets the run loop — and with it the SKView's render loop, the action scheduler
    /// and the physics simulation — advance for `seconds`.
    func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    var gameContent: SKNode {
        guard let node = scene.gameContentNode else {
            XCTFail("gameplay layer was never built")
            return SKNode()
        }
        return node
    }

    /// Resolved once, when the level is built, and held from then on.
    ///
    /// Looking the ship up by name on every access is unreliable mid-test: the lookup is
    /// non-recursive, and anything that re-parents or removes the node — an effect, a
    /// death animation — turns every later access into a failure that reads as if the
    /// test's own subject had vanished. The node identity is what these tests care about.
    private var resolvedPlayer: Player?

    var player: Player {
        if let resolvedPlayer { return resolvedPlayer }
        guard let found = scene.gameContentNode?.childNode(withName: "player") as? Player else {
            XCTFail("player is not in the gameplay layer")
            return Player(sceneSize: view.bounds.size, safeAreaBottom: 0)
        }
        resolvedPlayer = found
        return found
    }

    /// Whether the ship is still attached to the playfield — false once it has been
    /// destroyed. Worth asserting in any test long enough for an enemy to reach it.
    var playerIsAlive: Bool {
        return resolvedPlayer?.parent != nil
    }

    /// Adds an enemy at a fixed position and registers it, without starting its
    /// movement or shooting actions — so it stays exactly where the test put it.
    @discardableResult
    func addEnemy(_ type: EnemyType = .basic, at position: CGPoint) -> Enemy {
        let enemy = Enemy(sceneSize: scene.size, scene: scene, type: type)
        enemy.position = position
        gameContent.addChild(enemy)
        scene.registerEnemy(enemy)
        return enemy
    }

    /// Fires real bullets out of the player and parks them on `target`, so the physics
    /// engine reports a genuine contact on the next step. Returns the bullets.
    @discardableResult
    func fireBullets(onto target: CGPoint) -> [SKShapeNode] {
        let bullets = player.shoot()
        for bullet in bullets {
            bullet.position = target
            gameContent.addChild(bullet)
        }
        return bullets
    }

    /// Fires real bullets that actually *fly*, the way `GameScene.shoot()` sends them:
    /// straight up, with the same move-then-remove action. Use this when the number of
    /// hits matters — a bullet parked inside an enemy overlaps it for many frames, which
    /// is not how a shot behaves in play.
    @discardableResult
    func fireMovingBullets(from origin: CGPoint) -> [SKShapeNode] {
        player.position = origin
        let bullets = player.shoot()
        for bullet in bullets {
            gameContent.addChild(bullet)
            bullet.run(SKAction.sequence([
                SKAction.moveTo(y: scene.size.height + 20, duration: 1.5),
                SKAction.removeFromParent()
            ]))
        }
        return bullets
    }

    /// An enemy bullet shaped the way `Enemy` builds them. Constructed here rather than
    /// driven out of `Enemy.startShooting()`, whose interval is randomised per instance
    /// and would make the test non-deterministic. The subject under test is
    /// `GameScene`'s handling of the contact, and that only reads the category mask.
    @discardableResult
    func addEnemyBullet(at position: CGPoint) -> SKShapeNode {
        let bullet = SKShapeNode(circleOfRadius: 4)
        bullet.name = "enemyBullet"
        bullet.position = position
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.enemyBullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.player
        bullet.physicsBody?.collisionBitMask = PhysicsCategory.none
        bullet.physicsBody?.usesPreciseCollisionDetection = true
        gameContent.addChild(bullet)
        return bullet
    }

    // MARK: - Input

    /// Bullets currently in the air. Each one is removed 1.5 s after it is fired, so this
    /// counts recent shots rather than every shot of the level — which is what makes it a
    /// usable proxy for fire rate.
    var bulletsInFlight: Int {
        return gameContent.children.filter { $0.name == "bullet" }.count
    }

    /// Clears the sky so the next count starts from a known zero.
    func clearBullets() {
        for bullet in gameContent.children where bullet.name == "bullet" {
            bullet.removeFromParent()
        }
    }

    /// Where a node sits in scene coordinates — what `touchesBegan` matches against via
    /// `nodes(at:)`. HUD nodes live under `uiNode`, not the scene, so this cannot just
    /// read `node.position`.
    func scenePosition(of node: SKNode) -> CGPoint {
        guard let parent = node.parent else { return node.position }
        return parent.convert(node.position, to: scene)
    }

    /// Finds a named node anywhere in the scene, HUD included.
    func node(named name: String) -> SKNode? {
        return scene.childNode(withName: "//\(name)")
    }

    func touchDown(at point: CGPoint) {
        scene.touchesBegan([HarnessTouch(point)], with: nil)
    }

    func touchMove(to point: CGPoint) {
        scene.touchesMoved([HarnessTouch(point)], with: nil)
    }

    /// Drags to `point` the way a finger does: `touchesMoved` repeatedly, over time.
    ///
    /// A single `touchesMoved` is not enough to observe. `touchesBegan` starts an animated
    /// `moveTo` glide, and that action keeps rewriting the ship's position every frame —
    /// so one `moveToInstant` is applied and then immediately overwritten. A real drag
    /// delivers a move per frame, which is what actually wins against the glide.
    func drag(to point: CGPoint, duration: TimeInterval = 0.35) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            touchMove(to: point)
            spin(0.02)
        }
        touchMove(to: point)
    }

    func touchUp(at point: CGPoint) {
        scene.touchesEnded([HarnessTouch(point)], with: nil)
    }

    /// Presses and holds directly over the ship — the normal way a player fires — then
    /// lets `update(_:)` drive the shooting for `seconds`.
    func holdFire(for seconds: TimeInterval, offsetX: CGFloat = 0) {
        let target = CGPoint(x: player.position.x + offsetX, y: player.position.y)
        touchDown(at: target)
        spin(seconds)
    }

    /// Presenting another scene runs `willMove(from:)`, which is where GameScene tears
    /// down its managers and observers. Leaving that out lets one test's scene keep
    /// reacting to notifications while the next one runs.
    func teardown() {
        view.presentScene(MenuScene(size: view.bounds.size))
        spin(0.3)
    }
}
