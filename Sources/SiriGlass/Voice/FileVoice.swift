//
//  FileVoice.swift
//  SiriGlass
//
//  `SiriGlassAudio.file`: the file is analysed once, off the main thread,
//  and played from the moment the drop starts listening (unless muted). The
//  drop reads the analysis at the same instant the player is at, so what
//  you hear is what moves the light.
//

import AVFoundation
import os

@MainActor
final class FileVoice {
    let url: URL
    let muted: Bool
    private var player: AVAudioPlayer?
    private static var tracks: [URL: VoiceTrack] = [:]
    private static var loading: Set<URL> = []
    nonisolated private static let log = Logger(subsystem: "SiriGlass", category: "file")

    init(url: URL, muted: Bool) {
        self.url = url
        self.muted = muted
        Self.prepare(url)
    }

    /// Starts analysing the file in the background, once per file.
    static func prepare(_ url: URL) {
        guard tracks[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        Task.detached(priority: .userInitiated) {
            let track: VoiceTrack?
            do {
                track = try VoiceTrack(url: url)
            } catch {
                log.error("SiriGlass couldn't read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                track = nil
            }
            await MainActor.run {
                loading.remove(url)
                if let track { tracks[url] = track }
            }
        }
    }

    /// Plays the file `delay` seconds from now.
    func play(after delay: Double) {
        guard !muted else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play(atTime: player.deviceCurrentTime + delay)
            self.player = player
        } catch {
            Self.log.error("SiriGlass couldn't play \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// What the file sounds like `time` seconds in (silence until the
    /// analysis is ready).
    func levels(at time: Double) -> SiriGlassLevels {
        Self.tracks[url]?.drive(at: time).levels ?? SiriGlassLevels()
    }

    var isPlaying: Bool { player?.isPlaying ?? false }
}
