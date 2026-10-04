//
//  StagePicker.swift
//  SiriGlassDemo
//
//  A segmented control in glass, Orb | iPhone. Its thumb follows the
//  demo's clock rather than an animation of its own, so it slides in step
//  with the screens in a slowed-down recording too.
//

import SwiftUI

struct StagePicker: View {
    /// 0 on Orb … 1 on iPhone.
    let mix: Double
    /// A scripted tap on iPhone, 0…1 while it plays.
    var tap: Double?
    let select: (DemoStage) -> Void

    private let width = 224.0, height = 40.0, inset = 4.0

    var body: some View {
        let segment = (width - inset * 2) / 2
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                .frame(width: segment, height: height - inset * 2)
                .offset(x: inset + segment * mix)
            HStack(spacing: 0) {
                ForEach(DemoStage.allCases) { stage in
                    let on = stage == .iPhone ? mix : 1 - mix
                    Text(stage.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45 + 0.45 * on))
                        .frame(width: segment, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { select(stage) }
                        .accessibilityAddTraits(on > 0.5 ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("siriGlass.stage.\(stage.rawValue)")
                }
            }
            .padding(.horizontal, inset)
            if let tap {
                // A finger's touch: a soft disc that swells and fades.
                Circle()
                    .fill(Color.black.opacity(0.14 * (1 - tap)))
                    .frame(width: 26 + 30 * tap, height: 26 + 30 * tap)
                    .position(x: inset + segment * 1.5, y: height / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .background {
            if #available(iOS 26, *) {
                Color.clear.glassEffect(.regular, in: .capsule)
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where Siri is shown")
    }
}

/// The take's clock in 4 ms steps as 16 black-or-white cells, read back
/// from the recording to time it and lay the voice under it.
struct ClockStamp: View {
    let clock: Double

    var body: some View {
        let value = Int((max(clock, 0) * 250).rounded(.down)) & 0xFFFF
        Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 12, height: 12)), with: .color(.white))
            for bit in 0..<16 where value & (1 << bit) != 0 {
                let cell = CGRect(x: Double(bit % 4) * 3, y: Double(bit / 4) * 3, width: 3, height: 3)
                context.fill(Path(cell), with: .color(.black))
            }
        }
        .frame(width: 12, height: 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
