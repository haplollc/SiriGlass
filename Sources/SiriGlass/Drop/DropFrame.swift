//
//  DropFrame.swift
//  SiriGlass
//
//  One frame of the drop: the shader's uniforms, and the outline of the
//  same shape for the system glass, traced from the same distance field.
//

import SwiftUI

/// The uniforms for one frame of SiriGlass.metal, in the space of the layer
/// the drop is drawn in.
struct DropFrame: Equatable {
    /// The island, in the drop's design space (see `extra.z`).
    var island: CGRect = .zero
    /// Centre x, centre y, half width, half height of the bead (pt).
    var drop = SIMD4<Float>(0, 0, 1, 1)
    var exponent: Float = 3
    var presence: Float = 0
    var neck: Float = 0
    var time: Float = 0
    /// Strand amplitudes (pt) and the voice level.
    var amps = SIMD4<Float>(0, 0, 0, 0)
    var phases = SIMD4<Float>(0, 0, 0, 0)
    /// Ignition, thinking, waterline offset (pt).
    var light = SIMD4<Float>(0, 0, 0, 0)
    /// How grown, debug, scale, how light the backdrop is.
    var extra = SIMD4<Float>(0, 0, 1, 0)
    /// Seconds on the drop's clock.
    var clock: Double = 0

    var isVisible: Bool { presence > 0.001 }
    var scale: Double { Double(extra.z) }

    @MainActor private static let library = ShaderLibrary.bundle(.module)

    @MainActor var shader: Shader {
        Shader(function: ShaderFunction(library: Self.library, name: "siriGlassDrop"), arguments: [
            .float4(Float(island.minX), Float(island.minY), Float(island.width), Float(island.height)),
            .float4(drop.x, drop.y, drop.z, drop.w),
            .float4(exponent, presence, neck, time),
            .float4(amps.x, amps.y, amps.z, amps.w),
            .float4(phases.x, phases.y, phases.z, phases.w),
            .float4(light.x, light.y, light.z, light.w),
            .float4(extra.x, extra.y, extra.z, extra.w),
        ])
    }

    /// The bead's bounding box in layer space, as drawn.
    var bounds: CGRect {
        let s = scale
        let w = Double(drop.z) * s, h = Double(drop.w) * s
        return CGRect(x: Double(drop.x) - w, y: Double(drop.y) - h, width: w * 2, height: h * 2)
    }
}

// MARK: - The shape, in Swift

/// SiriGlass.metal's distance field, line for line, so the glass outline
/// and the painted drop agree to the pixel.
struct DropField {
    let island: SIMD4<Double>
    let drop: SIMD4<Double>
    let n: Double
    let neck: Double
    let scale: Double

    init(_ frame: DropFrame) {
        island = SIMD4(frame.island.minX, frame.island.minY, frame.island.width, frame.island.height)
        drop = SIMD4(Double(frame.drop.x), Double(frame.drop.y), Double(frame.drop.z), Double(frame.drop.w))
        n = Double(frame.exponent)
        neck = Double(frame.neck)
        scale = max(frame.scale, 0.01)
    }

    private func pill(_ px: Double, _ py: Double) -> Double {
        let hx = island.z * 0.5, hy = island.w * 0.5
        let cx = island.x + hx, cy = island.y + hy
        let rad = min(hx, hy)
        let qx = abs(px - cx) - (hx - rad), qy = abs(py - cy) - (hy - rad)
        let ox = max(qx, 0), oy = max(qy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(qx, qy), 0) - rad
    }

    private func bead(_ px: Double, _ py: Double) -> Double {
        let qx = max(abs(px - drop.x) / drop.z, 1e-4), qy = max(abs(py - drop.y) / drop.w, 1e-4)
        let nx = pow(qx, n), ny = pow(qy, n)
        let s = nx + ny
        let r = pow(s, 1 / n)
        let k = pow(s, 1 / n - 1)
        let gx = k * (nx / qx) / drop.z, gy = k * (ny / qy) / drop.w
        return (r - 1) / max((gx * gx + gy * gy).squareRoot(), 1e-5)
    }

    private func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = max(k - abs(a - b), 0) / max(k, 1e-4)
        return min(a, b) - h * h * k * 0.25
    }

    /// Signed distance (design units) at a point in layer space.
    func distance(at point: CGPoint) -> Double {
        let qx = drop.x + (Double(point.x) - drop.x) / scale
        let qy = drop.y + (Double(point.y) - drop.y) / scale
        return smin(pill(qx, qy), bead(qx, qy), neck)
    }

    /// The outline, as `count` points round a point inside it: for each
    /// direction, the outermost place the field crosses zero.
    func outline(count: Int = 180) -> [CGPoint] {
        let centre = CGPoint(x: drop.x, y: drop.y)
        // Inside both the island and the bead while it hangs from the
        // island (the island's foot); otherwise the bead's middle.
        let footDesign = CGPoint(x: island.x + island.z / 2, y: island.y + island.w / 2 + 3)
        let foot = CGPoint(x: centre.x + (footDesign.x - centre.x) * scale, y: centre.y + (footDesign.y - centre.y) * scale)
        let origin = distance(at: foot) < 0 ? foot : centre
        guard distance(at: origin) < 0 else { return [] }

        // Far enough to clear everything the shape can reach.
        let corners = [
            CGPoint(x: centre.x - drop.z * 1.1 * scale, y: centre.y - drop.w * 1.1 * scale),
            CGPoint(x: centre.x + drop.z * 1.1 * scale, y: centre.y + drop.w * 1.1 * scale),
            CGPoint(x: centre.x + (island.x - drop.x - 4) * scale, y: centre.y + (island.y - drop.y - 4) * scale),
            CGPoint(x: centre.x + (island.x + island.z - drop.x + 4) * scale, y: centre.y + (island.y + island.w - drop.y + 4) * scale),
        ]
        let reach = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max()! + neck * scale + 4
        let steps = 40
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let dx = cos(angle), dy = sin(angle)
            func at(_ r: Double) -> CGPoint { CGPoint(x: origin.x + dx * r, y: origin.y + dy * r) }
            var lastInside = 0.0
            for k in 1...steps {
                let r = reach * Double(k) / Double(steps)
                if distance(at: at(r)) < 0 { lastInside = r }
            }
            var lo = lastInside, hi = min(lastInside + reach / Double(steps), reach)
            for _ in 0..<14 {
                let mid = (lo + hi) / 2
                if distance(at: at(mid)) < 0 { lo = mid } else { hi = mid }
            }
            points.append(at((lo + hi) / 2))
        }
        return points
    }
}

/// A closed, smooth curve through the outline's points (Catmull-Rom).
struct DropOutline: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2 else { return path }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
