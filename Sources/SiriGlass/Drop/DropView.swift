//
//  DropView.swift
//  SiriGlass
//
//  Draws one drop. The glass is the system's own Liquid Glass (iOS 26),
//  in the drop's outline, so it bends whatever is behind it, SwiftUI or
//  UIKit, live; the ink and light are SiriGlass.metal, laid over it. Before
//  iOS 26 a thin material stands in for the glass.
//
//  The drop is an overlay: nothing behind it is re-rendered or flattened,
//  so lists, maps, text fields and video keep working under it.
//

import SwiftUI

struct DropView: View {
    enum Placement { case island, orb }

    let placement: Placement
    let binding: Binding<SiriGlassState>?
    let fixed: SiriGlassState
    let audio: SiriGlassAudio

    @Environment(\.siriGlassTake) private var take
    @Environment(\.siriGlassProbe) private var probe
    @Environment(\.colorScheme) private var colorScheme

    @State private var engine = DropEngine()
    /// True once the drop is home and still: the timeline stops ticking.
    @State private var resting = true
    @State private var window: WindowMetrics?

    private var requested: SiriGlassState { binding?.wrappedValue ?? fixed }

    var body: some View {
        let paused = take == nil && resting && requested == .idle
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
                drop(at: context.date, in: proxy)
            }
        }
        .background {
            if placement == .island {
                WindowReader { window = $0 }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onDisappear {
            engine.stop()
            resting = true
        }
    }

    @ViewBuilder
    private func drop(at date: Date, in proxy: GeometryProxy) -> some View {
        let space = layout(in: proxy)
        let backdrop = placement == .orb ? (colorScheme == .light ? 1.0 : 0.35) : 0
        let out = engine.frame(at: date, requested: requested, audio: audio, writable: binding != nil,
                               take: take, layout: space.layout, backdrop: backdrop)
        let _ = commit(out)
        ZStack(alignment: .topLeading) {
            if placement == .orb {
                OrbShadow(frame: out.frame, strength: backdrop)
            }
            DropGlass(points: out.outline)
            Rectangle()
                .fill(.white)
                .colorEffect(out.frame.shader)
        }
        .frame(width: space.size.width, height: space.size.height)
        .offset(space.offset)
    }

    /// Where the drop goes. Under the island its layer covers the top of the
    /// window, wherever this view sits in it; as an orb, this view's bounds.
    private func layout(in proxy: GeometryProxy) -> (layout: DropEngine.Layout, size: CGSize, offset: CGSize) {
        switch placement {
        case .island:
            let global = proxy.frame(in: .global)
            let metrics = window ?? WindowMetrics(size: CGSize(width: global.maxX, height: global.maxY),
                                                  safeAreaTop: proxy.safeAreaInsets.top + global.minY, isPhone: true)
            let island = DropGeometry.island(in: metrics)
            let size = CGSize(width: metrics.size.width, height: DropGeometry.reach)
            return (.island(island), size, CGSize(width: -global.minX, height: -global.minY))
        case .orb:
            let size = proxy.size
            // The orb keeps the drop's proportions, with room to swell.
            let scale = max(min(size.width / DropGeometry.size.width, size.height / DropGeometry.size.height) / 1.08, 0.05)
            return (.orb(centre: CGPoint(x: size.width / 2, y: size.height / 2), scale: scale), size, .zero)
        }
    }

    /// Hands what the frame decided back to SwiftUI, after the update.
    private func commit(_ out: DropEngine.Output) {
        probe?.record(out, state: engine.mode)
        if let request = out.request, let binding {
            DispatchQueue.main.async {
                if binding.wrappedValue == request.from { binding.wrappedValue = request.to }
            }
        }
        if out.resting != resting {
            let now = out.resting
            DispatchQueue.main.async { resting = now }
        }
    }
}

/// The drop's glass: Liquid Glass in its outline, or a material before
/// iOS 26. Always in the hierarchy, empty while the drop is home, so it
/// never has to be inserted mid-animation.
struct DropGlass: View {
    let points: [CGPoint]

    var body: some View {
        let outline = DropOutline(points: points)
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.clear, in: outline)
        } else {
            outline.fill(.ultraThinMaterial)
        }
    }
}

/// The soft shadow an orb casts on a light backdrop.
struct OrbShadow: View {
    let frame: DropFrame
    let strength: Double

    var body: some View {
        let scale = frame.scale
        let w = Double(frame.drop.z) * scale, h = Double(frame.drop.w) * scale
        let opacity = 0.24 * strength * Double(frame.presence)
        Ellipse()
            .fill(RadialGradient(colors: [.black.opacity(opacity), .black.opacity(opacity * 0.4), .black.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: w * 0.86))
            .frame(width: w * 1.72, height: h * 0.24)
            .position(x: Double(frame.drop.x), y: Double(frame.drop.y) + h * 1.13)
            .opacity(frame.isVisible ? 1 : 0)
    }
}
