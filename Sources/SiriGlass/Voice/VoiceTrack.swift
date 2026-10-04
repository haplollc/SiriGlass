//
//  VoiceTrack.swift
//  SiriGlass
//
//  A whole audio file run through the analyzer and the drive ahead of time,
//  on a fixed 120 Hz grid, so the drop's reaction at any instant is the
//  same on every run however the frames happen to fall. Used for
//  `SiriGlassAudio.file` and for scripted recordings.
//

import AVFoundation

final class VoiceTrack: @unchecked Sendable {
    static let rate = 120.0
    let duration: Double
    private let drives: [VoiceDrive]

    convenience init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        self.init(samples: samples, sampleRate: format.sampleRate)
    }

    /// Mono samples at `sampleRate`.
    init(samples: [Float], sampleRate: Double) {
        let duration = Double(samples.count) / max(sampleRate, 1)
        self.duration = duration
        let analyzer = VoiceAnalyzer()
        let hop = 1 / Self.rate
        var drive = VoiceDrive()
        var out: [VoiceDrive] = []
        out.reserveCapacity(Int(duration * Self.rate) + 2)
        samples.withUnsafeBufferPointer { all in
            var step = 0
            while Double(step) * hop <= duration {
                let t = Double(step) * hop
                // The window ends at t: the analysis only ever hears the past.
                let end = min(Int(t * sampleRate), all.count)
                let start = max(0, end - VoiceAnalyzer.windowSize)
                let raw = end > start
                    ? analyzer.measure(UnsafeBufferPointer(rebasing: all[start..<end]), sampleRate: sampleRate, elapsed: hop)
                    : SiriGlassLevels()
                drive.advance(toward: raw, dt: hop)
                out.append(drive)
                step += 1
            }
        }
        drives = out
    }

    /// The drive at `time` seconds into the file; before it, silence, and
    /// after it the strands keep drifting at rest.
    func drive(at time: Double) -> VoiceDrive {
        guard let first = drives.first, let last = drives.last else { return VoiceDrive() }
        if time <= 0 {
            var d = first
            d.levels = SiriGlassLevels()
            d.phases += VoiceDrive.restSpeed * time
            return d
        }
        let position = time * Self.rate
        let i = Int(position)
        if i >= drives.count - 1 {
            var d = last
            d.phases += VoiceDrive.restSpeed * (time - Double(drives.count - 1) / Self.rate)
            return d
        }
        let f = position - Double(i)
        let a = drives[i], b = drives[i + 1]
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * Float(f) }
        var d = VoiceDrive()
        d.levels = SiriGlassLevels(loudness: mix(a.levels.loudness, b.levels.loudness), low: mix(a.levels.low, b.levels.low),
                                   mid: mix(a.levels.mid, b.levels.mid), high: mix(a.levels.high, b.levels.high))
        d.phases = a.phases + (b.phases - a.phases) * f
        return d
    }

    /// Loudness of the file around `time`, as the drop would show it.
    func loudness(at time: Double) -> Float { drive(at: time).levels.loudness }
}
