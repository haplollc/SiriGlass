//
//  SpeechEnd.swift
//  SiriGlass
//
//  When to stop listening, the way Siri does: a beat after you stop
//  talking, never more than half a minute (a noisy room), and if nobody
//  says anything at all, give up after a while.
//

struct SpeechEnd: Equatable {
    enum Verdict: Equatable {
        /// Someone spoke and has stopped: think about it.
        case finished
        /// Nobody spoke: go away.
        case nobodySpoke
    }

    /// Loudness that counts as speech.
    static let speech: Float = 0.22
    /// Speech needs to last this long to count…
    static let minimumSpeech = 0.5
    /// …and this much quiet after it ends it.
    static let pause = 1.4
    /// Silence this long, with no speech at all, sends the drop away.
    static let patience = 14.0
    /// Listening never lasts longer than this.
    static let limit = 30.0

    private(set) var spokenFor = 0.0
    private(set) var quietFor = 0.0

    /// Hears `dt` seconds at `loudness`, `listening` seconds into listening.
    mutating func hear(_ loudness: Float, dt: Double, listening: Double) -> Verdict? {
        if loudness > Self.speech { spokenFor += dt; quietFor = 0 } else { quietFor += dt }
        if (spokenFor > Self.minimumSpeech && quietFor > Self.pause) || listening > Self.limit { return .finished }
        if spokenFor < Self.minimumSpeech && listening > Self.patience { return .nobodySpoke }
        return nil
    }
}
