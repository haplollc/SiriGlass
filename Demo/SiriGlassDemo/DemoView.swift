//
//  DemoView.swift
//  SiriGlassDemo
//
//  Two stages, picked at the bottom. The orb: `SiriGlassOrb`, a drop of
//  Liquid Glass alone in the middle of a white screen. The iPhone: a home
//  screen with `.siriGlass`, where the drop pours out of the Dynamic
//  Island. Tap anywhere and it listens; talk and the light dances with your
//  voice; stop and it thinks, then slips away.
//
//  Everything that moves is a function of one clock (the picker's thumb
//  and the screens' crossfade included), so a scripted take slowed down for
//  recording keeps every motion in step. A take stamps its clock as a 4 x 4
//  barcode in the top-left corner, which a device frame's rounded corner
//  hides (Scripts/sync.py reads it).
//

import SwiftUI
@_spi(Recording) import SiriGlass

struct DemoView: View {
    let config: DemoConfig
    /// The scripted take, when recording.
    let take: SiriGlassTake?

    @State private var stage: DemoStage
    @State private var orbState = SiriGlassState.idle
    @State private var phoneState = SiriGlassState.idle
    /// A stage change under way: where from, and when.
    @State private var switchFrom: DemoStage?
    @State private var switchAt: Date?
    @State private var probe = SiriGlassProbe()

    init(config: DemoConfig, take: SiriGlassTake?) {
        self.config = config
        self.take = take
        _stage = State(initialValue: config.stage)
    }

    var body: some View {
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top
            GeometryReader { geo in
                TimelineView(.animation) { context in
                    scene(size: geo.size, safeTop: safeTop, date: context.date, clock: take?.clock(at: context.date))
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.white)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.light)
        .onChange(of: orbState) { _, state in thinkThenLeave(state, on: .orb) }
        .onChange(of: phoneState) { _, state in thinkThenLeave(state, on: .iPhone) }
    }

    @ViewBuilder
    private func scene(size: CGSize, safeTop: CGFloat, date: Date, clock: Double?) -> some View {
        let island = SiriGlassIsland.frame(windowSize: size, safeAreaTop: safeTop)
        let mix = stageMix(date: date, clock: clock)
        let pickerY = HomeLayout(size: size).searchY
        ZStack(alignment: .topLeading) {
            stages(size: size, island: island, mix: mix, clock: clock)
            StagePicker(mix: mix, tap: tap(at: clock)) { select($0) }
                .position(x: size.width / 2, y: pickerY)
            if take == nil && activeState == .idle && switchAt == nil {
                Text("Tap anywhere to talk")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(mix > 0.5 ? Color.white : Color.black.opacity(0.35))
                    .shadow(color: .black.opacity(mix > 0.5 ? 0.3 : 0), radius: 2, y: 1)
                    .position(x: size.width / 2, y: pickerY - 50)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if config.stamp, let clock {
                ClockStamp(clock: clock)
            }
            if config.probe {
                // The drop's voice level, for the UI tests.
                Text(String(format: "%.3f", probe.loudness))
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("siriGlass.level")
            }
        }
    }

    private func stages(size: CGSize, island: CGRect, mix: Double, clock: Double?) -> some View {
        // The orb at the size it has on a Pro Max, smaller on narrower
        // screens, with a little room to swell.
        let scale = min(2.0, size.width * 0.78 / 170)
        let state: SiriGlassState
        if let clock, take != nil {
            state = config.cues(for: mix > 0.5 ? .iPhone : .orb).state(at: clock)
        } else {
            state = activeState
        }
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.white
                SiriGlassOrb(state: $orbState, audio: config.audio)
                    .frame(width: 170 * scale * 1.08, height: 126 * scale * 1.08)
                    .position(x: size.width / 2, y: size.height * 0.42)
            }
            .siriGlassTake(take, cues: config.cues(for: .orb))
            .siriGlassProbe(stage == .orb ? probe : nil)
            .opacity(max(1 - mix, 0.001))

            HomeScreen(size: size, island: island)
                .siriGlass($phoneState, audio: config.audio)
                .siriGlassTake(take, cues: config.cues(for: .iPhone))
                .siriGlassProbe(stage == .iPhone ? probe : nil)
                .opacity(max(mix, 0.001))

            // The island itself, on both stages, as on the phone. On a real
            // phone the hardware covers this.
            Capsule()
                .fill(.black)
                .frame(width: island.width, height: island.height)
                .position(x: island.midX, y: island.midY)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Siri")
        .accessibilityValue(Self.mood(state))
        .accessibilityHint(state == .idle ? "Double-tap to talk to Siri" : "Double-tap to send Siri away")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("siriGlass.stage")
    }

    private static func mood(_ state: SiriGlassState) -> String {
        switch state {
        case .idle: "Asleep"
        case .listening: "Listening"
        case .thinking: "Thinking"
        }
    }

    // MARK: - Interactive

    private var activeState: SiriGlassState {
        get { stage == .orb ? orbState : phoneState }
        nonmutating set {
            if stage == .orb { orbState = newValue } else { phoneState = newValue }
        }
    }

    private func toggle() {
        guard take == nil, switchAt == nil else { return }
        activeState = activeState == .idle ? .listening : .idle
    }

    /// The drop goes home, the screens cross, and it comes back out on the
    /// new stage, listening.
    private func select(_ new: DemoStage) {
        guard take == nil, new != stage, switchAt == nil else { return }
        activeState = .idle
        switchFrom = stage
        switchAt = .now
        stage = new
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            activeState = .listening
            try? await Task.sleep(for: .seconds(0.85))
            switchAt = nil
            switchFrom = nil
        }
    }

    /// A real assistant would answer here; the demo thinks for a moment
    /// and sends the drop home.
    private func thinkThenLeave(_ state: SiriGlassState, on stage: DemoStage) {
        guard take == nil, state == .thinking else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.15))
            if stage == .orb, orbState == .thinking { orbState = .idle }
            if stage == .iPhone, phoneState == .thinking { phoneState = .idle }
        }
    }

    // MARK: - The clock

    /// 0 the orb … 1 the iPhone, easing across while a change is under way.
    private func stageMix(date: Date, clock: Double?) -> Double {
        func value(_ s: DemoStage) -> Double { s == .iPhone ? 1 : 0 }
        if let clock, take != nil {
            guard let at = config.cues.switchAt else { return value(config.stage) }
            let u = Self.ease((clock - at - 0.12) / 0.55)
            return value(config.stage) + (value(config.stage.other) - value(config.stage)) * u
        }
        guard let switchAt, let switchFrom else { return value(stage) }
        let u = Self.ease((date.timeIntervalSince(switchAt) - 0.12) / 0.55)
        return value(switchFrom) + (value(stage) - value(switchFrom)) * u
    }

    /// A scripted take's tap on the picker: 0…1 while it plays.
    private func tap(at clock: Double?) -> Double? {
        guard let clock, let at = config.cues.switchAt else { return nil }
        let u = (clock - (at - 0.18)) / 0.5
        return u >= 0 && u <= 1 ? u : nil
    }

    private static func ease(_ t: Double) -> Double {
        let u = min(max(t, 0), 1)
        return u * u * (3 - 2 * u)
    }
}
