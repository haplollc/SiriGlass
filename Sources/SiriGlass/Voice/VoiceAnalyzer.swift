//
//  VoiceAnalyzer.swift
//  SiriGlass
//
//  Turns a window of audio into a loudness and three band levels.
//
//  Loudness is judged against the loudest speech heard lately rather than a
//  fixed level, so a quiet voice across the room and a loud one up close
//  both fill the drop, and room noise under a gate leaves it calm.
//

import Accelerate
import Foundation

/// Measures one window of mono samples at a time. Not thread-safe: one
/// analyzer per stream, used from one thread at a time.
final class VoiceAnalyzer: @unchecked Sendable {
    static let windowSize = 1024
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var outReal: [Float]
    private var outImag: [Float]
    private var power: [Float]
    /// The loudest speech heard lately (dBFS), falling 6 dB a second.
    private var peak: Float = -32

    init() {
        let n = Self.windowSize
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        outReal = [Float](repeating: 0, count: n / 2)
        outImag = [Float](repeating: 0, count: n / 2)
        power = [Float](repeating: 0, count: n / 2)
    }

    /// `samples` holds up to `windowSize` samples (fewer are zero-padded);
    /// `elapsed` is the time since the previous call, for the peak's decay.
    func measure(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double, elapsed: Double) -> SiriGlassLevels {
        let n = Self.windowSize
        let count = min(samples.count, n)
        guard count > 0, sampleRate > 0 else { return SiriGlassLevels() }

        let rms = vDSP.rootMeanSquare(UnsafeBufferPointer(rebasing: samples[0..<count]))
        // One bad sample would poison the smoothing for good.
        guard rms.isFinite else { return SiriGlassLevels() }
        let db = 20 * log10(max(rms, 1e-7))
        peak = max(db, peak - 6 * Float(elapsed))
        peak = max(peak, -32)                       // never chase the noise floor
        let gate = Self.smooth(-54, -42, db)        // a quiet room stays calm
        let norm = min(max((db - (peak - 22)) / 22, 0), 1)
        let level = pow(norm, 1.15) * gate

        // Where the energy sits: lows are vowels' body, highs are consonants.
        for i in 0..<n { windowed[i] = i < count ? samples[i] * window[i] : 0 }
        let half = n / 2
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                outReal.withUnsafeMutableBufferPointer { oRe in
                    outImag.withUnsafeMutableBufferPointer { oIm in
                        let packed = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        var split = packed
                        windowed.withUnsafeBufferPointer { w in
                            w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        // Out of place: vDSP doesn't promise this one works in place.
                        var spectrum = DSPSplitComplex(realp: oRe.baseAddress!, imagp: oIm.baseAddress!)
                        fft.forward(input: packed, output: &spectrum)
                        oIm[0] = 0                                // packed Nyquist term
                        power.withUnsafeMutableBufferPointer { p in
                            vDSP_zvmags(&spectrum, 1, p.baseAddress!, 1, vDSP_Length(half))
                        }
                    }
                }
            }
        }
        let hz = sampleRate / Double(n)
        func band(_ from: Double, _ to: Double) -> Float {
            let a = max(1, Int(from / hz)), b = min(n / 2 - 1, Int(to / hz))
            guard b > a else { return 0 }
            return vDSP.sum(power[a...b])
        }
        let low = band(80, 400), mid = band(400, 2_000), high = band(2_000, 6_000)
        let total = low + mid + high + 1e-12
        func share(_ e: Float) -> Float { min(level * (0.45 + 1.65 * e / total), 1) }
        return SiriGlassLevels(loudness: level, low: share(low), mid: share(mid), high: share(high))
    }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Smoothing and the strands' phases

/// The voice as the drop shows it: smoothed levels (quick to rise, slower
/// to fall) and the strand phases, which run faster the louder it gets.
struct VoiceDrive: Sendable, Equatable {
    var levels = SiriGlassLevels()
    /// Unwrapped radians: strand 1, 2, 3 and the prism's drift.
    var phases = SIMD4<Double>(0.6, 2.1, 4.0, 0)

    static let restSpeed = SIMD4<Double>(1.6, -2.3, 2.9, 1.0)
    static let voiceSpeed = SIMD4<Double>(4.6, -5.6, 6.8, 2.6)

    mutating func advance(toward raw: SiriGlassLevels, dt: Double) {
        guard dt > 0 else { return }
        levels.loudness = Self.follow(levels.loudness, raw.loudness, dt, rise: 0.035, fall: 0.16)
        levels.low = Self.follow(levels.low, raw.low, dt, rise: 0.05, fall: 0.22)
        levels.mid = Self.follow(levels.mid, raw.mid, dt, rise: 0.04, fall: 0.18)
        levels.high = Self.follow(levels.high, raw.high, dt, rise: 0.03, fall: 0.14)
        phases += (Self.restSpeed + Self.voiceSpeed * Double(levels.loudness)) * dt
    }

    /// Silence, with the strands drifting at rest since time zero.
    static func resting(at time: Double) -> VoiceDrive {
        var drive = VoiceDrive()
        drive.phases += restSpeed * time
        return drive
    }

    private static func follow(_ value: Float, _ target: Float, _ dt: Double, rise: Double, fall: Double) -> Float {
        let tau = target > value ? rise : fall
        let k = Float(1 - exp(-dt / tau))
        return value + (target - value) * k
    }
}
