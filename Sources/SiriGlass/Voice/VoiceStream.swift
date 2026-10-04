//
//  VoiceStream.swift
//  SiriGlass
//
//  Live audio, from any thread, as a smooth stream of levels for the frame
//  loop. Audio arrives in chunks (about a tenth of a second from an input
//  tap), so each chunk is measured a window at a time and the windows are
//  replayed at the pace they were heard: the light moves at ~47 updates a
//  second, about a tenth of a second behind the voice, instead of jumping
//  ten times a second. If audio stops arriving (an interruption, a route
//  change, a feed that went quiet) the stream runs dry and the drop hears
//  silence rather than the last word frozen.
//

import AVFoundation
import QuartzCore
import os

final class VoiceStream: @unchecked Sendable {
    /// How far behind the audio the light runs.
    static let latency = 0.11

    private struct Pending: Sendable {
        var windows: [(due: Double, levels: SiriGlassLevels)] = []
        var current = SiriGlassLevels()
        var lastHeard = -Double.infinity
    }

    private let pending = OSAllocatedUnfairLock(initialState: Pending())
    private let analysis = OSAllocatedUnfairLock(initialState: VoiceAnalyzer())

    // MARK: Producing (any thread)

    /// Measures a buffer of audio a window at a time and queues each
    /// window for the moment it is due. Mono or the first channel; float or
    /// 16/32-bit integer samples, interleaved or not.
    func analyze(_ buffer: AVAudioPCMBuffer, now: Double = CACurrentMediaTime()) {
        let count = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard count > 0, sampleRate > 0 else { return }
        let stride = max(buffer.stride, 1)
        var samples = [Float](repeating: 0, count: count)
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<count { samples[i] = channel[i * stride] }
        } else if let channel = buffer.int16ChannelData?[0] {
            for i in 0..<count { samples[i] = Float(channel[i * stride]) / 32_768 }
        } else if let channel = buffer.int32ChannelData?[0] {
            for i in 0..<count { samples[i] = Float(channel[i * stride]) / 2_147_483_648 }
        } else {
            return
        }
        analyze(samples, sampleRate: sampleRate, now: now)
    }

    func analyze(_ samples: [Float], sampleRate: Double, now: Double = CACurrentMediaTime()) {
        let count = samples.count
        guard count > 0 else { return }
        let window = VoiceAnalyzer.windowSize
        // Whole windows from the end backwards, so none is a ragged tail,
        // then measured oldest first.
        var found: [Int] = []
        var start = count - window
        while start >= 0 { found.append(start); start -= window }
        let starts = found.isEmpty ? [0] : found
        let hop = Double(window) / sampleRate
        let measured: [(due: Double, levels: SiriGlassLevels)] = analysis.withLock { analyzer in
            samples.withUnsafeBufferPointer { all in
                starts.reversed().enumerated().map { i, s in
                    let length = min(window, count - s)
                    let levels = analyzer.measure(UnsafeBufferPointer(rebasing: all[s..<(s + length)]),
                                                  sampleRate: sampleRate, elapsed: hop)
                    return (now + Self.latency - Double(starts.count - 1 - i) * hop, levels)
                }
            }
        }
        pending.withLock { state in
            state.windows.append(contentsOf: measured)
            if state.windows.count > 64 { state.windows.removeFirst(state.windows.count - 64) }
        }
    }

    /// Levels measured elsewhere, shown as they arrive.
    func push(_ levels: SiriGlassLevels, now: Double = CACurrentMediaTime()) {
        pending.withLock { state in
            state.windows.append((now, levels))
            if state.windows.count > 64 { state.windows.removeFirst(state.windows.count - 64) }
        }
    }

    // MARK: Consuming (the frame loop)

    /// The level due now: the newest window whose time has come, or
    /// silence once nothing has arrived for a while.
    func levels(now: Double = CACurrentMediaTime()) -> SiriGlassLevels {
        pending.withLock { state in
            if let index = state.windows.lastIndex(where: { $0.due <= now }) {
                state.current = state.windows[index].levels
                state.windows.removeFirst(index + 1)
                state.lastHeard = now
            } else {
                // The clock jumped (a long stall): drop what can't be shown.
                if let first = state.windows.first, first.due > now + 1 { state.windows.removeAll() }
                // Nothing heard for a while: silence, not the last word frozen.
                if state.windows.isEmpty, now - state.lastHeard > 0.3 { state.current = SiriGlassLevels() }
            }
            return state.current
        }
    }

    func reset() {
        pending.withLock { $0 = Pending() }
    }
}
