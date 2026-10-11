//
//  StoryShots.swift
//  jetshot
//
//  The vocabulary the story films are written in: shots, the captions laid over
//  them, cues, and the pieces of scenery more than one shot needs.
//

import SpriteKit
import simd

// MARK: - Model

enum StoryBeatStyle {
    /// Huge gold lettering in the middle of the frame — the film's title.
    case title
    /// A caption on the black bar under the picture. Split into sentences, each
    /// shown on its own, so a paragraph never lands as a wall of text.
    case subtitle
    /// A line on its own, large, centred in the frame.
    case card
    /// The same, in the upper part of the frame, clear of action below it.
    case cardHigh
}

/// A paragraph of narration and how to present it.
struct StoryLine {
    let text: String
    let style: StoryBeatStyle
    /// Extra silence before the line.
    var delay: TimeInterval = 0
}

enum StorySound {
    case ignition, rift, entities, bigBang, blast, charge, energy, arc
}

enum StoryHaptic {
    case light, medium, heavy, tick, success
}

enum StoryCue {
    case sound(StorySound)
    case haptic(StoryHaptic)
    /// A white flash over the frame, at this peak alpha.
    case flash(Float)
    /// A camera jolt: amplitude in points, decaying over the duration.
    case shake(Float, TimeInterval)
}

/// One continuous clip of the film.
///
/// A shot is a pure function of time: `render` redraws the whole frame from `t`
/// alone, which is what lets the director cut, skip and (in Debug) start anywhere.
/// Its length is not fixed — it stretches to fit its captions, which are a
/// different length in every language.
struct StoryShot {
    enum Entry {
        /// Through black.
        case fade
        /// Hard cut.
        case cut
        /// Through a white flash.
        case flash
    }

    var entry: Entry = .fade
    var lines: [StoryLine] = []
    /// Picture before the first caption appears.
    var lead: TimeInterval = 1.0
    /// Picture after the last caption has gone.
    var tail: TimeInterval = 0.9
    var minDuration: TimeInterval = 5
    /// One-off cues at a fraction of the shot's length.
    var cues: [(at: Float, cue: StoryCue)] = []
    var render: (ShotFrame) -> Void
}

// MARK: - Timing

/// When each caption of a shot is on screen, and how long the shot runs.
struct ShotTimeline {
    struct Beat {
        let text: String
        let style: StoryBeatStyle
        /// Index into the shot's `lines`.
        let line: Int
        let start: Float
        let end: Float
    }

    let beats: [Beat]
    /// Start and end of every line, all its sentences included.
    let spans: [(start: Float, end: Float)]
    let duration: Float

    init(_ shot: StoryShot) {
        var t = Float(shot.lead)
        var beats: [Beat] = []
        var spans: [(start: Float, end: Float)] = []
        for (index, line) in shot.lines.enumerated() {
            if index > 0 { t += 0.45 }
            t += Float(line.delay)
            let start = t
            let pieces = line.style == .subtitle ? Self.sentences(in: line.text) : [line.text]
            for (n, piece) in pieces.enumerated() {
                if n > 0 { t += 0.2 }
                let length = Self.readingTime(piece, style: line.style)
                beats.append(Beat(text: piece, style: line.style, line: index, start: t, end: t + length))
                t += length
            }
            spans.append((start, t))
        }
        self.beats = beats
        self.spans = spans
        duration = max(Float(shot.minDuration), t + Float(shot.tail))
    }

    /// Seconds a caption stays up. Subtitle pace is a comfortable 16 characters a
    /// second on top of a fixed beat to find the line; cards are read slower,
    /// because they are meant to land.
    static func readingTime(_ text: String, style: StoryBeatStyle) -> Float {
        let count = Float(text.count)
        switch style {
        case .title: return 3.8
        case .card, .cardHigh: return max(2.6, 1.2 + count / 12)
        case .subtitle: return max(2.3, 0.9 + count / 16)
        }
    }

