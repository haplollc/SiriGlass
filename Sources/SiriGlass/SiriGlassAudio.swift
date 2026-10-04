//
//  SiriGlassAudio.swift
//  SiriGlass
//
//  What the drop listens to while it is listening.
//

import AVFoundation

/// What the drop reacts to while it is ``SiriGlassState/listening``.
///
/// ```swift
/// .siriGlass($state)                                   // the microphone
/// .siriGlass($state, audio: .file(greetingURL))        // a recording, played aloud
/// .siriGlass($state, audio: .feed(voice))              // audio you already have
/// ```
public struct SiriGlassAudio: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case microphone
        case file(URL, muted: Bool)
        case feed
    }

    let source: Source
    let feed: Feed?

    /// The device's microphone.
    ///
    /// The drop asks for permission the first time it listens. Your app's
    /// Info.plist needs `NSMicrophoneUsageDescription`; without it the drop
    /// doesn't ask (iOS would end the app) and hears silence. While it
    /// listens it sets the shared audio session to play-and-record, mixing
    /// with other audio and leaving Bluetooth playback where it is, and puts
    /// the session back when it stops.
    ///
    /// Like Siri, it moves to ``SiriGlassState/thinking`` a beat after the
    /// voice stops, and back to ``SiriGlassState/idle`` if no one speaks for
    /// 14 seconds.
    public static var microphone: SiriGlassAudio {
        SiriGlassAudio(source: .microphone, feed: nil)
    }

    /// An audio file, analysed ahead of time and played from the moment the
    /// drop starts listening. Handy for previews, demos and UI tests.
    ///
    /// Like the microphone, the drop moves itself to
    /// ``SiriGlassState/thinking`` once the voice in the file stops.
    ///
    /// - Parameters:
    ///   - url: Any file `AVAudioFile` can read.
    ///   - muted: Reacts to the file without playing it.
    public static func file(_ url: URL, muted: Bool = false) -> SiriGlassAudio {
        SiriGlassAudio(source: .file(url, muted: muted), feed: nil)
    }

    /// Audio you supply yourself: buffers from your own input tap, a
    /// synthesizer reading its answer aloud, or levels you measured.
    ///
    /// With a feed the drop never changes its state on its own; you decide
    /// when it stops listening.
    public static func feed(_ feed: Feed) -> SiriGlassAudio {
        SiriGlassAudio(source: .feed, feed: feed)
    }

    /// Whether the drop decides by itself when the speaker has finished.
    var listensLikeSiri: Bool { source != .feed }

    public static func == (a: SiriGlassAudio, b: SiriGlassAudio) -> Bool {
        a.source == b.source && a.feed === b.feed
    }
}

extension SiriGlassAudio {
    /// A stream of audio for the drop to react to.
    ///
    /// Keep one for as long as the view lives, for example in `@State`, and
    /// send it audio from any thread:
    ///
    /// ```swift
    /// @State private var voice = SiriGlassAudio.Feed()
    ///
    /// // In your AVAudioEngine tap, or as your player node plays:
    /// voice.send(buffer)
    ///
    /// // Or levels you measured yourself, about 30 times a second:
    /// voice.send(SiriGlassLevels(loudness: meter.level))
    /// ```
    public final class Feed: @unchecked Sendable {
        let stream = VoiceStream()

        public init() {}

        /// Analyses a buffer of audio the way the drop analyses the
        /// microphone: loudness against the loudest speech heard lately,
        /// and where it sits in the spectrum.
        ///
        /// Send buffers as they are heard (from a tap on your input or
        /// player node), not faster than real time: each one is shown about
        /// a tenth of a second after it arrives, spread over its length.
        /// Float or integer PCM; the first channel is used.
        public func send(_ buffer: AVAudioPCMBuffer) {
            stream.analyze(buffer)
        }

        /// Shows levels you measured yourself. Send them at least ten times
        /// a second: after 0.3 s without any the drop hears silence.
        public func send(_ levels: SiriGlassLevels) {
            stream.push(levels)
        }
    }
}

/// How loud a voice is, and where its energy sits in the spectrum, each
/// from 0 to 1.
public struct SiriGlassLevels: Sendable, Equatable {
    /// Overall loudness: 0 is silence, 1 as loud as the speech heard lately.
    public var loudness: Float
    /// Energy around 80–400 Hz, the body of vowels. Drives the widest strand.
    public var low: Float
    /// Energy around 400 Hz–2 kHz.
    public var mid: Float
    /// Energy around 2–6 kHz, the consonants. Drives the narrowest strand.
    public var high: Float

    /// Levels for the drop. Leave the bands out and they follow the
    /// loudness the way a speaking voice usually spreads.
    public init(loudness: Float, low: Float? = nil, mid: Float? = nil, high: Float? = nil) {
        func unit(_ x: Float) -> Float { x.isFinite ? min(max(x, 0), 1) : 0 }
        self.loudness = unit(loudness)
        self.low = unit(low ?? loudness)
        self.mid = unit(mid ?? loudness * 0.8)
        self.high = unit(high ?? loudness * 0.55)
    }

    /// Silence.
    public init() {
        self.init(loudness: 0, low: 0, mid: 0, high: 0)
    }
}
