//
//  ReadmeExamples.swift
//  SiriGlassTests
//
//  Every snippet in README.md, compiled against the package as it ships,
//  so the README can't drift from the API. Nothing here runs; the stand-ins
//  at the bottom play the parts of the reader's own app.
//

import AVFoundation
import Speech
import SwiftUI
import SiriGlass

// MARK: Quick start

private struct QuickStart: View {
    @State private var siri = SiriGlassState.idle

    var body: some View {
        NavigationStack {
            InboxView()
                .toolbar {
                    Button("Ask", systemImage: "waveform") {
                        siri = siri == .idle ? .listening : .idle
                    }
                }
        }
        .siriGlass($siri)
    }
}

// MARK: Two ways to show it

private struct OnItsOwn: View {
    @State private var siri = SiriGlassState.idle

    var body: some View {
        SiriGlassOrb(state: $siri)
            .frame(width: 320, height: 240)
            .onTapGesture { siri = siri == .idle ? .listening : .idle }
    }
}

// MARK: States

private struct HandOff: View {
    @State private var siri = SiriGlassState.idle
    @State private var reply = ""
    let assistant = Assistant()
    let transcript = ""

    var body: some View {
        HomeView()
            .siriGlass($siri)
            .onChange(of: siri) { _, state in
                guard state == .thinking else { return }
                Task {
                    reply = await assistant.respond(to: transcript)
                    siri = .idle
                }
            }
    }
}

// MARK: What it listens to

private struct Sources: View {
    @State private var siri = SiriGlassState.idle
    @State private var voice = SiriGlassAudio.Feed()
    let url = URL(fileURLWithPath: "/dev/null")

    var body: some View {
        VStack {
            HomeView().siriGlass($siri)                                      // the microphone (the default)
            HomeView().siriGlass($siri, audio: .file(url))                   // a recording, played aloud
            HomeView().siriGlass($siri, audio: .file(url, muted: true))      // reacts to it silently
            HomeView().siriGlass($siri, audio: .feed(voice))                 // audio you already have
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer, meter: Meter) {
        // In your input tap, on any thread:
        voice.send(buffer)

        voice.send(SiriGlassLevels(loudness: meter.level))
        voice.send(SiriGlassLevels(loudness: 0.8, low: 0.9, mid: 0.6, high: 0.3))
    }
}

// MARK: Recipes

private func oneTap(engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest, voice: SiriGlassAudio.Feed) {
    let input = engine.inputNode
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
        request.append(buffer)   // SFSpeechAudioBufferRecognitionRequest
        voice.send(buffer)       // SiriGlassAudio.Feed
    }
}

private func answerGlows(engine: AVAudioEngine, voice: SiriGlassAudio.Feed) {
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
        voice.send(buffer)
    }
}

#Preview {
    HomeView()
        .siriGlass(.constant(.listening), audio: .file(Bundle.main.url(forResource: "hello", withExtension: "m4a")!))
}

private struct HoldToTalk: View {
    @State private var siri = SiriGlassState.idle

    var body: some View {
        Image(systemName: "mic.fill")
            .onLongPressGesture(minimumDuration: 0.2) {
            } onPressingChanged: { pressing in
                siri = pressing ? .listening : .thinking
            }
    }
}

private struct AssistantCard: View {
    let siri: SiriGlassState

    var body: some View {
        VStack(spacing: 16) {
            SiriGlassOrb(state: siri)
                .frame(width: 200, height: 150)
            Text(siri == .thinking ? "Thinking…" : "Listening…")
                .font(.headline)
        }
        .padding(32)
        .background(.background, in: .rect(cornerRadius: 28))
    }
}

// MARK: Accessibility

private func announce() {
    AccessibilityNotification.Announcement("Listening").post()
}

// MARK: Stand-ins for the reader's app

private struct InboxView: View {
    var body: some View { List { Text("Inbox") } }
}

private struct HomeView: View {
    var body: some View { Color.blue }
}

private struct Assistant: Sendable {
    func respond(to transcript: String) async -> String { transcript }
}

private struct Meter {
    var level: Float = 0
}