    /// Splits a paragraph into sentences.
    ///
    /// A sentence ends at `.`, `!`, `?` or `…` (with any closing quotes) followed by
    /// a space and something that can open a sentence. Ellipses mid-thought
    /// ("…or you perish") and a paragraph that is one sentence pass through whole.
    static func sentences(in text: String) -> [String] {
        let characters = Array(text)
        let terminators: Set<Character> = [".", "!", "?", "…"]
        let closers: Set<Character> = [".", "!", "?", "…", "\"", "“", "”", "'", "’", ")", "»"]
        var result: [String] = []
        var current = ""
        var i = 0
        while i < characters.count {
            let c = characters[i]
            current.append(c)
            i += 1
            guard terminators.contains(c) else { continue }
            while i < characters.count, closers.contains(characters[i]) {
                current.append(characters[i])
                i += 1
            }
            guard i + 1 < characters.count, characters[i] == " " else { continue }
            let opener = characters[i + 1]
            if opener.isUppercase || opener.isNumber || "\"„“…«".contains(opener) {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                i += 1
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }
}

// MARK: - Frame

/// Everything a shot's `render` gets for one frame.
struct ShotFrame {
    /// Seconds since the shot began, and the previous frame's value.
    let t: Float
    let previousT: Float
    let duration: Float
    let canvas: WireCanvas
    let overlay: StoryOverlay
    let timeline: ShotTimeline

    /// Progress through the shot, 0...1.
    var p: Float { clamp01(t / duration) }

    /// Points the camera. Every shot calls this before drawing.
    func look(_ camera: WireCamera) { canvas.begin(camera) }

    /// Whether `time` passed during this frame — for one-off events inside a shot.
    func crossed(_ time: Float) -> Bool { previousT < time && time <= t }

    /// 0...1 between two times in seconds, eased.
    func ramp(_ from: Float, _ to: Float) -> Float { smooth(from, to, t) }

    /// 0...1 between two fractions of the shot, eased.
    func pramp(_ from: Float, _ to: Float) -> Float { smooth(from, to, p) }

    func lineStart(_ line: Int) -> Float {
        line < timeline.spans.count ? timeline.spans[line].start : 0
    }

    func lineEnd(_ line: Int) -> Float {
        line < timeline.spans.count ? timeline.spans[line].end : duration
    }

    /// Splits a line's time into `count` phases — at its sentence boundaries when
    /// it has exactly that many sentences, evenly otherwise — and reports which
    /// phase `t` is in and how far through it.
    func phase(line: Int, count: Int) -> (index: Int, progress: Float) {
        var starts = phaseStarts(line: line, count: count)
        starts[0] = min(starts[0], 0)
        var index = 0
        for (i, s) in starts.enumerated() where t >= s { index = i }
        let end = index + 1 < starts.count ? starts[index + 1] : duration
        return (index, clamp01((t - starts[index]) / max(0.01, end - starts[index])))
    }

    /// When each of `phase(line:count:)`'s phases begins.
    func phaseStarts(line: Int, count: Int) -> [Float] {
        let beats = timeline.beats.filter { $0.line == line }
        if beats.count == count { return beats.map(\.start) }
        let a = lineStart(line), b = lineEnd(line)
        return (0..<count).map { a + (b - a) * Float($0) / Float(count) }
    }

    func cue(_ cue: StoryCue) { overlay.queue(cue) }

    /// Continuous camera shake for this frame, in points.
    func shake(_ amount: Float) { overlay.frameShake = max(overlay.frameShake, amount) }
}

// MARK: - Palette

enum StoryPalette {
    static let cyan = UIColor(red: 0.32, green: 0.9, blue: 1.0, alpha: 1)
    static let ice = UIColor(red: 0.72, green: 0.94, blue: 1.0, alpha: 1)
    static let blue = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1)
    static let violet = UIColor(red: 0.66, green: 0.4, blue: 1.0, alpha: 1)
    static let magenta = UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 1)
    static let ember = UIColor(red: 1.0, green: 0.42, blue: 0.2, alpha: 1)
    static let red = UIColor(red: 1.0, green: 0.2, blue: 0.24, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.78, blue: 0.3, alpha: 1)
    static let sun = UIColor(red: 1.0, green: 0.92, blue: 0.7, alpha: 1)
    static let green = UIColor(red: 0.45, green: 1.0, blue: 0.6, alpha: 1)
    static let white = UIColor.white

    /// A colour between two others, for gradients along a curve or over time.
    static func mix(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(clamp01(t))
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: 1)
    }
}

// MARK: - Shared scenery

/// Distant stars on a sphere around the camera. They never parallax — only a
/// turning camera moves them — which is exactly what makes them read as far.
struct StoryStarfield {
    private let directions: [Vec3]
    private let sizes: [Float]
    private let tints: [UIColor]
    private let phases: [Float]

    init(count: Int, seed: UInt64) {
        var rng = StoryRandom(seed: seed)
        var directions: [Vec3] = []
        var sizes: [Float] = []
        var tints: [UIColor] = []
        var phases: [Float] = []
        let palette = [StoryPalette.white, StoryPalette.ice, StoryPalette.sun, StoryPalette.violet]
        for _ in 0..<count {
            directions.append(rng.direction())
            let big = rng.unit()
            sizes.append(big > 0.93 ? rng.float(10...15) : rng.float(3.5...7))
            tints.append(palette[Int(rng.unit() * Float(palette.count)) % palette.count])
            phases.append(rng.float(0...(2 * .pi)))
        }
        self.directions = directions
        self.sizes = sizes
        self.tints = tints
        self.phases = phases
    }

    func draw(_ canvas: WireCanvas, around eye: Vec3, t: Float, alpha: Float = 1,
              stretch: Vec3? = nil) {
        for i in 0..<directions.count {
            let twinkle = 0.65 + 0.35 * sin(t * 1.7 + phases[i])
            let p = eye + directions[i] * 2000
            if let stretch {
                canvas.line(p, p + stretch, color: tints[i], alpha: alpha * twinkle * 0.7, width: 1)
            } else {
                canvas.dot(p, size: sizes[i], color: tints[i], alpha: alpha * twinkle, fogged: false)
            }
        }
    }
}

