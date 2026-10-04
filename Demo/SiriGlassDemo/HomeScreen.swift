//
//  HomeScreen.swift
//  SiriGlassDemo
//
//  A home screen for the drop to pour over: a pale silver wallpaper that
//  deepens into a soft dawn toward the dock, the status bar beside the
//  island, and an iOS 27 grid at its measured spacing (fractions of the
//  screen's width, from iOS Eras). The icons are drawn here from gradients
//  and SF Symbols, in each app's current colours.
//

import SwiftUI

/// The iOS 27 home screen's measurements, as fractions of the width.
struct HomeLayout {
    let size: CGSize
    private var w: Double { size.width }
    private var h: Double { size.height }

    var iconEdge: Double { w * 0.1593 }
    var dockIconEdge: Double { w * 0.1589 }
    var labelSize: Double { w * 0.0300 }

    func iconCentre(_ index: Int) -> CGPoint {
        let column = Double(index % 4), row = Double(index / 4)
        return CGPoint(x: w * (0.1552 + 0.2300 * column), y: w * (0.2245 + 0.2492 * row) + iconEdge / 2)
    }

    func dockCentre(_ index: Int) -> CGPoint {
        CGPoint(x: w * (0.1685 + 0.2211 * Double(index)), y: h - w * 0.1700)
    }

    var dockFrame: CGRect {
        let inset = w * 0.0405, top = h - w * 0.2995, bottom = h - w * 0.0410
        return CGRect(x: inset, y: top, width: w - inset * 2, height: bottom - top)
    }

    var dockCorner: Double { w * 0.096 }

    /// Where the Search pill sits; the demo's stage picker goes there.
    var searchY: Double { h - w * 0.3878 }
}

struct HomeScreen: View {
    let size: CGSize
    let island: CGRect

    static let page = [
        "FaceTime", "Wallet", "Clock", "Weather",
        "Calendar", "Photos", "Camera", "Mail",
        "Maps", "Notes", "Reminders", "Stocks",
        "Siri", "News", "Books", "App Store",
        "Games", "TV", "Health", "Home",
        "Settings", "Files", "Shortcuts", "Passwords",
    ]
    static let dock = ["Phone", "Safari", "Messages", "Music"]

    var body: some View {
        let layout = HomeLayout(size: size)
        ZStack(alignment: .topLeading) {
            Wallpaper()
            ForEach(Array(Self.page.enumerated()), id: \.offset) { index, name in
                AppIcon(name: name, edge: layout.iconEdge, labelSize: layout.labelSize, labelled: true)
                    .position(layout.iconCentre(index))
            }
            Dock(layout: layout)
            StatusBar(width: size.width, island: island)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// The dock: live Liquid Glass and four icons.
private struct Dock: View {
    let layout: HomeLayout

    var body: some View {
        let frame = layout.dockFrame
        let shape = RoundedRectangle(cornerRadius: layout.dockCorner, style: .continuous)
        ZStack(alignment: .topLeading) {
            Color.clear
            Group {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            ForEach(Array(HomeScreen.dock.enumerated()), id: \.offset) { index, name in
                AppIcon(name: name, edge: layout.dockIconEdge, labelSize: 0, labelled: false)
                    .position(layout.dockCentre(index))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Icons

struct AppIcon: View {
    let name: String
    let edge: Double
    let labelSize: Double
    let labelled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: edge * 0.27, style: .continuous)
        let colours = Self.colours[name] ?? (0x8E8E93, 0x636366)
        ZStack {
            shape.fill(LinearGradient(colors: [hex(colours.0), hex(colours.1)], startPoint: .top, endPoint: .bottom))
            Glyph(name: name, edge: edge)
            // iOS 26's glass rim: light along the top-left edge.
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), .white.opacity(0.45)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: max(0.8, edge * 0.022))
        }
        .frame(width: edge, height: edge)
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1.5)
        .overlay(alignment: .top) {
            if labelled {
                Text(name)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 1.3, y: 0.8)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: edge + edge * 0.06)
            }
        }
    }

    /// Each app's tile, top and bottom (iOS 27 colours, from iOS Eras).
    static let colours: [String: (UInt32, UInt32)] = [
        "FaceTime": (0x82EC7C, 0x62CD53), "Wallet": (0x1F1E1F, 0x0E0E0E), "Clock": (0xFEFEFE, 0xF6F6F6),
        "Weather": (0x349EFF, 0x1B73DA), "Calendar": (0xFEFEFE, 0xF7F7F7), "Photos": (0xFFFFFF, 0xE8E9EA),
        "Camera": (0xDADADA, 0xBEBEBE), "Mail": (0x57BEF4, 0x1D74FD), "Maps": (0xEFEFEF, 0xE2E2E2),
        "Notes": (0xF6F6F6, 0xECECEC), "Reminders": (0xFEFEFE, 0xEBEBEB), "Stocks": (0x1F1F1F, 0x161616),
        "Siri": (0xFFFFFF, 0xF3F3F4), "News": (0xFEFEFE, 0xF5F4F5), "Books": (0xFF8A0B, 0xFE7200),
        "App Store": (0x3F8EF1, 0x3162E2), "Games": (0xEC5847, 0xE93D39), "TV": (0x1F1E1F, 0x0F0F0F),
        "Health": (0xFFFEFE, 0xE8E9E7), "Home": (0xFFFFFF, 0xF4F5F4), "Settings": (0x9C9C9F, 0x78787D),
        "Files": (0xFEFEFE, 0xF6F5F5), "Shortcuts": (0x421D8F, 0x29157A), "Passwords": (0x1F1F1F, 0x0F0F0F),
        "Phone": (0x54EF6E, 0x25C041), "Safari": (0xF4F5F7, 0xECF0F1), "Messages": (0x54EF6E, 0x25C041),
        "Music": (0xFF4E6F, 0xFF002D),
    ]
}

func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: alpha)
}

