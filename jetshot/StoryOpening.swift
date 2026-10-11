//
//  StoryOpening.swift
//  jetshot
//
//  "End of Ages" — the opening film. Each function is one shot; the order is in
//  `shots()`. The props several shots share (the tesseract, the entities, the
//  epicentre) are here too, and the ending film reuses them for its flashbacks.
//

import SpriteKit
import simd

enum StoryOpening {

    static func shots() -> [StoryShot] {
        let paragraphs = L10n.Story.openingParagraphs
        func line(_ i: Int) -> String { i < paragraphs.count ? paragraphs[i] : "" }
        return [
            endOfAges(title: L10n.Story.openingTitle, line: line(0)),
            gravityWell(line(1)),
            quantumBleed(line(2)),
            shipReveal(line(3), name: L10n.Story.shipName),
            ignition(line(4)),
            riftRun(line(5)),
            epicenter(line(6), protocolName: L10n.Story.protocolName),
            entities(line(7)),
            plunge(line(8), line(9), line(10)),
            logo()
        ]
    }

    // MARK: - 1. The end of ages

    /// Dying stars over a horizon of spacetime grid. One of them goes out.
    static func endOfAges(title: String, line: String) -> StoryShot {
        let stars = StoryStarfield(count: 240, seed: 11)
        let giant = WireMesh.globe(radius: 150, rings: 12, meridians: 18, segments: 48)
        let dwarf = WireMesh.geodesic(radius: 14, subdivisions: 1)
        let doomed = WireMesh.geodesic(radius: 30, subdivisions: 1)
        var rng = StoryRandom(seed: 12)
        let dust = (0..<80).map { _ in Vec3(rng.float(-220...220), rng.float(4...120), rng.float(-500...160)) }
        let sparks = (0..<28).map { _ in rng.direction() }

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let travel: Float = 90 * easeInOut(p)
            let camera = WireCamera(
                position: Vec3(sin(t * 0.07) * 14, 18 + 10 * p, 160 - travel),
                target: Vec3(0, 70, -400),
                roll: sin(t * 0.31) * 0.025, fov: 64
            )
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.8)

            // Spacetime, flat to the horizon.
            canvas.settings.fogNear = 40
            canvas.settings.fogFar = 1100
            for i in 0...40 {
                let x = Float(i - 20) * 32
                canvas.line(Vec3(x, 0, -1200), Vec3(x, 0, 240), color: StoryPalette.cyan, alpha: 0.34, width: 1.1)
            }
            for i in 0...45 {
                let z = 240 - Float(i) * 32
                canvas.line(Vec3(-660, 0, z), Vec3(660, 0, z), color: StoryPalette.cyan, alpha: 0.34, width: 1.1)
            }
            for (i, d) in dust.enumerated() {
                let drift = Vec3(t * 3, sin(t * 0.5 + Float(i)) * 2, 0)
                canvas.dot(d + drift, size: 3, color: StoryPalette.ice, alpha: 0.35)
            }

            // The sky is too far to fog.
            canvas.settings.fogNear = 4000
            canvas.settings.fogFar = 8000
            canvas.flare(Vec3(0, 0, -1150), length: Float(canvas.viewport.width) * 1.6, thickness: 30,
                         color: StoryPalette.ember, alpha: 0.4)
            canvas.glow(Vec3(0, -20, -1150), radius: 260, color: StoryPalette.ember, alpha: 0.25)

            // Nebulae: the last colour left in the sky.
            canvas.glow(Vec3(260, 420, -1300), radius: 700, color: StoryPalette.violet, alpha: 0.13)
            canvas.glow(Vec3(-420, 160, -1200), radius: 520, color: StoryPalette.blue, alpha: 0.1)

            // A red giant, swelling in its last breaths, throwing loops of plasma.
            let giantPos = Vec3(-170, 235, -600)
            let swell: Float = 1 + 0.03 * sin(t * 2.1)
            canvas.glow(giantPos, radius: 380, color: StoryPalette.ember, alpha: 0.3)
            canvas.mesh(giant, at: giantPos, rotation: rotation(t * 0.08, Vec3(0.2, 1, 0.1)), scale: swell,
                        color: StoryPalette.ember, alpha: 0.7, width: 1.3, backAlpha: 0.18)
            canvas.glow(giantPos, radius: 110, color: StoryPalette.sun, alpha: 0.2)
            let (gu, gv) = StoryScenery.basis(camera.position - giantPos)
            for loop in 0..<5 {
                let a = Float(loop) * 1.26 + 0.4
                let base = gu * cos(a) + gv * sin(a)
                let side = gu * -sin(a) + gv * cos(a)
                let rise: Float = 0.18 + 0.1 * sin(t * 0.9 + Float(loop) * 2)
                let points = (0...16).map { k -> Vec3 in
                    let s = Float(k) / 16 * .pi
                    return giantPos + base * (150 * swell + 150 * rise * sin(s)) + side * 150 * 0.16 * cos(s)
                }
                canvas.polyline(points, color: StoryPalette.gold, alpha: 0.7, width: 1.3)
            }

            // A white dwarf, guttering.
            let dwarfPos = Vec3(230, 150, -560)
            let flicker: Float = 0.55 + 0.45 * abs(sin(t * 7.3) * sin(t * 2.9))
            canvas.mesh(dwarf, at: dwarfPos, rotation: rotation(t * 0.5, Vec3(0, 1, 0.3)),
                        color: StoryPalette.ice, alpha: flicker * 0.9, width: 1.2, backAlpha: 0.3)
            canvas.glow(dwarfPos, radius: 60, color: StoryPalette.ice, alpha: flicker * 0.35)

