//
//  SiriGlass.swift
//  SiriGlass
//
//  iOS 27's Siri, for your app: a drop of Liquid Glass that pours out of
//  the Dynamic Island, listens, and lights up with the voice it hears.
//

import SwiftUI

/// What the drop is doing.
public enum SiriGlassState: String, Sendable, Hashable, CaseIterable {
    /// Home: tucked back into the Dynamic Island. Set it to send the drop
    /// away; it pulls back in with a small swell.
    case idle
    /// Out and listening: the light inside dances with the audio.
    case listening
    /// Out and thinking: the light gathers into one lens and swirls slowly
    /// until you change the state.
    case thinking
}

extension View {
    /// Pours the Siri drop out of the Dynamic Island over this view.
    ///
    /// Set `state` to ``SiriGlassState/listening`` and the drop drips out of
    /// the island, hangs there, and lights up with what it hears. Set it to
    /// ``SiriGlassState/thinking`` and the light gathers and swirls; set it
    /// to ``SiriGlassState/idle`` and it goes home.
    ///
    /// ```swift
    /// @State private var siri = SiriGlassState.idle
    ///
    /// var body: some View {
    ///     ContentView()
    ///         .siriGlass($siri)
    /// }
    /// ```
    ///
    /// Listening to the ``SiriGlassAudio/microphone`` (the default) or a
    /// ``SiriGlassAudio/file(_:muted:)``, the drop behaves like Siri: a beat
    /// after the voice stops it moves itself to `.thinking`, and if nobody
    /// speaks for 14 seconds it goes back to `.idle`. It writes those changes
    /// to `state`; from `.thinking` on, the next change is yours.
    ///
    /// The drop is drawn over this view, never into it, so it works over any
    /// content: lists, maps, video, UIKit. On iOS 26 its glass is the
    /// system's Liquid Glass and bends whatever is behind it; earlier, a thin
    /// material stands in. It doesn't take touches.
    ///
    /// Apply it to a view that reaches the top of the screen, such as your
    /// root view: the drop is placed in window coordinates at the Dynamic
    /// Island, so a view lower down still shows it at the top, unless
    /// something clips it (a sheet, a scroll view). On a phone without an
    /// island, on iPad and in landscape it pours from the top centre.
    ///
    /// - Parameters:
    ///   - state: What the drop is doing. The drop writes `.thinking` and
    ///     `.idle` back when it decides by itself that listening is over.
    ///   - audio: What it listens to. The microphone needs
    ///     `NSMicrophoneUsageDescription` in your app's Info.plist.
    public func siriGlass(_ state: Binding<SiriGlassState>, audio: SiriGlassAudio = .microphone) -> some View {
        overlay(alignment: .topLeading) {
            DropView(placement: .island, binding: state, fixed: state.wrappedValue, audio: audio)
        }
    }
}