/// The art on each tile.
private struct Glyph: View {
    let name: String
    let edge: Double

    var body: some View {
        switch name {
        case "FaceTime": symbol("video.fill", .white, 0.42)
        case "Phone": symbol("phone.fill", .white, 0.46)
        case "Messages": symbol("message.fill", .white, 0.5)
        case "Music": symbol("music.note", .white, 0.5, weight: .semibold)
        case "Mail": symbol("envelope.fill", .white, 0.44)
        case "Weather":
            Image(systemName: "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: edge * 0.48))
        case "Camera": symbol("camera.fill", hex(0x3A3A3C), 0.44)
        case "Books": symbol("book.fill", .white, 0.44)
        case "Games": symbol("gamecontroller.fill", .white, 0.42)
        case "TV": symbol("tv.fill", .white, 0.42)
        case "News": symbol("newspaper.fill", hex(0xFA2D48), 0.46)
        case "Health": symbol("heart.fill", hex(0xFF3B5C), 0.46)
        case "Home": symbol("house.fill", hex(0xFF9500), 0.46)
        case "Settings": symbol("gearshape.fill", hex(0xE9E9EE), 0.62)
        case "Files": symbol("folder.fill", hex(0x1E8EF7), 0.48)
        case "Passwords": symbol("key.fill", hex(0x34C3B5), 0.46)
        case "Safari": symbol("safari.fill", hex(0x1E7CF2), 0.66)
        case "Wallet": WalletArt(edge: edge)
        case "Clock": ClockArt(edge: edge)
        case "Calendar": CalendarArt(edge: edge)
        case "Photos": PhotosArt(edge: edge)
        case "Maps": MapsArt(edge: edge)
        case "Notes": NotesArt(edge: edge)
        case "Reminders": RemindersArt(edge: edge)
        case "Stocks": StocksArt(edge: edge)
        case "Siri": SiriArt(edge: edge)
        case "App Store": AppStoreArt(edge: edge)
        case "Shortcuts": ShortcutsArt(edge: edge)
        default: EmptyView()
        }
    }

    private func symbol(_ name: String, _ colour: Color, _ size: Double, weight: Font.Weight = .medium) -> some View {
        Image(systemName: name)
            .font(.system(size: edge * size, weight: weight))
            .foregroundStyle(colour)
    }
}

private struct WalletArt: View {
    let edge: Double
    var body: some View {
        let colours: [UInt32] = [0xFF9F0A, 0x34C759, 0x0A84FF, 0xFF453A]
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: edge * 0.05, style: .continuous)
                    .fill(hex(colours[i]))
                    .frame(width: edge * 0.62, height: edge * 0.3)
                    .offset(y: -edge * 0.2 + Double(i) * edge * 0.08)
            }
            RoundedRectangle(cornerRadius: edge * 0.07, style: .continuous)
                .fill(hex(0x2C2C2E))
                .frame(width: edge * 0.66, height: edge * 0.3)
                .offset(y: edge * 0.15)
        }
    }
}

