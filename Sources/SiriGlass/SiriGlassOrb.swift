//
//  SiriGlassOrb.swift
//  SiriGlass
//
//  The drop on its own: the same glass, ink and light, centred in its
//  frame, blooming from a point instead of pouring out of the island.
//

import SwiftUI

/// The Siri drop on its own, as an orb.
///
/// ```swift
/// @State private var siri = SiriGlassState.idle
///
/// SiriGlassOrb(state: $siri)
///     .frame(width: 320, height: 240)
///     .onTapGesture { siri = siri == .idle ? .listening : .idle }
/// ```
///
/// The orb fills the frame you give it, keeping the drop's proportions
/// (about 4:3), and blooms from the middle when it starts listening. On a
/// light backdrop it darkens its rim and casts a soft shadow below itself,
/// outside its frame. While idle it draws nothing.
public struct SiriGlassOrb: View {
    private let binding: Binding<SiriGlassState>?
    private let value: SiriGlassState
    private let audio: SiriGlassAudio

    /// An orb that listens like Siri: with the microphone or a file it
    /// moves itself to `.thinking` when the voice stops, and to `.idle` if
    /// nobody speaks, writing the change to `state`.
    public init(state: Binding<SiriGlassState>, audio: SiriGlassAudio = .microphone) {
        binding = state
        value = state.wrappedValue
        self.audio = audio
    }

    /// An orb that shows `state` and never changes it.
    public init(state: SiriGlassState, audio: SiriGlassAudio = .microphone) {
        binding = nil
        value = state
        self.audio = audio
    }

    public var body: some View {
        DropView(placement: .orb, binding: binding, fixed: value, audio: audio)
    }
}
