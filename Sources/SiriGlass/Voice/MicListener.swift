//
//  MicListener.swift
//  SiriGlass
//
//  Taps the microphone and hands the frame loop a smooth stream of levels.
//  Asks for permission the first time (the host app's Info.plist needs
//  NSMicrophoneUsageDescription), listens through the phone's microphone
//  while leaving any Bluetooth playback where it is, and puts the audio
//  session back the way it found it when it stops.
//

import AVFoundation
import os

@MainActor
final class MicListener {
    let stream = VoiceStream()
    private var running: Running?
    /// Bumped by stop(), so a start() still waiting on permission or the
    /// audio session knows it has been called off.
    private var generation = 0
    nonisolated private static let log = Logger(subsystem: "SiriGlass", category: "microphone")
    private static var warnedAboutUsageDescription = false

    /// The session as it was before the drop started listening.
    private struct SessionState: Sendable {
        var category: AVAudioSession.Category
        var mode: AVAudioSession.Mode
        var options: AVAudioSession.CategoryOptions
    }

    /// A running engine and the session to put back when it stops. Handed
    /// between the main actor and the set-up thread, never used on both.
    private final class Running: @unchecked Sendable {
        let engine: AVAudioEngine
        let previous: SessionState
        init(engine: AVAudioEngine, previous: SessionState) {
            self.engine = engine
            self.previous = previous
        }
    }

    /// Without this key iOS ends the app the moment it asks for the
    /// microphone, so the drop never asks without it.
    static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    /// False when there is no microphone to listen to, permission was
    /// refused, or stop() was called meanwhile.
    func start() async -> Bool {
        if running != nil { return true }
        guard Self.hasUsageDescription else {
            if !Self.warnedAboutUsageDescription {
                Self.warnedAboutUsageDescription = true
                Self.log.error("SiriGlass can't listen: add NSMicrophoneUsageDescription to your app's Info.plist. The drop will hear silence.")
            }
            return false
        }
        let ticket = generation
        guard await AVAudioApplication.requestRecordPermission(), ticket == generation else { return false }
        // Session and engine set-up block for a moment: keep them off the
        // main thread so the drop's animation doesn't stall.
        let stream = self.stream
        let started = await Task.detached(priority: .userInitiated) {
            Self.makeEngine(feeding: stream)
        }.value
        guard let started else { return false }
        guard ticket == generation, running == nil else {
            Task.detached(priority: .userInitiated) { Self.tearDown(started) }
            return ticket == generation
        }
        running = started
        return true
    }

    func stop() {
        generation += 1
        stream.reset()
        guard let running else { return }
        self.running = nil
        Task.detached(priority: .userInitiated) { Self.tearDown(running) }
    }

    func levels() -> SiriGlassLevels { stream.levels() }

    nonisolated private static func makeEngine(feeding stream: VoiceStream) -> Running? {
        let session = AVAudioSession.sharedInstance()
        let previous = SessionState(category: session.category, mode: session.mode, options: session.categoryOptions)
        do {
            // Keep AirPods (or any Bluetooth) playback where it is; listen
            // through the phone's microphone, alongside other audio.
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            log.error("SiriGlass couldn't start the audio session: \(error.localizedDescription, privacy: .public)")
            restore(previous)
            return nil
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            restore(previous)
            return nil
        }
        // Off the main actor: the tap runs on the audio engine's own thread.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.1), format: format) { buffer, _ in
            stream.analyze(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            restore(previous)
            return nil
        }
        return Running(engine: engine, previous: previous)
    }

    nonisolated private static func tearDown(_ running: Running) {
        running.engine.inputNode.removeTap(onBus: 0)
        running.engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        restore(running.previous)
    }

    nonisolated private static func restore(_ state: SessionState) {
        try? AVAudioSession.sharedInstance().setCategory(state.category, mode: state.mode, options: state.options)
    }
}
