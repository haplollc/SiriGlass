//
//  SiriGlassTake.swift
//  SiriGlass
//
//  What the demo's recordings need, as SPI while its shape settles:
//
//      @_spi(Recording) import SiriGlass
//
//  A take is a clock and a voice file. Drops inside `.siriGlassTake(_:cues:)`
//  follow the take's clock instead of the wall's and change state exactly at
//  their cues, reacting to the take's voice file (analysed, never played),
//  so a recording can run several times slower than real time on a busy
//  machine and be sped back up with every frame where it should be.
//

import SwiftUI

/// A scripted run of the drop for recordings and stills.
@_spi(Recording)
@MainActor
public final class SiriGlassTake {
    /// Everything runs this many times slower than real time.
    public let pace: Double
    /// Real seconds the take holds its first instant before the clock runs.
    public let hold: Double
    /// Holds the take at one instant, for stills.
    public let freeze: Double?
    /// Paints nothing over the glass, to look at the glass alone.
    public var showsOnlyGlass = false

    let voice: VoiceTrack?
    private var epoch: Date?

    /// - Parameter voice: The file the drop reacts to, on the take's clock
    ///   (its first sample at 0 s).
    public init(pace: Double = 1, hold: Double = 0, freeze: Double? = nil, voice: URL? = nil) {
        self.pace = max(pace, 0.01)
        self.hold = max(hold, 0)
        self.freeze = freeze
        self.voice = voice.flatMap { try? VoiceTrack(url: $0) }
    }

    /// Seconds on the take's clock at `date`. Its first call starts it.
    /// Slowed down, it steps in whole sixtieths of a second, so every frame
    /// of a sped-up recording is an exact instant.
    public func clock(at date: Date) -> Double {
        if let freeze { return freeze }
        if epoch == nil { epoch = date.addingTimeInterval(hold) }
        let raw = max(date.timeIntervalSince(epoch!), 0) / pace
        return pace > 1 ? (raw * 60).rounded(.down) / 60 : raw
    }

    /// The voice's loudness at a moment of the take, as the drop shows it.
    public func loudness(at clock: Double) -> Float {
        voice?.loudness(at: clock) ?? 0
    }
}

/// When a drop in a take changes state, in seconds on the take's clock.
@_spi(Recording)
public struct SiriGlassCues: Sendable, Equatable {
    public var listen: Double?
    public var think: Double?
    public var idle: Double?

    public init(listen: Double? = nil, think: Double? = nil, idle: Double? = nil) {
        self.listen = listen
        self.think = think
        self.idle = idle
    }

    /// What the drop is doing at `clock`.
    public func state(at clock: Double) -> SiriGlassState {
        if let idle, clock >= idle { return .idle }
        if let think, clock >= think { return .thinking }
        if let listen, clock >= listen { return .listening }
        return .idle
    }
}

/// What a drop showed on its last frame, for UI tests and timing.
@_spi(Recording)
@MainActor
public final class SiriGlassProbe {
    public init() {}
    /// The voice level the light is showing, 0…1.
    public private(set) var loudness: Float = 0
    /// How far out the drop is, 0 home … 1 out.
    public private(set) var presence: Float = 0
    /// What the drop is doing.
    public private(set) var state: SiriGlassState = .idle
    /// Seconds on the drop's clock.
    public private(set) var clock: Double = 0

    func record(_ out: DropEngine.Output, state: SiriGlassState) {
        loudness = out.frame.amps.w
        presence = out.frame.presence
        self.state = state
        clock = out.frame.clock
    }
}

/// Where the drop takes the Dynamic Island to be.
@_spi(Recording)
public enum SiriGlassIsland {
    /// The island's frame in a portrait window of `size` with this top safe
    /// area (or, without an island, a pill just above the top edge).
    public static func frame(windowSize size: CGSize, safeAreaTop: CGFloat, isPhone: Bool = true) -> CGRect {
        DropGeometry.island(in: WindowMetrics(size: size, safeAreaTop: safeAreaTop, isPhone: isPhone))
    }
}

struct TakeContext {
    let take: SiriGlassTake
    let cues: SiriGlassCues
}

private struct SiriGlassTakeKey: EnvironmentKey {
    static let defaultValue: TakeContext? = nil
}

private struct SiriGlassProbeKey: EnvironmentKey {
    static let defaultValue: SiriGlassProbe? = nil
}

extension EnvironmentValues {
    var siriGlassTake: TakeContext? {
        get { self[SiriGlassTakeKey.self] }
        set { self[SiriGlassTakeKey.self] = newValue }
    }

    var siriGlassProbe: SiriGlassProbe? {
        get { self[SiriGlassProbeKey.self] }
        set { self[SiriGlassProbeKey.self] = newValue }
    }
}

@_spi(Recording)
extension View {
    /// Drops in this view follow `take`'s clock and `cues`, ignoring the
    /// state they are given.
    public func siriGlassTake(_ take: SiriGlassTake?, cues: SiriGlassCues) -> some View {
        environment(\.siriGlassTake, take.map { TakeContext(take: $0, cues: cues) })
    }

    /// Drops in this view report what they showed on each frame to `probe`.
    public func siriGlassProbe(_ probe: SiriGlassProbe?) -> some View {
        environment(\.siriGlassProbe, probe)
    }
}