private struct ClockArt: View {
    let edge: Double
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width * 0.42
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                let long = i % 3 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + sin(a) * r * (long ? 0.78 : 0.84), y: c.y - cos(a) * r * (long ? 0.78 : 0.84)))
                tick.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.95, y: c.y - cos(a) * r * 0.95))
                context.stroke(tick, with: .color(hex(0x1C1C1E, long ? 1 : 0.5)), lineWidth: size.width * (long ? 0.035 : 0.02))
            }
            func hand(_ angle: Double, _ length: Double, _ width: Double, _ colour: Color) {
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + sin(angle) * r * length, y: c.y - cos(angle) * r * length))
                context.stroke(p, with: .color(colour), style: StrokeStyle(lineWidth: size.width * width, lineCap: .round))
            }
            hand((10 + 9.0 / 60) / 12 * 2 * .pi, 0.5, 0.05, hex(0x1C1C1E))     // 10:09
            hand(9.0 / 60 * 2 * .pi, 0.78, 0.04, hex(0x1C1C1E))
            hand(32.0 / 60 * 2 * .pi, 0.82, 0.015, hex(0xFF9500))
            context.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(hex(0xFF9500)))
        }
        .frame(width: edge, height: edge)
    }
}

private struct CalendarArt: View {
    let edge: Double
    var body: some View {
        VStack(spacing: -edge * 0.04) {
            Text("TUE")
                .font(.system(size: edge * 0.15, weight: .semibold))
                .foregroundStyle(hex(0xFF3B30))
            Text("9")
                .font(.system(size: edge * 0.46, weight: .light))
                .foregroundStyle(hex(0x1C1C1E))
        }
    }
}

private struct PhotosArt: View {
    let edge: Double
    var body: some View {
        let colours: [UInt32] = [0xFF9500, 0xFFCC00, 0x8BD03A, 0x34C7A0, 0x30A2F0, 0x7D5BE0, 0xD45ACB, 0xFF4F5E]
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(hex(colours[i], 0.82))
                    .frame(width: edge * 0.19, height: edge * 0.34)
                    .offset(y: -edge * 0.15)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .blendMode(.multiply)
            }
        }
    }
}

private struct MapsArt: View {
    let edge: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: edge * 0.2).fill(hex(0xB8E0A0)).frame(width: edge * 0.6, height: edge * 0.5)
                .offset(x: -edge * 0.28, y: -edge * 0.3)
            Rectangle().fill(hex(0x8FCBFF)).frame(width: edge * 1.3, height: edge * 0.16)
                .rotationEffect(.degrees(-28)).offset(y: edge * 0.3)
            Rectangle().fill(hex(0xFFD24A)).frame(width: edge * 0.1, height: edge * 1.4)
                .rotationEffect(.degrees(32))
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: edge * 0.34))
                .foregroundStyle(.white, hex(0x0A84FF))
        }
    }
}

private struct NotesArt: View {
    let edge: Double
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(LinearGradient(colors: [hex(0xFFD84A), hex(0xFFC81E)], startPoint: .top, endPoint: .bottom))
                .frame(height: edge * 0.28)
            VStack(spacing: edge * 0.1) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle().fill(hex(0xC7C7CC)).frame(height: max(1, edge * 0.015))
                }
            }
            .padding(.top, edge * 0.1)
            .padding(.horizontal, edge * 0.12)
            Spacer(minLength: 0)
        }
        .frame(width: edge, height: edge)
    }
}

private struct RemindersArt: View {
    let edge: Double
    var body: some View {
        let colours: [UInt32] = [0x0A84FF, 0xFF453A, 0xFF9F0A]
        VStack(alignment: .leading, spacing: edge * 0.1) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: edge * 0.08) {
                    Circle().strokeBorder(hex(colours[i]), lineWidth: edge * 0.03)
                        .background(Circle().fill(hex(colours[i]).opacity(0.0)))
                        .frame(width: edge * 0.15, height: edge * 0.15)
                    Capsule().fill(hex(0xD1D1D6)).frame(width: edge * 0.36, height: edge * 0.04)
                }
            }
        }
    }
}

