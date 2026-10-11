//
//  StoryEnding.swift
//  jetshot
//
//  "New Beginning" — the ending film. Each function is one shot; the order is in
//  `shots()`.
//

import SpriteKit
import simd

enum StoryEnding {

    static func shots() -> [StoryShot] {
        let paragraphs = L10n.Story.endingParagraphs
        func line(_ i: Int) -> String { i < paragraphs.count ? paragraphs[i] : "" }
        // Paragraph 10 is "∞". It is not set as a caption: the last shot draws it.
        return [
            stillness(line(0)),
            montage(line(1)),
            activation(line(2), protocolName: L10n.Story.protocolName),
            convergence(line(3)),
            bigBang(line(4)),
            firstStars(title: L10n.Story.endingTitle, line(5)),
            galaxy(line(6)),
            planet(line(7), question: line(8)),
            constellation(line(9)),
            infinity(thanks: line(11), saved: line(12) + "\n" + line(13))
        ]
    }

    // MARK: - 1. Stillness

    /// At the epicentre. The old universe folding in around a ship that made it.
    static func stillness(_ text: String) -> StoryShot {
        let shell = WireMesh.globe(radius: 420, rings: 12, meridians: 24, segments: 48)
        var rng = StoryRandom(seed: 201)
        let streams = (0..<70).map { _ in (dir: rng.direction(), speed: rng.float(0.05...0.12), phase: rng.unit()) }

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: Vec3(0, 7, 0), distance: 62 - 10 * p, yaw: 2.55 + t * 0.05,
                                          elevation: 0.2, fov: 58)
            f.look(camera)
            canvas.settings.fogNear = 200
            canvas.settings.fogFar = 700