enum StoryScenery {

    /// The Singularity-7 with its engines lit.
    static func ship(_ canvas: WireCanvas, at position: Vec3, rotation q: simd_quatf, scale: Float = 1,
                     color: UIColor = StoryPalette.cyan, alpha: Float = 1, engine: Float = 1, t: Float,
                     width: Float = 1.5, edgeAlpha: ((Vec3, Vec3) -> Float)? = nil) {
        canvas.mesh(WireMesh.ship, at: position, rotation: q, scale: scale, color: color, alpha: alpha,
                    width: width, backAlpha: 0.45, edgeAlpha: edgeAlpha)
        guard engine > 0.01 else { return }
        let back = q.act(Vec3(0, 0, 1))
        for (i, nozzle) in WireMesh.shipNozzles.enumerated() {
            let p = position + q.act(nozzle * scale)
            let flicker = 0.85 + 0.15 * sin(t * 47 + Float(i) * 2.1)
            canvas.glow(p, radius: 5 * scale * engine * flicker, color: StoryPalette.cyan, alpha: alpha * 0.9)
            canvas.glow(p, radius: 2.2 * scale * engine, color: StoryPalette.white, alpha: alpha)
            // Exhaust: a fan of lines trailing from the nozzle, lengths flickering.
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + t * 9
                let side = q.act(Vec3(cos(a), sin(a), 0)) * 0.9 * scale
                let length = (10 + 5 * sin(t * 31 + Float(k * 3 + i))) * scale * engine
                canvas.line(p + side, p + back * length, color: StoryPalette.blue, alpha: alpha * 0.55 * engine, width: 1.1)
            }
        }
    }

    /// A circle through `center` in the plane spanned by `u` and `v`.
    static func circle(center: Vec3, radius: Float, u: Vec3, v: Vec3, segments: Int = 48,
                       from: Float = 0, to: Float = 2 * .pi) -> [Vec3] {
        (0...segments).map { s in
            let a = from + (to - from) * Float(s) / Float(segments)
            return center + (u * cos(a) + v * sin(a)) * radius
        }
    }

    /// A dashed ring — the gaps are what make its rotation visible.
    static func dashedRing(_ canvas: WireCanvas, center: Vec3, radius: Float, u: Vec3, v: Vec3,
                           phase: Float, dashes: Int, fill: Float, color: UIColor, alpha: Float, width: Float = 1.4) {
        let span = 2 * Float.pi / Float(dashes)
        for d in 0..<dashes {
            let a0 = phase + Float(d) * span
            canvas.polyline(circle(center: center, radius: radius, u: u, v: v, segments: 4, from: a0, to: a0 + span * fill),
                            color: color, alpha: alpha, width: width)
        }
    }

    /// A jagged bolt between two points, re-rolled every `period` seconds.
    static func lightning(_ canvas: WireCanvas, from a: Vec3, to b: Vec3, t: Float, seed: UInt64,
                          jitter: Float, color: UIColor, alpha: Float, period: Float = 0.09) {
        var rng = StoryRandom(seed: seed &+ UInt64(max(0, t / period)))
        let segments = 9
        var points: [Vec3] = [a]
        for s in 1..<segments {
            let base = lerp(a, b, Float(s) / Float(segments))
            points.append(base + rng.direction() * jitter * rng.unit())
        }
        points.append(b)
        canvas.polyline(points, color: color, alpha: alpha, width: 1.6)
        canvas.polyline(points, color: StoryPalette.white, alpha: alpha * 0.6, width: 0.7)
    }

    /// Two vectors spanning the plane perpendicular to `normal`.
    static func basis(_ normal: Vec3) -> (Vec3, Vec3) {
        let n = simd_normalize(normal)
        let helper = abs(n.y) < 0.9 ? Vec3(0, 1, 0) : Vec3(1, 0, 0)
        let u = simd_normalize(simd_cross(n, helper))
        return (u, simd_cross(n, u))
    }

    /// Warp-speed star streaks rushing past the camera, travelling along -Z.
    /// `speed` is world units per second; streak length follows it.
    static func warp(_ canvas: WireCanvas, around center: Vec3, t: Float, speed: Float, count: Int,
                     radius: Float, depth: Float, seed: UInt64, color: UIColor = StoryPalette.ice,
                     alpha: Float = 1, travelled: Float? = nil) {
        var rng = StoryRandom(seed: seed)
        let distance = travelled ?? t * speed
        let streak = min(160, 2 + speed * 0.08)
        for _ in 0..<count {
            let angle = rng.float(0...(2 * .pi))
            let r = radius * (0.25 + 0.75 * rng.unit().squareRoot())
            let z0 = rng.float(0...depth)
            // Wrap so the stream is endless: each streak cycles through `depth`.
            var z = (z0 + distance).truncatingRemainder(dividingBy: depth)
            if z < 0 { z += depth }
            let p = center + Vec3(cos(angle) * r, sin(angle) * r, -depth + z)
            canvas.line(p, p + Vec3(0, 0, -streak), color: color, alpha: alpha * 0.8, width: 1.2)
        }
    }
}
