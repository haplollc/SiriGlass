//
//  DropEngine.swift
//  SiriGlass
//
//  The life of one drop, a frame at a time: when it was summoned, when it
//  started thinking, when it left, and what it is hearing. Every frame it
//  turns those into the shader's uniforms. Nothing animates on its own:
//  shape, light and voice are all functions of one clock, so a scripted
//  take can be slowed down for recording and still come out identical.
//

import SwiftUI
import UIKit

@MainActor
final class DropEngine {

    /// Where the drop is drawn.
    enum Layout {
        /// Hanging from the island (in the layer's space).
        case island(CGRect)
        /// On its own, centred, at `scale` times its size under the island.
        case orb(centre: CGPoint, scale: Double)
    }

    struct Output {
        var frame: DropFrame
        var outline: [CGPoint]
        /// A change the drop made by itself, for the binding: from, to.
        var request: (from: SiriGlassState, to: SiriGlassState)?
        /// Nothing left to animate: home, still, silent.
        var resting: Bool
    }

    // MARK: State

    /// What the drop is doing now.
    private(set) var mode: SiriGlassState = .idle
    private var summonedAt: Double?
    private var dismissedAt: Double?
    private var listeningSince = 0.0
    private var think = Ramp()
    /// Extra strand travel while thinking: the swirl.
    private var swirl = 0.0

    private var epoch: Date?
    private var lastClock: Double?

    private var drive = VoiceDrive()
    private var speech = SpeechEnd()
    /// A change the drop made that the binding hasn't caught up with.
    private var awaiting: (from: SiriGlassState, to: SiriGlassState)?

    // The audio source while listening.
    private var listeningTo: SiriGlassAudio?
    private var mic: MicListener?
    private var file: FileVoice?
    private var trackStart = 0.0

    /// Shows only the glass (debug).
    var glassOnly = false

    // MARK: Timing

    /// How long a summoned drop takes to settle, and to go home.
    nonisolated static let leaveTime = 0.5
    nonisolated static let restAfterLeaving = 0.65
    nonisolated static let thinkTime = 0.35

    // MARK: - One frame

    func frame(at date: Date, requested: SiriGlassState, audio: SiriGlassAudio, writable: Bool,
               take: TakeContext?, layout: Layout, backdrop: Double) -> Output {
        let clock: Double
        if let take {
            clock = take.take.clock(at: date)
        } else {
            if epoch == nil { epoch = date }
            clock = max(date.timeIntervalSince(epoch!), 0)
        }
        let dt = lastClock.map { min(max(clock - $0, 0), 0.1) } ?? 0
        lastClock = clock

        var request: (from: SiriGlassState, to: SiriGlassState)?
        if let take {
            follow(take, clock: clock)
        } else {
            if case .file(let url, _) = audio.source { FileVoice.prepare(url) }
            // The host's word, unless it is still catching up with a change
            // the drop made itself.
            if let pending = awaiting, requested != pending.from || requested == pending.to { awaiting = nil }
            if awaiting == nil, requested != mode { apply(requested, at: clock, audio: audio) }
            if mode == .listening, audio != listeningTo {
                stopAudio()
                startAudio(audio, at: clock)
            }
            request = advance(clock: clock, dt: dt, autoListen: writable && audio.listensLikeSiri)
        }

        let frame = render(clock: clock, layout: layout, backdrop: backdrop)
        let outline = frame.isVisible ? DropField(frame).outline() : []
        let home = dismissedAt.map { clock - $0 > Self.restAfterLeaving } ?? (summonedAt == nil)
        let resting = take == nil && mode == .idle && home && drive.levels.loudness < 0.001
        return Output(frame: frame, outline: outline, request: request, resting: resting)
    }

    /// Leaving the screen: the microphone goes off and the drop goes home
    /// with nothing pending.
    func stop() {
        stopAudio()
        mode = .idle
        summonedAt = nil
        dismissedAt = nil
        think = Ramp()
        awaiting = nil
        drive = VoiceDrive()
    }

    // MARK: - Changes of state