private struct StocksArt: View {
    let edge: Double
    var body: some View {
        Canvas { context, size in
            let points: [Double] = [0.62, 0.55, 0.6, 0.42, 0.48, 0.34, 0.38, 0.26]
            var path = Path()
            for (i, y) in points.enumerated() {
                let p = CGPoint(x: size.width * (0.14 + 0.72 * Double(i) / Double(points.count - 1)), y: size.height * y)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(hex(0x30D158)),
                           style: StrokeStyle(lineWidth: size.width * 0.05, lineCap: .round, lineJoin: .round))
        }
        .frame(width: edge, height: edge)
    }
}

private struct SiriArt: View {
    let edge: Double
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [hex(0xFF5FA2), hex(0xFF9F0A), hex(0x5AC8FA), hex(0x7D5BE0), hex(0xFF5FA2)],
                                  center: .center))
            .frame(width: edge * 0.58, height: edge * 0.58)
            .blur(radius: edge * 0.03)
            .overlay(Circle().fill(.white.opacity(0.35)).frame(width: edge * 0.22).blur(radius: edge * 0.05))
    }
}

private struct AppStoreArt: View {
    let edge: Double
    var body: some View {
        ZStack {
            Capsule().fill(.white).frame(width: edge * 0.08, height: edge * 0.52).rotationEffect(.degrees(30)).offset(x: -edge * 0.07)
            Capsule().fill(.white).frame(width: edge * 0.08, height: edge * 0.52).rotationEffect(.degrees(-30)).offset(x: edge * 0.07)
            Capsule().fill(.white).frame(width: edge * 0.5, height: edge * 0.08).offset(y: edge * 0.1)
        }
    }
}

private struct ShortcutsArt: View {
    let edge: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: edge * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [hex(0x5AC8FA), hex(0x007AFF)], startPoint: .top, endPoint: .bottom))
                .frame(width: edge * 0.38, height: edge * 0.38)
                .rotationEffect(.degrees(45)).offset(y: edge * 0.08)
            RoundedRectangle(cornerRadius: edge * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [hex(0xFF6FB1), hex(0xFF2D55)], startPoint: .top, endPoint: .bottom))
                .frame(width: edge * 0.38, height: edge * 0.38)
                .rotationEffect(.degrees(45)).offset(y: -edge * 0.08)
        }
    }
}

// MARK: - Wallpaper and status bar

/// Pale silver up top where the drop hangs, deepening into a soft dawn of
/// lavender and periwinkle toward the dock, warmed by a peach glow on one
/// side and a rose one on the other.
struct Wallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = max(w, h)
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(red: 0.86, green: 0.86, blue: 0.88), location: 0),
                    .init(color: Color(red: 0.80, green: 0.80, blue: 0.86), location: 0.2),
                    .init(color: Color(red: 0.66, green: 0.66, blue: 0.83), location: 0.48),
                    .init(color: Color(red: 0.50, green: 0.54, blue: 0.80), location: 0.78),
                    .init(color: Color(red: 0.40, green: 0.43, blue: 0.72), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                bloom(Color(red: 1.00, green: 0.76, blue: 0.62), at: CGPoint(x: w * 0.0, y: h * 0.52), radius: side * 0.5, opacity: 0.55)
                bloom(Color(red: 0.98, green: 0.66, blue: 0.84), at: CGPoint(x: w * 1.05, y: h * 0.80), radius: side * 0.48, opacity: 0.5)
                bloom(Color(red: 0.66, green: 0.80, blue: 1.00), at: CGPoint(x: w * 0.95, y: h * 0.30), radius: side * 0.38, opacity: 0.45)
                // Keep the top quiet and silver for the drop.
                LinearGradient(colors: [Color(red: 0.87, green: 0.87, blue: 0.89),
                                        Color(red: 0.87, green: 0.87, blue: 0.89).opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
            }
        }
    }

    private func bloom(_ color: Color, at point: CGPoint, radius: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .position(point)
    }
}

/// 9:41, full bars, full battery, level with the island.
struct StatusBar: View {
    let width: CGFloat
    let island: CGRect

    var body: some View {
        let y = max(island.midY, 22)
        ZStack(alignment: .topLeading) {
            Color.clear
            Text("9:41")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .fixedSize()
                .position(x: width * 0.182, y: y)
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                    .font(.system(size: 21, weight: .regular))
            }
            .font(.system(size: 15, weight: .semibold))
            .fixedSize()
            .position(x: width - 66, y: y)
        }
        .foregroundStyle(.black)
        .frame(width: width, height: y + 30)
    }
}
