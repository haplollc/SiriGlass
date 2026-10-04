//
//  DemoConfig.swift
//  SiriGlassDemo
//
//  How the demo was launched. With none of these it is the interactive
//  demo: tap to talk to the microphone. The UI tests and the recording
//  scripts set them with the launch environment.
//
//    SIRIGLASS_STAGE=iPhone   open on the home screen instead of the orb
//    SIRIGLASS_AUDIO=<file>   listen to this voice file instead of the mic
//    SIRIGLASS_MUTE=1         …without playing it
//    SIRIGLASS_PROBE=1        publish the voice level for the UI tests
//    SIRIGLASS_DEMO=1         play the scripted take (reacting to the file)
//    SIRIGLASS_CUES=…         its beats: "summon=0.45,switch=4.67,think=8.79,dismiss=9.89"
//                             (switch moves the take to the other stage)
//    SIRIGLASS_PACE=10        run the take ten times slower, for recording
//    SIRIGLASS_HOLD=6         hold its first frame for six real seconds
//    SIRIGLASS_FREEZE=3.2     hold it at 3.2 s, for stills
//    SIRIGLASS_STAMP=1        stamp the clock in the corner (on in a take)
//    SIRIGLASS_DEBUG=1        draw the glass alone
//

import Foundation
@_spi(Recording) import SiriGlass

enum DemoStage: String, CaseIterable, Identifiable {
    case orb, iPhone

    var id: String { rawValue }
    var title: String { self == .orb ? "Orb" : "iPhone" }
    var other: DemoStage { self == .orb ? .iPhone : .orb }
}

struct DemoConfig {
    struct Cues {
        var summon = 0.45
        var switchAt: Double?
        var think = 7.4
        var dismiss = 8.5
    }

    let scripted: Bool
    let voice: URL?
    let muted: Bool
    let stage: DemoStage
    let pace: Double
    let hold: Double
    let freeze: Double?
    let probe: Bool
    let stamp: Bool
    let glassOnly: Bool
    let cues: Cues

    init(environment env: [String: String] = ProcessInfo.processInfo.environment) {
        scripted = env["SIRIGLASS_DEMO"] == "1"
        voice = env["SIRIGLASS_AUDIO"].map { URL(fileURLWithPath: $0) }
        muted = env["SIRIGLASS_MUTE"] == "1"
        stage = env["SIRIGLASS_STAGE"].flatMap(DemoStage.init(rawValue:)) ?? .orb
        pace = env["SIRIGLASS_PACE"].flatMap(Double.init) ?? 1
        hold = env["SIRIGLASS_HOLD"].flatMap(Double.init) ?? 0
        freeze = env["SIRIGLASS_FREEZE"].flatMap(Double.init)
        probe = env["SIRIGLASS_PROBE"] == "1"
        stamp = scripted || env["SIRIGLASS_STAMP"] == "1"
        glassOnly = env["SIRIGLASS_DEBUG"] == "1"
        var cues = Cues()
        for cue in (env["SIRIGLASS_CUES"] ?? "").split(separator: ",") {
            let parts = cue.split(separator: "=")
            guard parts.count == 2, let value = Double(parts[1]) else { continue }
            switch parts[0] {
            case "summon": cues.summon = value
            case "switch": cues.switchAt = value
            case "think": cues.think = value
            case "dismiss": cues.dismiss = value
            default: break
            }
        }
        self.cues = cues
    }

    /// What the drops listen to: the voice file if there is one, else the
    /// microphone.
    var audio: SiriGlassAudio {
        voice.map { .file($0, muted: muted) } ?? .microphone
    }

    /// When each stage's drop does what, in a scripted take.
    func cues(for stage: DemoStage) -> SiriGlassCues {
        if let switchAt = cues.switchAt {
            // The first stage's drop leaves at the tap; the other's comes out
            // once the screens have crossed, and finishes the take.
            if stage == self.stage { return SiriGlassCues(listen: cues.summon, idle: switchAt) }
            return SiriGlassCues(listen: switchAt + 0.6, think: cues.think, idle: cues.dismiss)
        }
        guard stage == self.stage else { return SiriGlassCues() }
        return SiriGlassCues(listen: cues.summon, think: cues.think, idle: cues.dismiss)
    }
}