    private func apply(_ target: SiriGlassState, at now: Double, audio: SiriGlassAudio) {
        guard target != mode else { return }
        let old = mode
        mode = target
        switch target {
        case .listening:
            if old == .idle { summon(at: now) }
            think.set(0, at: now)
            listeningSince = now
            speech = SpeechEnd()
            startAudio(audio, at: now)
        case .thinking:
            if old == .idle { summon(at: now) }
            think.set(1, at: now)
            stopAudio()
        case .idle:
            dismissedAt = now
            stopAudio()
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
    }

    /// Out of the island. Called back while still on its way home, it
    /// carries on from the size it has rather than starting over.
    private func summon(at now: Double) {
        var since = 0.0
        if let dismissedAt, let summonedAt, now - dismissedAt < Self.leaveTime {
            let current = Self.fill(now - summonedAt) * Self.leave(now - dismissedAt)
            while since < 0.6 && Self.fill(since) < current { since += 0.005 }
        }
        summonedAt = now - since
        dismissedAt = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
    }

    /// Listens for a frame; returns the change it made by itself, if any.
    private func advance(clock: Double, dt: Double, autoListen: Bool) -> (from: SiriGlassState, to: SiriGlassState)? {
        var raw = SiriGlassLevels()
        var request: (from: SiriGlassState, to: SiriGlassState)?
        if mode == .listening {
            raw = levels(at: clock)
            if autoListen, let verdict = speech.hear(raw.loudness, dt: dt, listening: clock - listeningSince) {
                let target: SiriGlassState = verdict == .finished ? .thinking : .idle
                apply(target, at: clock, audio: listeningTo ?? .microphone)
                awaiting = (.listening, target)
                request = awaiting
                raw = SiriGlassLevels()
            }
        }
        drive.advance(toward: raw, dt: dt)
        swirl += think.value(at: clock) * dt
        return request
    }

    /// A scripted take: every change at its cue, the voice from its file.
    private func follow(_ take: TakeContext, clock: Double) {
        let cues = take.cues
        summonedAt = cues.listen ?? cues.think
        dismissedAt = cues.idle
        think = Ramp(from: 0, to: 1, at: cues.think ?? .infinity)
        mode = cues.state(at: clock)
        drive = take.take.voice?.drive(at: clock) ?? VoiceDrive.resting(at: clock)
        swirl = cues.think.map { max(clock - $0 - Self.thinkTime / 2, 0) } ?? 0
        glassOnly = take.take.showsOnlyGlass
    }

    // MARK: - Audio

    private func startAudio(_ audio: SiriGlassAudio, at now: Double) {
        listeningTo = audio
        switch audio.source {
        case .microphone:
            let mic = self.mic ?? MicListener()
            self.mic = mic
            Task { @MainActor [weak self] in
                let ok = await mic.start()
                // Sent away, or the screen left, while permission was asked.
                if ok, self?.mode != .listening || self?.listeningTo?.source != .microphone { mic.stop() }
            }
        case .file(let url, let muted):
            let voice = FileVoice(url: url, muted: muted)
            trackStart = now + 0.1
            voice.play(after: 0.1)
            file = voice
        case .feed:
            audio.feed?.stream.reset()
        }
    }

    private func stopAudio() {
        mic?.stop()
        file?.stop()
        file = nil
        listeningTo = nil
    }

    private func levels(at clock: Double) -> SiriGlassLevels {
        guard let listeningTo else { return SiriGlassLevels() }
        switch listeningTo.source {
        case .microphone: return mic?.levels() ?? SiriGlassLevels()
        case .file: return file?.levels(at: clock - trackStart) ?? SiriGlassLevels()
        case .feed: return listeningTo.feed?.stream.levels() ?? SiriGlassLevels()
        }
    }

    // MARK: - Shape and light from the clock

    private func render(clock: Double, layout: Layout, backdrop: Double) -> DropFrame {
        var f = DropFrame()
        f.clock = clock
        f.time = Float(clock.truncatingRemainder(dividingBy: 1000))
        if case .island(let island) = layout { f.island = island }

        guard let summonedAt, clock >= summonedAt else { return f }
        let since = clock - summonedAt
        let level = Double(drive.levels.loudness)

        // Out of the island like a drop: a small bead forms at the island's
        // foot and drips down while it swells, joined to the island by a
        // liquid neck, then hangs there. Both springs overshoot a little, so
        // it lands with some weight and settles. It lengthens first and
        // fills out a beat later, so mid-drip it is a round-bottomed
        // teardrop rather than a box.
        let drip = Self.spring(since, delay: 0.0, frequency: 2.3, damping: 0.78)
        let lengthen = Self.spring(since, delay: 0.03, frequency: 2.0, damping: 0.62)
        let fill = Self.fill(since)

        // Back in: a small swell, then a quick pull home.
        let leave = dismissedAt.map { clock >= $0 ? Self.leave(clock - $0) : 1 } ?? 1
        // Thinking draws it in a little, as if it were concentrating.
        let thinking = think.value(at: clock)
        let concentrate = 1 - 0.07 * thinking

        // Listening, it breathes and swells with the voice. Under the island
        // it hangs from its top, so it grows downward and outward and the
        // island never shows through; the orb swells about its middle.
        let breath = 1 + 0.006 * sin(clock * 2 * .pi * 0.38)
        let settledHalfW = DropGeometry.halfWidth * (1 + 0.034 * level) * breath * concentrate
        let settledHalfH = (DropGeometry.bottom - DropGeometry.top) / 2 * (1 + 0.028 * level) * breath * concentrate
        let seedHalfW = 16.0, seedHalfH = 13.0

        let kDrip = drip * leave, kLength = lengthen * leave, kFill = fill * leave
        let halfW = Self.mix(seedHalfW, settledHalfW, kFill)
        let halfH = Self.mix(seedHalfH, settledHalfH, kLength)
        let grown = min(max(kFill, 0), 1)
        let presence = min(max((drip * leave + lengthen * leave) * 2.5, 0), 1)

        var centre: CGPoint, scale = 1.0, island: CGRect, neck: Double
        switch layout {
        case .island(let rect):
            // Out of the island, hanging from it. The bead it grows from is
            // tucked into the island's foot.
            let foot = CGPoint(x: rect.midX, y: rect.midY + 3)
            centre = CGPoint(x: foot.x, y: Self.mix(foot.y, DropGeometry.top + settledHalfH, kDrip))
            island = rect
            // A wide, gooey neck until the bead has swallowed the island;
            // nearly none once it hangs free.
            neck = 1 + 17 * (1 - Self.easeInOut(min(max((grown - 0.78) / 0.22, 0), 1)))
        case .orb(let at, let size):
            // On its own: it blooms from a point.
            centre = at
            scale = size
            island = CGRect(x: at.x - 1, y: at.y - 1, width: 2, height: 2)
            neck = 1
        }

        // The shader works in the drop's design space around its centre, so
        // the island goes over in those terms too.
        f.island = CGRect(x: centre.x + (island.minX - centre.x) / scale, y: centre.y + (island.minY - centre.y) / scale,
                          width: island.width / scale, height: island.height / scale)
        f.drop = SIMD4(Float(centre.x), Float(centre.y), Float(max(halfW, 1)), Float(max(halfH, 1)))
        f.exponent = Float(Self.mix(2.0, 2.4, grown))
        f.neck = Float(neck)
        f.presence = Float(presence)
        f.extra = SIMD4(Float(grown), glassOnly ? 1 : 0, Float(scale), Float(backdrop))

        // The line lights from the middle once the drop is out, and goes
        // dark first on the way back in.
        var ignite = Self.easeInOut(min(max((since - 0.16) / 0.42, 0), 1))
        if let dismissedAt, clock >= dismissedAt {
            ignite *= 1 - Self.easeInOut(min(max((clock - dismissedAt) / 0.22, 0), 1))
        }

        // Strand heights: a small idle swell plus each band's share of the
        // voice. Thinking, they settle into one steady lens of light that
        // swirls slowly round itself.
        let lv = drive.levels
        let a1 = Self.mix(2.8 + 11.0 * Double(lv.low), 7.5, thinking)
        let a2 = Self.mix(1.7 + 7.0 * Double(lv.mid), 3.0, thinking)
        let a3 = Self.mix(1.1 + 5.0 * Double(lv.high), 1.8, thinking)
        f.amps = SIMD4(Float(a1 * ignite), Float(a2 * ignite), Float(a3 * ignite), Float(level * (1 - thinking)))
        let p = drive.phases + VoiceDrive.restSpeed * 1.6 * swirl
        func wrap(_ x: Double) -> Float { Float(x.truncatingRemainder(dividingBy: 2 * .pi)) }
        f.phases = SIMD4(wrap(p.x), wrap(p.y), wrap(p.z), wrap(p.w))
        f.light = SIMD4(Float(ignite), Float(thinking), Float(0.07 * halfH), 0)
        return f
    }

    // MARK: - Curves

    /// How full the bead is `t` seconds after it was summoned.
    nonisolated static func fill(_ t: Double) -> Double { spring(t, delay: 0.09, frequency: 1.7, damping: 0.6) }

    /// 1 while out, through a small swell, to 0 home, `t` seconds after it
    /// was sent away.
    nonisolated static func leave(_ t: Double) -> Double {
        let u = t / leaveTime
        guard u < 1 else { return 0 }
        let puff = 0.035 * sin(min(u / 0.28, 1) * .pi)
        return (1 + puff) * (1 - easeInOut(min(max((u - 0.12) / 0.88, 0), 1)))
    }

    /// A damped spring from 0 to 1, started `delay` seconds in.
    nonisolated static func spring(_ t: Double, delay: Double, frequency: Double, damping: Double) -> Double {
        let t = t - delay
        guard t > 0 else { return 0 }
        let w0 = 2 * .pi * frequency
        let wd = w0 * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * w0 * t)
        return 1 - decay * (cos(wd * t) + damping * w0 / wd * sin(wd * t))
    }

    nonisolated static func easeInOut(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    nonisolated static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// A value easing from one level to another over `thinkTime`.
struct Ramp: Equatable {
    var from = 0.0
    var to = 0.0
    var at = 0.0

    func value(at t: Double) -> Double {
        let u = min(max((t - at) / DropEngine.thinkTime, 0), 1)
        return DropEngine.mix(from, to, DropEngine.easeInOut(u))
    }

    mutating func set(_ target: Double, at t: Double) {
        guard target != to else { return }
        from = value(at: t)
        to = target
        at = t
    }
}