            // And one that goes out: it falls in on itself, then a ring of light.
            let doomedPos = Vec3(90, 330, -900)
            let collapseAt = f.duration * 0.6
            let k = clamp01((t - collapseAt) / 0.8)
            if t < collapseAt + 0.8 {
                let s = 1 - easeIn(k)
                let tremor: Float = k > 0 ? 1 + 0.08 * sin(t * 60) : 1
                canvas.mesh(doomed, at: doomedPos, rotation: rotation(t * 0.3, Vec3(1, 1, 0)),
                            scale: max(0.02, s) * tremor, color: StoryPalette.gold, alpha: 0.9, backAlpha: 0.3)
                canvas.glow(doomedPos, radius: 80 * s + 12 * k, color: StoryPalette.gold, alpha: 0.35 + 0.5 * k)
            }
            let after = t - (collapseAt + 0.8)
            if after > 0 {
                let e = easeOut(after / 2.6)
                let fade = 1 - smooth(0.3, 2.8, after)
                let (u, v) = StoryScenery.basis(camera.position - doomedPos)
                canvas.glow(doomedPos, radius: 40 + 260 * e, color: StoryPalette.white, alpha: fade * 0.55)
                canvas.polyline(StoryScenery.circle(center: doomedPos, radius: 20 + 440 * e, u: u, v: v, segments: 72),
                                color: StoryPalette.gold, alpha: fade * 0.85, width: 2)
                canvas.polyline(StoryScenery.circle(center: doomedPos, radius: 10 + 300 * e, u: u, v: v, segments: 64),
                                color: StoryPalette.ember, alpha: fade * 0.5, width: 1.4)
                for d in sparks {
                    canvas.line(doomedPos + d * (30 + 380 * e), doomedPos + d * (50 + 520 * e),
                                color: StoryPalette.sun, alpha: fade, width: 1.2)
                }
            }
            if f.crossed(collapseAt + 0.8) {
                f.cue(.flash(0.2))
                f.cue(.sound(.blast))
                f.cue(.haptic(.medium))
            }
        })
        shot.lines = [StoryLine(text: title, style: .title), StoryLine(text: line, style: .subtitle, delay: 0.3)]
        shot.lead = 1.4
        shot.minDuration = 10
        return shot
    }

    // MARK: - 2. Collapse

    /// Spacetime dragged down a black hole: a funnel of grid, an accretion disc,
    /// stars spiralling in and stretching as they go.
    static func gravityWell(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 220, seed: 21)
        var rng = StoryRandom(seed: 22)
        let infall = (0..<26).map { _ in
            (r0: rng.float(70...190), a0: rng.float(0...(2 * .pi)), speed: rng.float(0.08...0.18), phase: rng.unit())
        }
        let ringRadii: [Float] = (0..<14).map { 7 * pow(1.27, Float($0)) }

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let well: Float = 40 + 70 * easeInOut(p)
            func height(_ r: Float) -> Float { -well * pow(16 / (r + 8), 1.25) }
            func twist(_ r: Float) -> Float { t * 0.55 * (20 / (r + 10)) }

            let camera = WireCamera.orbit(around: Vec3(0, -45, 0), distance: 250 - 70 * easeInOut(p),
                                          yaw: 0.4 + t * 0.06, elevation: 0.62 - 0.18 * p, fov: 60)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.7)
            canvas.settings.fogNear = 160
            canvas.settings.fogFar = 620

            let hole = Vec3(0, height(7) - 10, 0)
            canvas.settings.depthSplit = canvas.depth(of: hole)

            // Funnel rings, each turning faster the deeper it sits.
            for (i, r) in ringRadii.enumerated() {
                let k = Float(i) / Float(ringRadii.count - 1)
                let y = height(r)
                let points = (0...40).map { s -> Vec3 in
                    let a = Float(s) / 40 * 2 * .pi + twist(r)
                    return Vec3(cos(a) * r, y, sin(a) * r)
                }
                canvas.polyline(points, color: StoryPalette.mix(StoryPalette.violet, StoryPalette.cyan, k),
                                alpha: 0.75 - 0.4 * k, width: 1.2)
            }
            // Spokes, swept into spirals by the same twist.
            for s in 0..<28 {
                let a0 = Float(s) / 28 * 2 * .pi
                let points = ringRadii.map { r -> Vec3 in
                    let a = a0 + twist(r)
                    return Vec3(cos(a) * r, height(r), sin(a) * r)
                }
                canvas.polyline(points, color: StoryPalette.violet, alpha: 0.5, width: 1.1)
            }

            // Lensing halo behind the hole, the hole itself, then the disc around it.
            let toCamera = simd_normalize(camera.position - hole)
            canvas.glow(hole - toCamera * 4, radius: 70, color: StoryPalette.violet, alpha: 0.45)
            canvas.disc(hole, radius: 7.5)
            let tilt = rotation(0.22, Vec3(1, 0, 0.4))
            let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 0, 1))
            for ring in 0..<6 {
                let radius: Float = 10 + Float(ring) * 3
                let speed: Float = 3.2 / (radius / 10)
                StoryScenery.dashedRing(canvas, center: hole, radius: radius, u: u, v: v, phase: t * speed,
                                        dashes: 7 + ring, fill: 0.6,
                                        color: StoryPalette.mix(StoryPalette.sun, StoryPalette.ember, Float(ring) / 5),
                                        alpha: 0.95, width: 1.5)
            }
            let (pu, pv) = StoryScenery.basis(toCamera)
            canvas.polyline(StoryScenery.circle(center: hole, radius: 8.2, u: pu, v: pv, segments: 36),
                            color: StoryPalette.white, alpha: 0.9, width: 1.6)

            // Stars spiralling in, stretched into streaks as they fall.
            for star in infall {
                func position(_ u: Float) -> Vec3 {
                    let r = 8 + star.r0 * pow(1 - u, 1.6)
                    let a = star.a0 + 7 * pow(u, 1.5) + twist(r)
                    return Vec3(cos(a) * r, height(r) + 3, sin(a) * r)
                }
                let u = (t * star.speed + star.phase).truncatingRemainder(dividingBy: 1)
                let fade = smooth(0, 0.1, u) * (1 - smooth(0.85, 1, u))
                let trail = (0..<6).map { position(max(0, u - Float($0) * 0.012)) }
                canvas.polyline(trail, color: StoryPalette.sun, alpha: fade * 0.7, width: 1.2)
                canvas.dot(trail[0], size: 7, color: StoryPalette.white, alpha: fade)
            }
            f.shake(smooth(0.75, 1, p) * 1.5)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.minDuration = 9
        return shot
    }

    // MARK: - 3. Quantum bleed

    private static let tesseractEdges: [(Int, Int)] = {
        var edges: [(Int, Int)] = []
        for i in 0..<16 { for bit in [1, 2, 4, 8] where i & bit == 0 { edges.append((i, i | bit)) } }
        return edges
    }()

    /// A hypercube turning through the fourth dimension, projected down to three.
    ///
    /// - Parameters:
    ///   - time: Drives the 4D rotation; pass a warped clock for "time flows chaotically".
    ///   - shatter: 0 whole, 1 every edge flung outwards.
    ///   - split: Chromatic split in points — the copies that sell "dimensions overlap".
    static func tesseract(_ canvas: WireCanvas, time: Float, at center: Vec3, scale: Float,
                          spin: simd_quatf, shatter: Float = 0, split: Float = 0, alpha: Float = 1) {
        let a = time * 0.55, b = time * 0.37, c = time * 0.23
        var points: [Vec3] = []
        var depth4: [Float] = []
        points.reserveCapacity(16)
        for i in 0..<16 {
            var x: Float = i & 1 == 0 ? -1 : 1
            var y: Float = i & 2 == 0 ? -1 : 1
            var z: Float = i & 4 == 0 ? -1 : 1
            var w: Float = i & 8 == 0 ? -1 : 1
            (x, w) = (x * cos(a) - w * sin(a), x * sin(a) + w * cos(a))
            (z, w) = (z * cos(b) - w * sin(b), z * sin(b) + w * cos(b))
            (y, w) = (y * cos(c) - w * sin(c), y * sin(c) + w * cos(c))
            let k = 3.2 / (3.2 - w)
            points.append(center + spin.act(Vec3(x, y, z) * k * scale))
            depth4.append(w)
        }

        func draw(_ offset: CGPoint, tint: UIColor?, strength: Float) {
            canvas.settings.offset = offset
            canvas.applyOffset()
            for (index, (i, j)) in tesseractEdges.enumerated() {
                var pa = points[i], pb = points[j]
                if shatter > 0 {
                    let mid = (pa + pb) * 0.5
                    let out = simd_normalize(mid - center + Vec3(0.01, 0.02, 0.03))
                    let spinOut = rotation(shatter * Float(index % 5 + 1) * 0.9, out)
                    let push = out * shatter * scale * (1.2 + 0.3 * Float(index % 7))
                    pa = mid + push + spinOut.act((pa - mid) * (1 - shatter * 0.4))
                    pb = mid + push + spinOut.act((pb - mid) * (1 - shatter * 0.4))
                }
                let w = (depth4[i] + depth4[j]) * 0.25 + 0.5
                let color = tint ?? StoryPalette.mix(StoryPalette.violet, StoryPalette.ice, w)
                canvas.line(pa, pb, color: color, alpha: alpha * strength * (1 - shatter * 0.6), width: 1.7)
            }
        }
        if split > 0.3 {
            draw(CGPoint(x: CGFloat(split), y: 0), tint: StoryPalette.magenta, strength: 0.55)
            draw(CGPoint(x: -CGFloat(split), y: CGFloat(split) * 0.3), tint: StoryPalette.cyan, strength: 0.55)
        }
        draw(.zero, tint: nil, strength: 1)
        for (i, point) in points.enumerated() where shatter < 0.5 {
            canvas.dot(point, size: 5 + 3 * (depth4[i] + 1), color: StoryPalette.white, alpha: alpha * (1 - shatter * 2))
        }
    }

    /// Dimensions overlapping: a tesseract, intersecting grids of other spaces, a
    /// clock face whose hand cannot decide which way time runs.
    static func quantumBleed(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 200, seed: 31)
        var rng = StoryRandom(seed: 32)
        let cloud = (0..<90).map { _ in
            (pos: rng.direction() * rng.float(60...150), freq: rng.float(1.5...4), phase: rng.float(0...6.3))
        }
        let dial = WireMesh.ring(radius: 125, segments: 72, ticks: 60, tickLength: 6)
        let planeAxes: [(Vec3, UIColor)] = [
            (Vec3(1, 0.3, 0), StoryPalette.cyan), (Vec3(0, 1, 0.5), StoryPalette.violet), (Vec3(0.4, 0, 1), StoryPalette.magenta)
        ]
        let glitchPeriod: Float = 2.2

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            // Time runs, then stutters backwards for a quarter second, every couple of beats.
            let cycle = (t / glitchPeriod).rounded(.down)
            let local = t - cycle * glitchPeriod
            let glitching = t > 1 && local < 0.28
            let clock: Float = glitching ? cycle * glitchPeriod - local * 2.5 : t + 0.4 * sin(t * 0.8)
            if t > 1 && f.crossed(cycle * glitchPeriod) { f.cue(.haptic(.tick)) }

            let camera = WireCamera.orbit(around: Vec3(sin(t * 0.4) * 3, cos(t * 0.33) * 3, 0), distance: 270,
                                          yaw: t * 0.09, elevation: 0.25 + 0.1 * sin(t * 0.3), fov: 58)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.6)
            canvas.settings.fogNear = 200
            canvas.settings.fogFar = 520

            // Grids of other spaces cutting through this one.
            for (i, (axis, color)) in planeAxes.enumerated() {
                let q = rotation(t * 0.12 + Float(i) * 1.1, axis)
                let size: Float = 150
                for k in 0...10 {
                    let o = -size + Float(k) * size / 5
                    canvas.line(q.act(Vec3(o, 0, -size)), q.act(Vec3(o, 0, size)), color: color, alpha: 0.2, width: 1)
                    canvas.line(q.act(Vec3(-size, 0, o)), q.act(Vec3(size, 0, o)), color: color, alpha: 0.2, width: 1)
                }
            }

            // The clock face.
            canvas.mesh(dial, rotation: rotation(clock * 0.5, Vec3(0, 1, 0)) * rotation(.pi / 2 - 0.3, Vec3(1, 0, 0)),
                        color: StoryPalette.gold, alpha: 0.45, width: 1.1)
            let hand = rotation(.pi / 2 - 0.3, Vec3(1, 0, 0)).act(Vec3(cos(clock * 1.7), 0, sin(clock * 1.7)) * 110)
            canvas.line(.zero, hand, color: StoryPalette.gold, alpha: 0.8, width: 1.6)

            let split: Float = glitching ? 9 : 2 + 1.5 * sin(t * 3)
            tesseract(canvas, time: clock + 1.1, at: .zero, scale: 42, spin: rotation(yaw: t * 0.2, pitch: 0.35),
                      split: split)
            canvas.settings.offset = .zero
            canvas.applyOffset()

            // Particles that are, and then are not.
            for c in cloud {
                let blink = pow(max(0, sin(t * c.freq + c.phase)), 6)
                canvas.dot(c.pos, size: 5, color: StoryPalette.ice, alpha: blink)
            }
            if glitching { f.shake(3) }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.minDuration = 9
        return shot
    }

    // MARK: - 4. Singularity-7

    /// The ship on a holographic turntable, drawn in by a scan line, then named.
    static func shipReveal(_ text: String, name: String) -> StoryShot {
        let stars = StoryStarfield(count: 180, seed: 41)
        let pad = WireMesh.ring(radius: 26, segments: 64, ticks: 36, tickLength: 2.5)
        let padInner = WireMesh.ring(radius: 21, segments: 48)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: Vec3(0, 1, 0), distance: 72 - 16 * easeInOut(p),
                                          yaw: -0.5 + t * 0.05, elevation: 0.3 - 0.1 * p, fov: 56)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.55)
            canvas.settings.fogNear = 60
            canvas.settings.fogFar = 260
            canvas.settings.widthReference = 70

            let spin = rotation(yaw: 0.9 + t * 0.32, pitch: 0.12)
            let scan = lerp(-22, 24, easeInOut(f.ramp(0.3, 3.0)))
            let scanning = 1 - f.ramp(2.8, 3.4)

            // Turntable below, beams up to the hull.
            canvas.mesh(pad, at: Vec3(0, -10, 0), rotation: rotation(t * 0.4, Vec3(0, 1, 0)),
                        color: StoryPalette.cyan, alpha: 0.45, width: 1.1)
            canvas.mesh(padInner, at: Vec3(0, -10, 0), rotation: rotation(-t * 0.6, Vec3(0, 1, 0)),
                        color: StoryPalette.blue, alpha: 0.5, width: 1)
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi + t * 0.4
                canvas.line(Vec3(cos(a) * 26, -10, sin(a) * 26), Vec3(cos(a) * 9, -2, sin(a) * 9),
                            color: StoryPalette.cyan, alpha: 0.14, width: 1)
            }
            canvas.glow(Vec3(0, -10, 0), radius: 34, color: StoryPalette.cyan, alpha: 0.2)

            StoryScenery.ship(canvas, at: .zero, rotation: spin, color: StoryPalette.ice, alpha: 1,
                              engine: 0.45 * f.ramp(3.0, 3.8), t: t, width: 1.6) { a, b in
                clamp01((scan - max(a.z, b.z)) / 2)
            }
            if scanning > 0.01 {
                // The scan ring wraps the hull at the scan line.
                let ring = (0...40).map { s -> Vec3 in
                    let a = Float(s) / 40 * 2 * .pi
                    return spin.act(Vec3(cos(a) * 14, sin(a) * 5, scan))
                }
                canvas.polyline(ring, color: StoryPalette.cyan, alpha: scanning, width: 2)
                canvas.glow(spin.act(Vec3(0, 0, scan)), radius: 18, color: StoryPalette.cyan, alpha: scanning * 0.3)
            }

            // Name it: a lock-on and a typed tag tied back to the nose.
            let tagIn = f.ramp(3.2, 3.6)
            if tagIn > 0, let nose = canvas.project(spin.act(Vec3(0, 0.5, -18))),
               let centre = canvas.project(.zero) {
                let frame = f.overlay.frame
                let size = canvas.screenSize(of: 26, at: .zero)
                let lockIn = CGFloat(tagIn)
                f.overlay.bracket(around: centre, halfWidth: size * (1.4 - 0.25 * lockIn), halfHeight: size * (1.0 - 0.15 * lockIn),
                                  arm: 12, color: StoryPalette.cyan, alpha: tagIn * 0.8)
                let anchor = CGPoint(x: frame.minX + 26, y: frame.maxY - 46)
                let elbow = CGPoint(x: anchor.x + 150 * f.overlay.typeScale, y: anchor.y - 14)
                let draw = f.ramp(3.2, 3.9)
                canvas.line2D(CGPoint(x: anchor.x, y: anchor.y - 14), elbow, color: StoryPalette.cyan, alpha: draw * 0.7)
                canvas.line2D(elbow, lerpPoint(elbow, nose, draw), color: StoryPalette.cyan, alpha: draw * 0.7)
                canvas.glow2D(nose, size: 14, color: StoryPalette.white, alpha: draw)
                f.overlay.tag("name", name, at: anchor, size: 17, color: StoryPalette.ice,
                              reveal: f.ramp(3.5, 4.6), alpha: tagIn, tracking: 4, blink: t)
            }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 2.6
        shot.minDuration = 10
        return shot
    }

    private static func lerpPoint(_ a: CGPoint, _ b: CGPoint, _ t: Float) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }

    // MARK: - 5. Escape

    /// Engines light, the ship tears out through a line of launch gates.
    static func ignition(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 200, seed: 51)
        let gate = WireMesh.ring(radius: 30, segments: 8, ticks: 8, tickLength: 5)
        let launchAt: Float = 1.7

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let run = max(0, t - launchAt)
            let travelled: Float = 46 * pow(run, 2.2)
            let speed: Float = run > 0 ? 46 * 2.2 * pow(run, 1.2) : 0
            let shipPos = Vec3(0, 0, -travelled)
            let lag: Float = travelled * 0.16
            let camera = WireCamera(position: Vec3(sin(t * 0.5) * 3, 11 + lag * 0.02, 48 - travelled + lag),
                                    target: shipPos + Vec3(0, 2, -60), roll: sin(t * 0.7) * 0.03, fov: 60)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.75)
            canvas.settings.fogNear = 120
            canvas.settings.fogFar = 900

            // Launch gates, each flaring gold as the ship goes through it.
            for k in 1...14 {
                let z = -Float(k) * 80
                let passed = clamp01((-z - travelled) / -40 + 1)
                let color = StoryPalette.mix(StoryPalette.cyan, StoryPalette.gold, passed)
                canvas.mesh(gate, at: Vec3(0, 0, z), rotation: rotation(.pi / 2, Vec3(1, 0, 0)) * rotation(Float(k) * 0.2, Vec3(0, 1, 0)),
                            color: color, alpha: 0.55 + 0.45 * passed, width: 1.4)
            }

            if speed > 30 {
                StoryScenery.warp(canvas, around: camera.position, t: t, speed: speed, count: 110, radius: 140,
                                  depth: 900, seed: 52, alpha: smooth(30, 200, speed), travelled: travelled)
            }

            let engine = 0.35 + 0.65 * f.ramp(0.3, launchAt) + min(1, speed / 400)
            StoryScenery.ship(canvas, at: shipPos, rotation: rotation(sin(t * 1.3) * 0.05, Vec3(0, 0, 1)),
                              color: StoryPalette.ice, engine: engine, t: t, width: 1.6)

            // The kick: a ring of thrust left hanging where the ship was.
            if run > 0 {
                let e = easeOut(run / 1.2)
                let (u, v) = StoryScenery.basis(Vec3(0, 0, 1))
                canvas.polyline(StoryScenery.circle(center: Vec3(0, 0, 20), radius: 6 + 60 * e, u: u, v: v, segments: 40),
                                color: StoryPalette.cyan, alpha: 1 - e, width: 2)
            }
            if f.crossed(launchAt) {
                f.cue(.flash(0.3))
                f.cue(.shake(5, 0.6))
                f.cue(.haptic(.heavy))
            }
            f.shake(run > 0 ? 1.4 : f.ramp(0.3, launchAt) * 0.8)
        })
        shot.lines = [StoryLine(text: text, style: .cardHigh)]
        shot.lead = 2.0
        shot.tail = 0.6
        shot.minDuration = 6.5
        shot.cues = [(0.02, .sound(.ignition))]
        return shot
    }

    // MARK: - 6. Through the rifts

    private static func tunnelCentre(_ s: Float) -> Vec3 {
        Vec3(70 * sin(s * 0.0045), 40 * sin(s * 0.0031 + 1.2), -s)
    }

    /// A run down a twisting dimensional tunnel, scooping up energy, into a rift.
    static func riftRun(_ text: String) -> StoryShot {
        let orb = WireMesh.geodesic(radius: 3.5, subdivisions: 0)
        let speed: Float = 160
        var rng = StoryRandom(seed: 61)
        let orbs = (0..<40).map { j in
            (s: 150 + Float(j) * 90, offset: SIMD2<Float>(rng.float(-14...14), rng.float(-9...9)))
        }
        let sparkDirections = (0..<10).map { _ in rng.direction() }

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let sCam = t * speed
            let sShip = sCam + 42
            let riftS = f.duration * speed + 70

            let ahead = tunnelCentre(sCam + 90)
            let bank = (tunnelCentre(sCam + 60).x - tunnelCentre(sCam).x) * -0.012
            let camera = WireCamera(position: tunnelCentre(sCam) + Vec3(0, 6, 0), target: ahead,
                                    roll: bank, fov: 66)
            f.look(camera)
            canvas.settings.fogNear = 140
            canvas.settings.fogFar = 640

            // Rings and the struts between them.
            let first = Int((sCam / 30).rounded(.down))
            var previous: [Vec3] = []
            for k in first...(first + 22) {
                let s = Float(k) * 30
                if s > riftS - 20 { break }
                let centre = tunnelCentre(s)
                let tangent = simd_normalize(tunnelCentre(s + 1) - centre)
                let (u, v) = StoryScenery.basis(tangent)
                let twist = Float(k) * 0.15 + t * 0.4
                let ring = (0..<6).map { i -> Vec3 in
                    let a = Float(i) / 6 * 2 * .pi + twist
                    return centre + (u * cos(a) + v * sin(a)) * 36
                }
                let gold = k % 6 == 0
                let color = gold ? StoryPalette.gold : (k % 2 == 0 ? StoryPalette.cyan : StoryPalette.violet)
                canvas.polyline(ring, closed: true, color: color, alpha: gold ? 1 : 0.7, width: gold ? 2 : 1.4)
                if previous.count == 6 {
                    for i in 0..<6 { canvas.line(previous[i], ring[i], color: StoryPalette.blue, alpha: 0.35, width: 1) }
                }
                previous = ring
            }

            // Energy along the way, burst into sparks as the ship takes it.
            for (j, o) in orbs.enumerated() where o.s > sCam && o.s < sCam + 600 && o.s < riftS - 60 {
                let centre = tunnelCentre(o.s)
                let (u, v) = StoryScenery.basis(simd_normalize(tunnelCentre(o.s + 1) - centre))
                let pos = centre + u * o.offset.x + v * o.offset.y
                let taken = sShip - o.s
                if taken < 0 {
                    canvas.mesh(orb, at: pos, rotation: rotation(t * 3 + Float(j), Vec3(1, 1, 0)),
                                color: StoryPalette.gold, alpha: 1, width: 1.5)
                    canvas.glow(pos, radius: 9, color: StoryPalette.gold, alpha: 0.6)
                } else if taken < 60 {
                    let e = taken / 60
                    for d in sparkDirections {
                        canvas.line(pos + d * (2 + 14 * e), pos + d * (4 + 26 * e), color: StoryPalette.sun, alpha: 1 - e, width: 1.3)
                    }
                    canvas.glow(pos, radius: 6 + 20 * e, color: StoryPalette.gold, alpha: (1 - e) * 0.7)
                }
                if f.crossed(o.s / speed - 42 / speed) { f.cue(.haptic(.tick)) }
            }

            // The rift: a torn, flickering wound in space at the end of the tunnel.
            let riftCentre = tunnelCentre(riftS)
            let open = f.pramp(0.55, 0.95)
            if open > 0 {
                let (u, v) = StoryScenery.basis(Vec3(0, 0, 1))
                for layer in 0..<4 {
                    var r = StoryRandom(seed: 63 + UInt64(layer) &+ UInt64(t * 14))
                    let points = (0..<26).map { i -> Vec3 in
                        let a = Float(i) / 26 * 2 * .pi
                        let radius = (10 + 70 * open) * (1 - Float(layer) * 0.18) * (0.75 + 0.5 * r.unit())
                        return riftCentre + (u * cos(a) * 0.55 + v * sin(a) * 1.4) * radius
                    }
                    canvas.polyline(points, closed: true, color: layer == 0 ? StoryPalette.white : StoryPalette.violet,
                                    alpha: open, width: 1.8)
                }
                canvas.glow(riftCentre, radius: 30 + 120 * open, color: StoryPalette.violet, alpha: open * 0.8)
                canvas.glow(riftCentre, radius: 12 + 50 * open, color: StoryPalette.white, alpha: open)
            }

            // The ship, banking with the tunnel.
            let shipCentre = tunnelCentre(sShip) + Vec3(0, -4, 0)
            let heading = simd_normalize(tunnelCentre(sShip + 1) - tunnelCentre(sShip))
            let turn = (tunnelCentre(sShip + 30).x - tunnelCentre(sShip).x) * -0.02
            let q = rotation(turn, heading) * simd_quatf(from: Vec3(0, 0, -1), to: heading)
            StoryScenery.ship(canvas, at: shipCentre, rotation: q, scale: 0.55, color: StoryPalette.ice, engine: 1, t: t, width: 1.4)
            f.shake(0.8 + 2 * open)
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.minDuration = 9
        shot.cues = [(0.82, .sound(.rift))]
        return shot
    }

    // MARK: - 7. The epicentre

    /// The heart of the collapse: nested geodesic shells, gyroscope rings, a core
    /// of white light spitting lightning, and the dying universe pouring into it.
    static func epicentreStructure(_ canvas: WireCanvas, t: Float, at centre: Vec3, scale: Float = 1,
                                   alpha: Float = 1, inflow: Float = 1, calm: Float = 0) {
        canvas.mesh(epicentreOuter, at: centre, rotation: rotation(t * 0.05, Vec3(0.3, 1, 0)), scale: scale,
                    color: StoryPalette.violet, alpha: alpha * 0.4, width: 1.2, backAlpha: 0.35)
        canvas.mesh(epicentreInner, at: centre, rotation: rotation(-t * 0.12, Vec3(1, 0.4, 0.2)), scale: scale,
                    color: StoryPalette.gold, alpha: alpha * 0.7, width: 1.4, backAlpha: 0.4)
        let axes = [Vec3(1, 0.2, 0), Vec3(0, 1, 0.3), Vec3(0.3, 0.1, 1)]
        for (i, axis) in axes.enumerated() {
            let q = rotation(t * (0.3 + Float(i) * 0.17) * (1 - calm), axis)
            let (u, v) = StoryScenery.basis(q.act(simd_normalize(axis)))
            StoryScenery.dashedRing(canvas, center: centre, radius: (200 + Float(i) * 25) * scale, u: u, v: v,
                                    phase: t * 0.4, dashes: 12, fill: 0.78,
                                    color: i == 1 ? StoryPalette.gold : StoryPalette.cyan, alpha: alpha * 0.75, width: 1.5)
        }
        let pulse: Float = 1 + 0.12 * sin(t * 5)
        canvas.glow(centre, radius: 150 * scale, color: StoryPalette.violet, alpha: alpha * 0.35)
        canvas.glow(centre, radius: 60 * scale * pulse, color: StoryPalette.gold, alpha: alpha * 0.55)
        canvas.glow(centre, radius: 22 * scale * pulse, color: StoryPalette.white, alpha: alpha)
        canvas.flare(centre, length: Float(canvas.viewport.width) * 0.9 * alpha, thickness: 10,
                     color: StoryPalette.sun, alpha: alpha * 0.5)

        var rng = StoryRandom(seed: 71)
        for bolt in 0..<5 {
            let target = epicentreInner.vertices[Int(rng.next() % UInt64(epicentreInner.vertices.count))]
            let twitch = rotation(Float(bolt) + t * 0.9, Vec3(0.2, 1, 0.4))
            StoryScenery.lightning(canvas, from: centre, to: centre + twitch.act(target) * scale, t: t,
                                   seed: 700 + UInt64(bolt), jitter: 9 * scale,
                                   color: StoryPalette.violet, alpha: alpha * (1 - calm) * 0.9)
        }

        guard inflow > 0 else { return }
        for i in 0..<120 {
            var r = StoryRandom(seed: 7_000 + UInt64(i))
            let dir = r.direction()
            let u = (t * r.float(0.08...0.16) + r.unit()).truncatingRemainder(dividingBy: 1)
            let distance = 620 * pow(1 - u, 1.3) * scale
            let fade = smooth(0, 0.15, u) * (1 - smooth(0.9, 1, u))
            canvas.dot(centre + dir * distance, size: 4, color: StoryPalette.ice, alpha: fade * inflow * alpha)
        }
    }

    private static let epicentreOuter = WireMesh.geodesic(radius: 150, subdivisions: 2)
    private static let epicentreInner = WireMesh.geodesic(radius: 80, subdivisions: 1)

    static func epicenter(_ text: String, protocolName: String) -> StoryShot {
        let stars = StoryStarfield(count: 220, seed: 72)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let camera = WireCamera.orbit(around: .zero, distance: 920 - 450 * easeInOut(p),
                                          yaw: 0.3 + t * 0.03, elevation: 0.14, fov: 56)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.6)
            canvas.settings.fogNear = 900
            canvas.settings.fogFar = 2400
            canvas.settings.widthReference = 700
            epicentreStructure(canvas, t: t, at: .zero)

            // Lock on and name the protocol.
            let lock = f.ramp(1.0, 2.2)
            if lock > 0, let core = canvas.project(.zero) {
                let half = CGFloat(170 - 120 * easeOut(lock))
                f.overlay.bracket(around: core, halfWidth: half, halfHeight: half, arm: 14,
                                  color: StoryPalette.gold, alpha: lock)
                f.overlay.tag("protocol", protocolName, at: CGPoint(x: core.x, y: core.y - half - 22),
                              size: 13, color: StoryPalette.gold, reveal: f.ramp(2.0, 3.6), alpha: lock,
                              align: .center, tracking: 3, blink: t)
            }
            if f.crossed(1.0) { f.cue(.haptic(.light)) }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 1.6
        shot.minDuration = 10
        shot.cues = [(0.1, .sound(.arc))]
        return shot
    }

    // MARK: - 8. What guards the way

    enum EntityKind { case spiked, crystal, cage, sentinel }

    private static let spikedMesh = WireMesh.spiked(radius: 11, spike: 2.0)
    private static let crystalMesh = WireMesh.octahedron(radius: 16)
    private static let cageMesh = WireMesh.box(Vec3(9, 9, 9))
    private static let sentinelMesh = WireMesh.ring(radius: 16, segments: 6, ticks: 6, tickLength: 9)
    private static let ancientMesh = WireMesh.spiked(radius: 230, spike: 1.45)

    /// A hostile quantum entity. `shatter` blows it apart edge by edge.
    static func entity(_ canvas: WireCanvas, kind: EntityKind, at position: Vec3, t: Float, alpha: Float,
                       scale: Float = 1, shatter: Float = 0, seed: Int = 0) {
        let spin = rotation(t * (0.6 + Float(seed % 3) * 0.25), Vec3(0.3, 1, Float(seed % 2) * 0.5))
        let color = seed % 2 == 0 ? StoryPalette.red : StoryPalette.magenta
        let mesh: WireMesh
        switch kind {
        case .spiked: mesh = spikedMesh
        case .crystal: mesh = crystalMesh
        case .cage: mesh = cageMesh
        case .sentinel: mesh = sentinelMesh
        }
        if shatter > 0 {
            let e = easeOut(shatter)
            for (index, (i, j)) in mesh.edges.enumerated() {
                let a = spin.act(mesh.vertices[i] * scale), b = spin.act(mesh.vertices[j] * scale)
                let mid = (a + b) * 0.5
                let out = simd_normalize(mid + Vec3(0.01, 0.01, 0.01)) * e * 34 * scale
                let twist = rotation(e * Float(index % 4 + 1), simd_normalize(mid + Vec3(0, 0.01, 0)))
                canvas.line(position + mid + out + twist.act(a - mid), position + mid + out + twist.act(b - mid),
                            color: color, alpha: alpha * (1 - e), width: 1.4)
            }
            canvas.glow(position, radius: (10 + 60 * e) * scale, color: StoryPalette.white, alpha: alpha * (1 - e))
            return
        }
        canvas.mesh(mesh, at: position, rotation: spin, scale: scale, color: color, alpha: alpha, width: 1.5, backAlpha: 0.4)
        if kind == .cage {
            canvas.mesh(crystalMesh, at: position, rotation: spin.inverse, scale: scale * 0.6, color: StoryPalette.ember,
                        alpha: alpha, width: 1.2)
        }
        let eye: Float = 0.6 + 0.4 * sin(t * 4 + Float(seed))
        canvas.glow(position, radius: 6 * scale * eye, color: StoryPalette.red, alpha: alpha)
        canvas.glow(position, radius: 2 * scale, color: StoryPalette.white, alpha: alpha * eye)
    }

    static func entities(_ text: String) -> StoryShot {
        let stars = StoryStarfield(count: 160, seed: 81)
        var rng = StoryRandom(seed: 82)
        let kinds: [EntityKind] = [.spiked, .crystal, .cage, .spiked, .sentinel, .crystal, .spiked, .cage, .sentinel]
        // A chevron, point towards the camera, low in the frame so the ancient one
        // towers over it.
        let swarm = kinds.enumerated().map { i, kind in
            let rank = Float(i) - Float(kinds.count - 1) / 2
            return (kind: kind, home: Vec3(rank * 25, -22 + abs(rank) * 9, 70 - abs(rank) * 24), seed: i)
        }
        let cracks: [[SIMD2<Float>]] = (0..<12).map { _ in
            var point = SIMD2<Float>(rng.unit(), rng.unit())
            var path = [point]
            let heading = rng.float(0...(2 * .pi))
            for _ in 0..<6 {
                let a = heading + rng.float(-0.8...0.8)
                point += SIMD2(cos(a), sin(a)) * rng.float(0.04...0.1)
                path.append(point)
            }
            return path
        }

        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let (phase, local) = f.phase(line: 0, count: 4)
            let emergeStart = f.phaseStarts(line: 0, count: 4)[1]
            let camera = WireCamera(position: Vec3(sin(t * 0.2) * 14, 6 + 4 * sin(t * 0.13), 230 + t * 4),
                                    target: Vec3(0, 70, -100), roll: sin(t * 0.17) * 0.04, fov: 62)
            f.look(camera)
            canvas.settings.fogNear = 260
            canvas.settings.fogFar = 900
            canvas.settings.widthReference = 200
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.35)

            // The ancient one, behind everything, opening its eye. Too far for the fog
            // the swarm is drawn in.
            canvas.settings.fogNear = 3000
            canvas.settings.fogFar = 6000
            let ancient = Vec3(0, 260, -720)
            let wake = phase == 0 ? local * 0.3 : 0.3 + 0.7 * (phase == 1 ? local : 1)
            canvas.mesh(ancientMesh, at: ancient, rotation: rotation(t * 0.04, Vec3(0.2, 1, 0)),
                        color: StoryPalette.red, alpha: 0.35 + 0.5 * wake, width: 1.5, backAlpha: 0.25)
            let eye: Float = 0.6 + 0.4 * sin(t * 2.2)
            canvas.glow(ancient, radius: 130 * wake * eye + 30, color: StoryPalette.red, alpha: 0.4 + 0.5 * wake)
            canvas.glow(ancient, radius: 30 * wake, color: StoryPalette.white, alpha: wake)
            let (iu, iv) = StoryScenery.basis(camera.position - ancient)
            StoryScenery.dashedRing(canvas, center: ancient, radius: 110 + 60 * wake, u: iu, v: iv, phase: t * 0.8,
                                    dashes: 9, fill: 0.5, color: StoryPalette.ember, alpha: wake, width: 1.6)

            canvas.settings.fogNear = 260
            canvas.settings.fogFar = 900

            // The vortex: anomalies that swallow.
            let vortex = phase >= 2 ? (phase == 2 ? local : 1) : 0
            if vortex > 0 {
                canvas.settings.fogFar = 1600
                let centre = Vec3(-40, 70, -320)
                let tilt = rotation(-0.35, Vec3(1, 0, 0))
                let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 0, 1))
                for arm in 0..<5 {
                    let points = (0..<36).map { k -> Vec3 in
                        let r = 9 * exp(0.1 * Float(k)) * vortex
                        let a = Float(arm) / 5 * 2 * .pi + Float(k) * 0.17 - t * 1.4
                        return centre + (u * cos(a) + v * sin(a)) * r
                    }
                    canvas.polyline(points, color: arm % 2 == 0 ? StoryPalette.violet : StoryPalette.magenta,
                                    alpha: vortex * 0.75, width: 1.5)
                }
                canvas.glow(centre, radius: 80 * vortex, color: StoryPalette.violet, alpha: vortex * 0.6)
                canvas.settings.fogFar = 900
            }

            // The swarm, rising out of the dark one after another.
            let glitch: Float = phase == 3 ? local : 0
            for e in swarm {
                let appear = smooth(emergeStart + Float(e.seed) * 0.45, emergeStart + Float(e.seed) * 0.45 + 1.6, t)
                guard appear > 0 else { continue }
                let from = e.home + Vec3(0, -40, -400)
                var pos = lerp(from, e.home, easeOut(appear)) + Vec3(0, sin(t + Float(e.seed)) * 4, 0)
                if vortex > 0 { pos += simd_normalize(Vec3(-40, 70, -320) - pos) * vortex * 12 }
                if glitch > 0 {
                    canvas.settings.offset = CGPoint(x: CGFloat(sin(t * 53 + Float(e.seed)) * 8 * glitch), y: 0)
                    canvas.applyOffset()
                }
                entity(canvas, kind: e.kind, at: pos, t: t, alpha: appear, scale: 1.5, seed: e.seed)
            }
            canvas.settings.offset = .zero
            canvas.applyOffset()

            // Reality resists: the picture cracks.
            if glitch > 0 {
                let frame = canvas.viewport
                for (i, crack) in cracks.enumerated() where Float(i) / Float(cracks.count) < glitch * 1.4 {
                    let flickerOn = sin(t * 30 + Float(i) * 1.7) > -0.3
                    guard flickerOn else { continue }
                    for k in 1..<crack.count {
                        let a = CGPoint(x: frame.minX + CGFloat(crack[k - 1].x) * frame.width, y: frame.minY + CGFloat(crack[k - 1].y) * frame.height)
                        let b = CGPoint(x: frame.minX + CGFloat(crack[k].x) * frame.width, y: frame.minY + CGFloat(crack[k].y) * frame.height)
                        canvas.line2D(a, b, color: i % 2 == 0 ? StoryPalette.white : StoryPalette.magenta, alpha: 0.8, width: 1.4)
                    }
                }
                f.shake(1 + 4 * glitch)
            }
            if f.crossed(emergeStart) {
                f.cue(.sound(.entities))
                f.cue(.haptic(.medium))
            }
        })
        shot.lines = [StoryLine(text: text, style: .subtitle)]
        shot.lead = 1.4
        shot.minDuration = 12
        return shot
    }

    // MARK: - 9. The plunge

    static func singularity(_ canvas: WireCanvas, at centre: Vec3, t: Float, scale: Float, alpha: Float = 1) {
        let tilt = rotation(0.35, Vec3(1, 0, 0.2))
        let u = tilt.act(Vec3(1, 0, 0)), v = tilt.act(Vec3(0, 0, 1))
        for ring in 0..<5 {
            let radius = (140 + Float(ring) * 45) * scale
            StoryScenery.dashedRing(canvas, center: centre, radius: radius, u: u, v: v,
                                    phase: t * (1.6 - Float(ring) * 0.22), dashes: 10 + ring * 2, fill: 0.55,
                                    color: StoryPalette.mix(StoryPalette.sun, StoryPalette.violet, Float(ring) / 4),
                                    alpha: alpha * 0.9, width: 1.8)
        }
        let pulse: Float = 1 + 0.15 * sin(t * 6)
        canvas.glow(centre, radius: 420 * scale, color: StoryPalette.violet, alpha: alpha * 0.4)
        canvas.glow(centre, radius: 140 * scale * pulse, color: StoryPalette.sun, alpha: alpha * 0.7)
        canvas.glow(centre, radius: 50 * scale * pulse, color: StoryPalette.white, alpha: alpha)
        canvas.flare(centre, length: Float(canvas.viewport.width) * 1.5, thickness: 16, color: StoryPalette.sun, alpha: alpha * 0.6)
        for ray in 0..<16 {
            let a = Float(ray) / 16 * 2 * .pi + t * 0.2
            let dir = u * cos(a) + v * sin(a)
            canvas.line(centre + dir * 60 * scale, centre + dir * 600 * scale, color: StoryPalette.sun, alpha: alpha * 0.25, width: 1.2)
        }
    }

    static func plunge(_ noOtherWay: String, _ either: String, _ or: String) -> StoryShot {
        let stars = StoryStarfield(count: 220, seed: 91)

        var shot = StoryShot(render: { f in
            let t = f.t
            let p = f.p
            let canvas = f.canvas
            let distance: Float = 2600 - 2450 * pow(p, 1.6)
            let wobble = rotation(sin(t * 0.9) * 0.12, Vec3(0, 0, 1)) * rotation(sin(t * 0.6) * 0.05, Vec3(1, 0, 0))
            let camera = WireCamera(position: Vec3(sin(t * 0.5) * 4, 9, 42), target: Vec3(0, 3, -80),
                                    roll: sin(t * 0.4) * 0.05, fov: 62 + 10 * p)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.6)
            canvas.settings.fogNear = 600
            canvas.settings.fogFar = 3200
            canvas.settings.widthReference = 300

            canvas.settings.fogNear = 3000
            canvas.settings.fogFar = 6000
            singularity(canvas, at: Vec3(0, 40 * (1 - p), -distance), t: t, scale: 1 + p)

            // Rings of light rushing past, quicker as the pull grows.
            canvas.settings.fogNear = 200
            canvas.settings.fogFar = 900
            let rush: Float = t * 220 + 400 * pow(p, 2) * 4
            for k in 0..<12 {
                var z = (Float(k) * 80 + rush).truncatingRemainder(dividingBy: 960) - 900
                if z > 40 { z -= 960 }
                let (u, v) = StoryScenery.basis(Vec3(0, 0, 1))
                canvas.polyline(StoryScenery.circle(center: Vec3(0, 0, z), radius: 70, u: u, v: v, segments: 24),
                                color: k % 3 == 0 ? StoryPalette.gold : StoryPalette.violet, alpha: 0.6, width: 1.4)
            }
            StoryScenery.warp(canvas, around: camera.position, t: t, speed: 300 + 900 * p, count: 90, radius: 160,
                              depth: 900, seed: 92, color: StoryPalette.sun, alpha: 0.7,
                              travelled: t * 300 + 450 * p * p * 4)
            StoryScenery.ship(canvas, at: Vec3(0, 0, 0), rotation: wobble, color: StoryPalette.ice, engine: 1.4, t: t, width: 1.6)
            f.shake(0.6 + 5 * pow(p, 3))
        })
        shot.lines = [
            StoryLine(text: noOtherWay, style: .cardHigh),
            StoryLine(text: either, style: .subtitle, delay: 0.3),
            StoryLine(text: or, style: .cardHigh, delay: 0.2)
        ]
        shot.lead = 1.2
        shot.tail = 1.0
        shot.minDuration = 12
        shot.cues = [(0.97, .haptic(.heavy)), (0.97, .shake(8, 0.6))]
        return shot
    }

    // MARK: - 10. Title

    /// Out of the white, the name of the game.
    static func logo() -> StoryShot {
        let stars = StoryStarfield(count: 260, seed: 101)
        var shot = StoryShot(render: { f in
            let t = f.t
            let canvas = f.canvas
            let camera = WireCamera(position: Vec3(0, 0, 60 - t * 6), target: Vec3(0, 0, -100), fov: 60)
            f.look(camera)
            stars.draw(canvas, around: camera.position, t: t, alpha: 0.9)
            let reveal = f.ramp(0.2, 1.4)
            let frame = canvas.viewport
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            canvas.glow2D(centre, size: frame.width * 1.2 * CGFloat(reveal), color: StoryPalette.cyan, alpha: 0.18 * reveal)
            canvas.line2D(CGPoint(x: centre.x - frame.width * 0.45 * CGFloat(reveal), y: centre.y),
                          CGPoint(x: centre.x + frame.width * 0.45 * CGFloat(reveal), y: centre.y),
                          color: StoryPalette.cyan, alpha: 0.35 * reveal, width: 1)
            // The game's name is the one word on screen that is never translated.
            f.overlay.title("logo", "JETSHOT", at: CGPoint(x: centre.x, y: centre.y + 4), size: 64,
                            color: UITheme.Colors.primaryCyanLight, glow: StoryPalette.cyan,
                            alpha: reveal * (1 - f.ramp(f.duration - 1.2, f.duration)),
                            scale: CGFloat(1.12 - 0.12 * easeOut(t / f.duration)))
        })
        shot.entry = .flash
        shot.minDuration = 4.2
        return shot
    }
}