            let fold = 1 - 0.5 * easeInOut(p)
            canvas.mesh(shell, rotation: rotation(t * 0.05, Vec3(0, 1, 0.2)), scale: fold,
                        color: StoryPalette.violet, alpha: 0.28, width: 1)
            for s in streams {
                let u = (t * s.speed + s.phase).truncatingRemainder(dividingBy: 1)
                let r = 420 * fold * (1 - u)
                let head = s.dir * r
                canvas.line(head, s.dir * (r + 30), color: StoryPalette.ice, alpha: smooth(0, 0.2, u) * 0.45, width: 1)
            }
            canvas.glow(Vec3(0, 20, 90), radius: 120, color: StoryPalette.gold, alpha: 0.22)
            canvas.glow(Vec3(0, 20, 90), radius: 30, color: StoryPalette.white, alpha: 0.4)
            let hover = Vec3(0, sin(t * 1.1) * 1.5, 0)
            StoryScenery.ship(canvas, at: hover, rotation: rotation(yaw: 0.25, roll: sin(t * 0.8) * 0.06),
                              color: StoryPalette.ice, engine: 0.35, t: t, width: 1.6)
        })
        shot.lines = [StoryLine(text: text, style: .cardHigh)]
        shot.lead = 1.6
        shot.tail = 1.4
        shot.minDuration = 7
        return shot
    }

    // MARK: - 2. What it took

    /// Flashbacks: four quick cuts of the run, each through a flash.
    static func montage(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 160, seed: 211)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let cut = min(3, Int(p * 4))
            let local = p * 4 - Float(cut)
            let cutStart = Float(cut) / 4 * f.duration
            if cut > 0 && f.crossed(cutStart) {
                f.cue(.flash(0.55))
                f.cue(.haptic(.light))
            }
            canvas.settings.fogNear = 200
            canvas.settings.fogFar = 700

            switch cut {
            case 0:
                // Collapsing dimensions.
                let camera = WireCamera.orbit(around: .zero, distance: 300 - 30 * local, yaw: t * 0.3, elevation: 0.3, fov: 58)
                f.look(camera)
                stars.draw(canvas, around: camera.position, t: t, alpha: 0.5)
                StoryOpening.tesseract(canvas, time: t + 1.1, at: .zero, scale: 38, spin: rotation(yaw: t * 0.3, pitch: 0.4),
                                       shatter: smooth(0.45, 1, local), split: 5)
                canvas.settings.offset = .zero
                canvas.applyOffset()

            case 1:
                // The entities, beaten.
                let camera = WireCamera(position: Vec3(0, 10, 125 - 20 * local), target: Vec3(0, 5, 0), fov: 58)
                f.look(camera)
                stars.draw(canvas, around: camera.position, t: t, alpha: 0.5)
                let blast = smooth(0.42, 1, local)
                StoryOpening.entity(canvas, kind: .spiked, at: .zero, t: t, alpha: 1, scale: 2.2, shatter: blast, seed: 0)
                StoryOpening.entity(canvas, kind: .crystal, at: Vec3(-62, 28, -50), t: t, alpha: 1, scale: 1.4,
                                    shatter: smooth(0.52, 1, local), seed: 1)
                StoryOpening.entity(canvas, kind: .cage, at: Vec3(58, -18, -36), t: t, alpha: 1, scale: 1.4,
                                    shatter: smooth(0.6, 1, local), seed: 2)
                if f.crossed(cutStart + 0.42 * f.duration / 4) { f.cue(.sound(.blast)) }
                if blast > 0 {
                    let (u, v) = StoryScenery.basis(Vec3(0, 0.2, 1))
                    canvas.polyline(StoryScenery.circle(center: .zero, radius: 10 + 160 * easeOut(blast), u: u, v: v, segments: 48),
                                    color: StoryPalette.ember, alpha: 1 - blast, width: 2.2)
                }

            case 2:
                // Spacetime falling in on itself.
                let camera = WireCamera.orbit(around: Vec3(0, -20, 0), distance: 200, yaw: t * 0.2, elevation: 0.7, fov: 58)
                f.look(camera)
                stars.draw(canvas, around: camera.position, t: t, alpha: 0.5)
                let pull = easeIn(local)
                for ring in 0..<12 {
                    let r0: Float = 12 + Float(ring) * 13
                    let r = r0 * (1 - 0.85 * pull)
                    let y = -60 * pull * (1 - Float(ring) / 12) - 20 * pull
                    let points = (0...36).map { s -> Vec3 in
                        let a = Float(s) / 36 * 2 * .pi + t * 2 * (1 - Float(ring) / 12) * (0.3 + pull)
                        return Vec3(cos(a) * r, y, sin(a) * r)
                    }
                    canvas.polyline(points, color: StoryPalette.mix(StoryPalette.violet, StoryPalette.cyan, Float(ring) / 11),
                                    alpha: 0.75, width: 1.3)
                }
                canvas.glow(Vec3(0, -70 * pull, 0), radius: 30 + 60 * pull, color: StoryPalette.violet, alpha: 0.5)

            default:
                // And through the last rift.
                let camera = WireCamera(position: Vec3(0, 8, 46), target: Vec3(0, 0, -100), fov: 60)
                f.look(camera)
                let open = easeOut(local)
                let (u, v) = StoryScenery.basis(Vec3(0, 0, 1))
                for layer in 0..<4 {
                    var r = StoryRandom(seed: 230 + UInt64(layer) &+ UInt64(t * 14))
                    let points = (0..<26).map { i -> Vec3 in
                        let a = Float(i) / 26 * 2 * .pi
                        let radius = (20 + 70 * open) * (1 - Float(layer) * 0.18) * (0.75 + 0.5 * r.unit())
                        return Vec3(0, 0, -160) + (u * cos(a) * 0.6 + v * sin(a) * 1.3) * radius
                    }
                    canvas.polyline(points, closed: true, color: layer == 0 ? StoryPalette.white : StoryPalette.violet,
                                    alpha: 0.9, width: 1.8)
                }
                canvas.glow(Vec3(0, 0, -160), radius: 60 + 100 * open, color: StoryPalette.violet, alpha: 0.7)
                StoryScenery.ship(canvas, at: Vec3(0, 0, -60 * local), rotation: rotation(sin(t) * 0.1, Vec3(0, 0, 1)),
                                  color: StoryPalette.ice, engine: 1.2, t: t)
            }
            f.shake(1.2)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 0.6
        shot.minDuration = 9
        return shot
    }

    // MARK: - 3. Big Bang Zero

    /// Time has stopped. Rings of the protocol assemble around the ship, spin up,
    /// and a countdown runs out.
    static func activation(_ text: String, protocolName: String) -> StoryShot {
        var rng = StoryRandom(seed: 221)
        let frozen = (0..<120).map { _ in rng.direction() * rng.float(40...240) }
        let ringAxes: [Vec3] = [Vec3(0, 1, 0.15), Vec3(1, 0.2, 0), Vec3(0.2, 0.3, 1)]
        let countdown: Float = 3.2

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: Vec3(0, 4, 0), distance: 120 - 30 * easeInOut(p),
                                          yaw: 2.4 + t * 0.05, elevation: 0.3, fov: 58)
            f.look(camera)
            canvas.settings.fogNear = 120
            canvas.settings.fogFar = 420

            // Dust hanging motionless: time stopped.
            for d in frozen { canvas.dot(d, size: 3, color: StoryPalette.ice, alpha: 0.5) }

            let spinUp = pow(p, 2.5) * 14
            for (i, axis) in ringAxes.enumerated() {
                let appear = f.ramp(0.8 + Float(i) * 0.9, 1.5 + Float(i) * 0.9)
                guard appear > 0 else { continue }
                let radius: Float = 34 + Float(i) * 9
                let q = rotation(t * 0.3 + spinUp * (1 + Float(i) * 0.3), axis)
                let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
                let arc = StoryScenery.circle(center: .zero, radius: radius, u: u, v: v, segments: 64,
                                              from: 0, to: 2 * .pi * appear)
                canvas.polyline(arc, color: StoryPalette.gold, alpha: 0.95, width: 1.8)
                StoryScenery.dashedRing(canvas, center: .zero, radius: radius + 4, u: u, v: v, phase: -t * 0.5 - spinUp,
                                        dashes: 24, fill: 0.25, color: StoryPalette.sun, alpha: appear * 0.8, width: 1.2)
                if appear > 0.99 {
                    for k in 0..<4 {
                        let a = Float(k) / 4 * 2 * .pi + spinUp
                        canvas.line((u * cos(a) + v * sin(a)) * radius, .zero, color: StoryPalette.gold,
                                    alpha: 0.15 + 0.5 * p, width: 1)
                    }
                }
                if f.crossed(0.8 + Float(i) * 0.9) { f.cue(.sound(.charge)) }
            }
            canvas.glow(.zero, radius: 30 + 40 * p, color: StoryPalette.gold, alpha: 0.3 + 0.5 * p)
            StoryScenery.ship(canvas, at: .zero, rotation: rotation(yaw: 0.4), color: StoryPalette.ice,
                              engine: 0.3 + p, t: t, width: 1.6)

            // HUD: the protocol's name across the top, then the count.
            let frame = f.overlay.frame
            let named = f.ramp(0.6, 1.0)
            f.overlay.tag("protocol", protocolName, at: CGPoint(x: frame.midX, y: frame.maxY - 34),
                          size: 13, color: StoryPalette.gold, reveal: f.ramp(0.8, 2.4), alpha: named,
                          align: .center, tracking: 3, blink: t)
            let countStart = f.duration - countdown
            if t >= countStart {
                let step = min(3, Int((t - countStart) / (countdown / 4)))
                let local = (t - countStart) / (countdown / 4) - Float(step)
                f.overlay.tag("count", String(format: "%02d", 3 - step), at: CGPoint(x: frame.midX, y: frame.maxY - 80),
                              size: 40, color: step == 3 ? StoryPalette.white : StoryPalette.gold,
                              alpha: 1 - 0.6 * local, align: .center, tracking: 6)
                for s in 0..<4 where f.crossed(countStart + Float(s) * countdown / 4) {
                    f.cue(.haptic(s == 3 ? .heavy : .tick))
                }
                f.shake(Float(step) * 0.8)
            }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 1.4
        shot.tail = TimeInterval(countdown) - 0.4
        shot.minDuration = 10
        return shot
    }

    // MARK: - 4. The seed

    /// All the energy the run gathered pours into the ship, and the ship becomes a
    /// single point of light.
    static func convergence(_ text: String) -> StoryShot {
        var rng = StoryRandom(seed: 241)
        let motes = (0..<260).map { _ in
            (dir: rng.direction(), phase: rng.unit(), turn: rng.float(1.5...3.5), gold: rng.unit() > 0.4)
        }

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: .zero, distance: 150 - 70 * easeInOut(p), yaw: -0.4 + t * 0.06,
                                          elevation: 0.2, fov: 58)
            f.look(camera)
            canvas.settings.fogNear = 200
            canvas.settings.fogFar = 600

            let collapse = f.pramp(0.82, 1)
            for m in motes {
                let u = (t * (0.12 + 0.25 * p) + m.phase).truncatingRemainder(dividingBy: 1)
                let r = 260 * pow(1 - u, 1.3) * (1 - collapse)
                let twist = rotation(u * m.turn, Vec3(0, 1, 0.2))
                let pos = twist.act(m.dir) * r
                let tail = rotation((u - 0.03) * m.turn, Vec3(0, 1, 0.2)).act(m.dir) * (r + 14)
                let color = m.gold ? StoryPalette.gold : StoryPalette.cyan
                let fade = smooth(0, 0.15, u)
                canvas.line(tail, pos, color: color, alpha: fade * 0.8, width: 1.1)
                canvas.dot(pos, size: 4, color: StoryPalette.white, alpha: fade)
            }
            let dissolve = f.pramp(0.45, 0.85)
            let charge = 0.3 + 0.7 * p
            canvas.glow(.zero, radius: 20 + 70 * charge * (1 - collapse * 0.7), color: StoryPalette.gold, alpha: 0.5 + 0.4 * charge)
            canvas.glow(.zero, radius: 8 + 20 * charge, color: StoryPalette.white, alpha: charge)
            if dissolve < 1 {
                StoryScenery.ship(canvas, at: .zero, rotation: rotation(yaw: -0.5 + t * 0.1), scale: 1 - 0.3 * dissolve,
                                  color: StoryPalette.mix(StoryPalette.ice, StoryPalette.gold, dissolve),
                                  alpha: 1 - dissolve, engine: 1 - dissolve, t: t, width: 1.6)
            }
            if collapse > 0 {
                canvas.flare(.zero, length: Float(canvas.viewport.width) * 1.4 * collapse, thickness: 8,
                             color: StoryPalette.white, alpha: collapse)
            }
            f.shake(dissolve * 1.5)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.minDuration = 9
        shot.cues = [(0.3, .sound(.energy)), (0.86, .haptic(.medium))]
        return shot
    }

    // MARK: - 5. Bang

    private static let shockShell = WireMesh.geodesic(radius: 1, subdivisions: 2)
    private static let innerShell = WireMesh.geodesic(radius: 1, subdivisions: 1)

    /// A point, a pause, and then everything.
    static func bigBang(_ text: String) -> StoryShot {
        var rng = StoryRandom(seed: 251)
        let burst = (0..<340).map { _ in (dir: rng.direction(), speed: rng.float(0.25...1)) }
        let bangAt: Float = 1.9

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let e = max(0, t - bangAt)
            let orbit = e * 0.05
            let pull: Float = 260 + 140 * easeOut(e / 6)
            let camera = WireCamera(position: Vec3(sin(orbit) * pull + sin(t * 0.2) * 20, 30 + 20 * smooth(2, 8, e), cos(orbit) * pull),
                                    target: .zero, roll: sin(t * 0.3) * 0.04, fov: 62)
            f.look(camera)
            canvas.settings.fogNear = 600
            canvas.settings.fogFar = 1600
            canvas.settings.widthReference = 260

            if e <= 0 {
                // An infinitesimal point of infinite density.
                let tremble: Float = 1 + 0.3 * sin(t * 40) * f.ramp(0.6, bangAt)
                canvas.glow(.zero, radius: 6 * tremble, color: StoryPalette.white, alpha: 1)
                canvas.glow(.zero, radius: 24 * tremble, color: StoryPalette.violet, alpha: 0.4)
                let (u, v) = StoryScenery.basis(camera.position)
                for k in 0..<3 {
                    let ring = (t * 0.7 + Float(k) / 3).truncatingRemainder(dividingBy: 1)
                    canvas.polyline(StoryScenery.circle(center: .zero, radius: 120 * (1 - ring), u: u, v: v, segments: 48),
                                    color: StoryPalette.ice, alpha: ring * 0.6, width: 1.2)
                }
                f.shake(f.ramp(1.0, bangAt) * 2)
                return
            }

            let cool = smooth(0.5, 6, e)
            let hot = StoryPalette.mix(StoryPalette.white, StoryPalette.gold, smooth(0, 1.2, e))
            let cooled = StoryPalette.mix(hot, StoryPalette.violet, cool)
            let shell = 900 * easeOut(e / 3.5)
            canvas.mesh(shockShell, rotation: rotation(e * 0.2, Vec3(0, 1, 0)), scale: shell,
                        color: hot, alpha: 1 - smooth(0.5, 3.5, e), width: 2)
            let innerRadius = 600 * easeOut(e / 5)
            canvas.mesh(innerShell, rotation: rotation(-e * 0.3, Vec3(1, 0, 0)), scale: innerRadius,
                        color: StoryPalette.violet, alpha: (0.8 - 0.6 * cool) * (1 - smooth(180, 320, innerRadius)), width: 1.6)

            // Space itself, born and stretching: a lattice whose every cell grows.
            let lattice = smooth(1.2, 3.5, e)
            if lattice > 0 {
                let spacing: Float = 18 + 42 * easeOut((e - 1.2) / 8)
                let turn = rotation(0.5 + e * 0.08, Vec3(0.3, 1, 0.1))
                let n = 2
                let extent = Float(n) * spacing
                for i in -n...n {
                    for j in -n...n {
                        let a = Float(i) * spacing, b = Float(j) * spacing
                        let fade = lattice * 0.5 * (1 - Float(abs(i) + abs(j)) / Float(2 * n + 2))
                        canvas.line(turn.act(Vec3(-extent, a, b)), turn.act(Vec3(extent, a, b)), color: StoryPalette.cyan, alpha: fade, width: 1)
                        canvas.line(turn.act(Vec3(a, -extent, b)), turn.act(Vec3(a, extent, b)), color: StoryPalette.blue, alpha: fade, width: 1)
                        canvas.line(turn.act(Vec3(a, b, -extent)), turn.act(Vec3(a, b, extent)), color: StoryPalette.violet, alpha: fade, width: 1)
                    }
                }
            }

            // Matter: a cloud of it, cooling from white to violet as it spreads.
            for (i, b) in burst.enumerated() where i % 2 == 0 {
                let drift = b.dir * (30 + 230 * b.speed * easeOut(e / 4))
                let wobble = rotation(e * 0.1, Vec3(0, 1, 0)).act(drift)
                canvas.dot(wobble, size: 8, color: i % 6 == 0 ? StoryPalette.cyan : cooled, alpha: smooth(0.4, 1.4, e))
            }

            for (i, b) in burst.enumerated() {
                let reach = 820 * b.speed * (1 - exp(-e * 0.9))
                let previous = 820 * b.speed * (1 - exp(-(max(0, e - 0.12)) * 0.9))
                let color = i % 5 == 0 ? StoryPalette.cyan : cooled
                canvas.line(b.dir * previous, b.dir * reach, color: color, alpha: 1 - 0.5 * cool, width: 1.3)
            }
            for ray in 0..<24 {
                let a = Float(ray) / 24 * 2 * .pi + e * 0.05
                let dir = Vec3(cos(a), sin(a) * 0.6, sin(a) * 0.8)
                canvas.line(dir * 20, dir * 1400 * easeOut(e / 2), color: StoryPalette.sun,
                            alpha: 0.5 * (1 - smooth(0.2, 2.5, e)), width: 1.4)
            }
            canvas.glow(.zero, radius: 60 + 300 * easeOut(e / 2), color: StoryPalette.sun, alpha: 1 - smooth(0, 3, e))
            canvas.glow(.zero, radius: 30, color: StoryPalette.white, alpha: 0.6 - 0.4 * cool)
            if f.crossed(bangAt) {
                f.cue(.flash(1))
                f.cue(.shake(11, 1.4))
                f.cue(.sound(.bigBang))
                f.cue(.sound(.blast))
                f.cue(.haptic(.heavy))
            }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 3.0
        shot.minDuration = 10
        return shot
    }

    // MARK: - 6. First light

    /// Dust gathers into clumps; one by one they ignite. Under them a new
    /// spacetime unrolls, and the axes of new dimensions settle into place.
    static func firstStars(title: String, _ text: String) -> StoryShot {
        var rng = StoryRandom(seed: 261)
        let clusters = (0..<7).map { i in
            (centre: Vec3(rng.float(-260...260), rng.float(-40...160), rng.float(-260...120)),
             ignite: 2.4 + Float(i) * 1.35,
             color: [StoryPalette.sun, StoryPalette.ice, StoryPalette.gold, StoryPalette.cyan][i % 4])
        }
        let dust = (0..<420).map { i in (cluster: i % 7, offset: Vec3(rng.gaussian(), rng.gaussian(), rng.gaussian())) }
        let starMesh = WireMesh.geodesic(radius: 7, subdivisions: 1)
        let frames: [(from: simd_quatf, to: simd_quatf)] = [
            (rotation(1.9, Vec3(1, 0.4, 0.2)), identityRotation),
            (rotation(2.4, Vec3(0.2, 1, 0.7)), rotation(.pi / 2, Vec3(1, 0, 0))),
            (rotation(1.3, Vec3(0.6, 0.1, 1)), rotation(.pi / 2, Vec3(0, 0, 1)))
        ]
        let square = WireMesh.box(Vec3(260, 0, 260))

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: Vec3(0, 30, 0), distance: 620 - 80 * p, yaw: 0.5 + t * 0.04,
                                          elevation: 0.22 + 0.1 * p, fov: 60)
            f.look(camera)
            canvas.settings.fogNear = 500
            canvas.settings.fogFar = 1400
            canvas.settings.widthReference = 500

            // New spacetime, unrolling from the centre.
            let reach = 950 * easeOut(f.ramp(0.5, f.duration * 0.8))
            let floorY: Float = -140
            for i in -15...15 {
                let o = Float(i) * 60
                guard abs(o) < reach else { continue }
                let half = (reach * reach - o * o).squareRoot()
                canvas.line(Vec3(o, floorY, -half), Vec3(o, floorY, half), color: StoryPalette.cyan, alpha: 0.4, width: 1.1)
                canvas.line(Vec3(-half, floorY, o), Vec3(half, floorY, o), color: StoryPalette.cyan, alpha: 0.4, width: 1.1)
            }

            // New dimensions, turning from chaos into right angles.
            let order = f.pramp(0.25, 0.85)
            for (i, frame) in frames.enumerated() {
                let q = simd_slerp(frame.from, frame.to, order)
                canvas.mesh(square, at: Vec3(0, 30, 0), rotation: q,
                            color: [StoryPalette.violet, StoryPalette.gold, StoryPalette.cyan][i],
                            alpha: 0.1 + 0.18 * order, width: 1.1)
            }

            // Dust, contracting into stars.
            for d in dust {
                let c = clusters[d.cluster]
                let gather = smooth(c.ignite - 2.6, c.ignite, t)
                let spread: Float = 46 * (1 - 0.9 * gather)
                let swirl = rotation(t * 0.3 * (1 + gather), Vec3(0, 1, 0.3))
                canvas.dot(c.centre + swirl.act(d.offset * spread), size: 3.5, color: c.color,
                           alpha: 0.35 + 0.3 * gather)
            }
            for (i, c) in clusters.enumerated() {
                let since = t - c.ignite
                guard since > 0 else { continue }
                let burst = 1 - smooth(0, 1.2, since)
                canvas.glow(c.centre, radius: 26 + 90 * burst, color: c.color, alpha: 0.5 + 0.5 * burst)
                canvas.glow(c.centre, radius: 8, color: StoryPalette.white, alpha: 1)
                canvas.mesh(starMesh, at: c.centre, rotation: rotation(t * 0.5 + Float(i), Vec3(0.2, 1, 0)),
                            scale: smooth(0, 0.6, since), color: c.color, alpha: 0.9, width: 1.3, backAlpha: 0.35)
                if let s = canvas.project(c.centre) {
                    let glint = CGFloat(20 + 70 * burst)
                    canvas.line2D(CGPoint(x: s.x - glint, y: s.y), CGPoint(x: s.x + glint, y: s.y), color: c.color, alpha: 0.6, width: 1)
                    canvas.line2D(CGPoint(x: s.x, y: s.y - glint * 0.7), CGPoint(x: s.x, y: s.y + glint * 0.7), color: c.color, alpha: 0.6, width: 1)
                }
                if f.crossed(c.ignite) { f.cue(.haptic(.light)) }
            }
        })
        shot.entry = .fade
        shot.lines = [StoryLine(text: title, style: .title), StoryLine(text: text, style: .subtitle, delay: 0.2)]
        shot.lead = 1.0
        shot.minDuration = 12
        return shot
    }

    // MARK: - 7. Galaxy

    static func galaxy(_ text: String) -> StoryShot {
        var rng = StoryRandom(seed: 271)
        let palette = [StoryPalette.ice, StoryPalette.cyan, StoryPalette.violet, StoryPalette.magenta, StoryPalette.white]
        let stars = (0..<720).map { _ -> (r: Float, theta: Float, y: Float, color: UIColor, size: Float) in
            let r = 18 + 330 * pow(rng.unit(), 0.9)
            let arm: Float = rng.unit() > 0.5 ? 0 : .pi
            let theta = arm + log(r / 18) / 0.32 + rng.gaussian() * 0.22
            let y = rng.gaussian() * 7 * (1 - r / 420)
            let core = r < 70
            let color = core ? (rng.unit() > 0.5 ? StoryPalette.sun : StoryPalette.white)
                : palette[Int(rng.unit() * Float(palette.count)) % palette.count]
            return (r, theta, y, color, core ? 4.5 : rng.float(2.5...4.5))
        }
        let guides = [WireMesh.ring(radius: 120, segments: 72, ticks: 24, tickLength: 4),
                      WireMesh.ring(radius: 240, segments: 96, ticks: 36, tickLength: 5),
                      WireMesh.ring(radius: 360, segments: 120)]
        let background = StoryStarfield(count: 180, seed: 272)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: .zero, distance: 400 + 200 * easeInOut(p), yaw: t * 0.05,
                                          elevation: 0.85 - 0.25 * p, roll: 0.12, fov: 58)
            f.look(camera)
            background.draw(canvas, around: camera.position, t: t, alpha: 0.5)
            canvas.settings.fogNear = 900
            canvas.settings.fogFar = 2000
            canvas.settings.widthReference = 600

            for (i, ring) in guides.enumerated() {
                canvas.mesh(ring, rotation: rotation(t * 0.02 * Float(i + 1), Vec3(0, 1, 0)),
                            color: StoryPalette.cyan, alpha: 0.12, width: 1)
            }
            for s in stars {
                // Inner orbits turn faster than outer ones.
                let a = s.theta + t * 0.5 / (1 + s.r / 60)
                canvas.dot(Vec3(cos(a) * s.r, s.y, sin(a) * s.r), size: s.size, color: s.color, alpha: 0.85)
            }
            canvas.glow(.zero, radius: 150, color: StoryPalette.gold, alpha: 0.35)
            canvas.glow(.zero, radius: 45, color: StoryPalette.white, alpha: 0.8)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.minDuration = 9
        return shot
    }

    // MARK: - 8. A world

    /// A young planet with a moon, and its sun rising over the limb.
    static func planet(_ text: String, question: String) -> StoryShot {
        let globe = WireMesh.globe(radius: 60, rings: 12, meridians: 18, segments: 48)
        let moon = WireMesh.geodesic(radius: 8, subdivisions: 1)
        let stars = StoryStarfield(count: 220, seed: 281)
        var rng = StoryRandom(seed: 282)
        let continents: [[Vec3]] = (0..<6).map { _ in
            let centre = rng.direction()
            let (u, v) = StoryScenery.basis(centre)
            let size = rng.float(0.22...0.42)
            return (0..<24).map { k in
                let a = Float(k) / 24 * 2 * .pi
                let wobble = size * (0.7 + 0.5 * rng.unit())
                return simd_normalize(centre + (u * cos(a) + v * sin(a)) * wobble) * 60.6
            }
        }
        let axis = simd_normalize(Vec3(0.25, 1, 0))
        let sun = Vec3(-520, 70, -1100)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let travel = easeInOut(p)
            let camera = WireCamera(position: Vec3(70 - 150 * travel, 20, 300 - 90 * travel),
                                    target: Vec3(-25 * travel, 0, 0), roll: 0.08, fov: 58)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.7)
            canvas.settings.fogNear = 2000
            canvas.settings.fogFar = 4000
            canvas.settings.depthSplit = canvas.depth(of: .zero)

            // The sun, behind the planet until the camera clears the limb.
            canvas.glow(sun, radius: 260, color: StoryPalette.gold, alpha: 0.45)
            canvas.glow(sun, radius: 60, color: StoryPalette.sun, alpha: 1)
            canvas.glow(sun, radius: 20, color: StoryPalette.white, alpha: 1)
            if let s = canvas.project(sun), let c = canvas.project(.zero) {
                let limb = canvas.screenSize(of: 60, at: .zero)
                let gap = hypot(s.x - c.x, s.y - c.y)
                let clear = smooth(Float(limb * 0.95), Float(limb * 1.25), Float(gap))
                canvas.flare(sun, length: Float(canvas.viewport.width) * 1.5, thickness: 12, color: StoryPalette.sun,
                             alpha: clear * 0.8)
            }

            canvas.disc(.zero, radius: 60, color: UIColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1))
            let spin = rotation(t * 0.12, axis)
            canvas.mesh(globe, rotation: spin, color: StoryPalette.blue, alpha: 0.75, width: 1.1, backAlpha: 0.1)
            for c in continents {
                canvas.polyline(c.map { spin.act($0) }, closed: true, color: StoryPalette.green, alpha: 0.9, width: 1.5)
            }
            let (u, v) = StoryScenery.basis(camera.position)
            canvas.polyline(StoryScenery.circle(center: .zero, radius: 62.5, u: u, v: v, segments: 72),
                            color: StoryPalette.cyan, alpha: 0.7, width: 2.2)
            canvas.glow(.zero, radius: 80, color: StoryPalette.cyan, alpha: 0.12)

            let orbit = t * 0.35 + 2.2
            let moonPos = Vec3(cos(orbit) * 130, sin(orbit) * 22, sin(orbit) * 130)
            canvas.mesh(moon, at: moonPos, rotation: rotation(t * 0.4, Vec3(0, 1, 0)), color: StoryPalette.ice,
                        alpha: 0.85, width: 1.2, backAlpha: 0.2)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle), StoryLine(text: question, style: .cardHigh, delay: 0.4)]
        shot.minDuration = 11
        return shot
    }

    // MARK: - 9. The legend

    /// Under a new sky, stars draw the outline of the Singularity-7.
    static func constellation(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 420, seed: 291)
        let outline = WireMesh.shipOutline2D.map { Vec3($0.x * 15, $0.y * 15 + 270, -760) }
        var rng = StoryRandom(seed: 292)
        let ridges: [[Vec3]] = (0..<3).map { layer in
            let z = -300 - Float(layer) * 160
            let base = -110 + Float(layer) * 28
            return (0...40).map { i in
                Vec3(-700 + Float(i) * 35, base + rng.float(0...46) * (1 + Float(layer) * 0.6), z)
            }
        }

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera(position: Vec3(0, 0, 120), target: Vec3(0, 40 + 170 * easeInOut(p), -700), fov: 60)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.8)
            canvas.settings.fogNear = 1500
            canvas.settings.fogFar = 3000

            for (layer, ridge) in ridges.enumerated() {
                canvas.polyline(ridge, color: layer == 0 ? StoryPalette.violet : StoryPalette.blue,
                                alpha: 0.7 - Float(layer) * 0.2, width: 1.3)
            }

            let draw = f.pramp(0.12, 0.75)
            let count = outline.count
            let progress = draw * Float(count)
            for i in 0..<count {
                let lit = clamp01(progress - Float(i) + 1)
                guard lit > 0 else { continue }
                let next = outline[(i + 1) % count]
                let along = clamp01(progress - Float(i))
                if along > 0 {
                    canvas.line(outline[i], lerp(outline[i], next, along), color: StoryPalette.ice, alpha: 0.55, width: 1.2)
                }
                let twinkle: Float = 0.8 + 0.2 * sin(t * 3 + Float(i))
                canvas.dot(outline[i], size: 9 * twinkle, color: StoryPalette.white, alpha: lit)
                canvas.glow(outline[i], radius: 9, color: StoryPalette.cyan, alpha: lit * 0.4)
            }
            let finished = f.pramp(0.75, 0.85)
            if finished > 0 {
                canvas.glow(Vec3(0, 270, -760), radius: 300, color: StoryPalette.cyan, alpha: 0.15 * finished)
            }

            // A shooting star.
            let streak = f.pramp(0.86, 0.95)
            if streak > 0 && streak < 1 {
                let a = Vec3(260, 300, -700), b = Vec3(-200, 180, -700)
                let head = lerp(a, b, streak)
                canvas.line(lerp(a, b, max(0, streak - 0.15)), head, color: StoryPalette.white, alpha: 1 - streak, width: 1.6)
            }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 1.4
        shot.minDuration = 10
        return shot
    }

    // MARK: - 10. Infinity

    private static func lemniscate(_ s: Float, size: Float) -> Vec3 {
        let d = 1 + sin(s) * sin(s)
        return Vec3(size * cos(s) / d, size * sin(s) * cos(s) / d, size * 0.18 * sin(2 * s))
    }

    /// The figure of infinity, traced in light, with the ship flying it forever.
    static func infinity(thanks: String, saved: String) -> StoryShot {
        let stars = StoryStarfield(count: 260, seed: 301)
        let samples = 160

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: Vec3(0, 10, 0), distance: 430, yaw: sin(t * 0.12) * 0.5,
                                          elevation: 0.18 + 0.08 * sin(t * 0.2), fov: 56)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.8)
            canvas.settings.fogNear = 800
            canvas.settings.fogFar = 1600
            canvas.settings.widthReference = 420

            let spin = rotation(sin(t * 0.25) * 0.35, Vec3(0, 1, 0))
            let size: Float = 175
            let traced = f.ramp(0.3, 3.2)
            let shown = Int(Float(samples) * traced)
            var previous = spin.act(lemniscate(0, size: size))
            for i in 1...max(1, shown) {
                let s = Float(i) / Float(samples) * 2 * .pi
                let point = spin.act(lemniscate(s, size: size))
                let k = Float(i) / Float(samples)
                let color = StoryPalette.mix(StoryPalette.gold, StoryPalette.cyan, 0.5 + 0.5 * sin(k * 2 * .pi + t))
                canvas.line(previous, point, color: color, alpha: 0.95, width: 2.2)
                previous = point
            }
            if traced >= 1 {
                for k in 0..<36 {
                    let s = (Float(k) / 36 + t * 0.06).truncatingRemainder(dividingBy: 1) * 2 * .pi
                    canvas.dot(spin.act(lemniscate(s, size: size)), size: 6, color: StoryPalette.white, alpha: 0.8)
                }
                let s = (t - 3) * 0.45
                let here = spin.act(lemniscate(s, size: size))
                let ahead = spin.act(lemniscate(s + 0.02, size: size))
                let heading = simd_normalize(ahead - here)
                let q = simd_quatf(from: Vec3(0, 0, -1), to: heading)
                StoryScenery.ship(canvas, at: here, rotation: q, scale: 0.8, color: StoryPalette.ice,
                                  alpha: f.ramp(3.0, 3.8), engine: 1, t: t, width: 1.5)
            }
            canvas.glow(.zero, radius: 40, color: StoryPalette.sun, alpha: 0.3 * traced)
        })
        shot.lines = [
            StoryLine(text: thanks, style: .cardHigh),
            StoryLine(text: saved, style: .cardHigh, delay: 0.4)
        ]
        shot.lead = 3.8
        shot.tail = 1.6
        shot.minDuration = 12
        return shot
    }
}
