//
//  SiriGlass.metal
//  SiriGlass
//
//  The Siri drop's ink and light. The drop is a bead of Liquid Glass that
//  pours out of the Dynamic Island; the system draws the glass itself (it
//  bends whatever is behind it), and this shader paints everything inside
//  it as a layer over that glass:
//
//    • Shape — a superellipse bead smooth-unioned with the island pill, so
//      it necks out of the island as it grows and pinches back into it.
//    • Glass — thick glass darkens what it shows a touch and lays a little
//      milk over it; a band of light runs round the inside of the rim,
//      brightest underneath, with a specular glint where light catches it.
//    • Ink — the island's black pours into the top of the bead down to a
//      waterline just below its middle. Under the waterline the ink's
//      surface catches the light: a lit band with a soft shadow beneath.
//    • Voice — three strands, the old Siri sine waves, ride the waterline.
//      Each strand and its mirror bound a translucent lobe; lobes are tinted
//      warm, cool and white and turn white where they overlap; every edge is
//      split into a spectrum, like light through a prism.
//
//  The output is premultiplied: colour plus how much of the glass beneath
//  it hides. Light is added on top (its colour can exceed its coverage),
//  so it brightens whatever the glass shows rather than covering it.
//
//  Uniforms (points, in the layer's space):
//    island  — x, y, w, h of the Dynamic Island
//    drop    — centre x, centre y, half width, half height of the bead
//    form    — x: superellipse exponent, y: presence 0…1,
//              z: neck (smooth-union radius), w: time (s)
//    amps    — x, y, z: strand amplitudes (pt), w: voice level 0…1
//    phases  — x, y, z: strand phases (rad), w: dispersion phase (rad)
//    light   — x: ignition 0…1, y: thinking 0…1,
//              z: waterline below the bead's centre (pt), w: unused
//    extra   — x: how grown the bead is (0 a seed in the island, 1 out),
//              y: debug (1 paints nothing, leaving only the glass),
//              z: scale the drop is shown at (1 under the island, ~2 as an orb),
//              w: how light the backdrop is (0…1): the rim shades in on white
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ── Look ────────────────────────────────────────────────────

constant float kGlass = 0.92;          // thick glass darkens what it shows a touch…
constant float kVeil = 0.03;           // …and lays a little milk over it
constant float3 kInkColour = float3(0.052, 0.052, 0.058);   // the island reads as blacker
constant float2 kKeyLight = float2(-0.53, -0.85);           // where the glint comes from (up, left)

// ── Shape ───────────────────────────────────────────────────

static inline float sgSq(float x) { return x * x; }

/// A pill: a rounded rect whose ends are fully round, like the island.
static float sgPill(float2 p, float4 r) {
    float2 h = r.zw * 0.5;
    float2 c = r.xy + h;
    float rad = min(h.x, h.y);
    float2 q = abs(p - c) - (h - rad);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

/// |x/a|^n + |y/b|^n = 1 as an approximate signed distance: the implicit
/// value over its gradient, exact on the edge and close near it.
static float sgBead(float2 p, float4 drop, float n) {
    float2 q = max(abs(p - drop.xy) / drop.zw, float2(1e-4));
    float2 qn = pow(q, float2(n));
    float s = qn.x + qn.y;
    float r = pow(s, 1.0 / n);
    float2 g = pow(s, 1.0 / n - 1.0) * (qn / q) / drop.zw;
    return (r - 1.0) / max(length(g), 1e-5);
}

/// Polynomial smooth minimum: the liquid neck between island and bead.
static float sgSmin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / max(k, 1e-4);
    return min(a, b) - h * h * k * 0.25;
}

static float sgShape(float2 p, float4 island, float4 drop, float n, float neck) {
    return sgSmin(sgPill(p, island), sgBead(p, drop, n), neck);
}

// ── Voice ───────────────────────────────────────────────────

/// The bell every strand lives under: zero at the bead's sides.
static float sgEnvelope(float x) {
    float u = saturate(1.0 - x * x);
    return u * sqrt(sqrt(u));
}

struct SGStrands {
    float3 f;   // signed strand heights (pt)
    float3 c;   // centre line of each lobe (pt): each leans on another strand
};

static SGStrands sgStrands(float x, float4 amps, float4 phases) {
    float env = sgEnvelope(x);
    SGStrands s;
    s.f = float3(amps.x * sin(0.90 * M_PI_F * x + phases.x),
                 amps.y * sin(1.30 * M_PI_F * x + phases.y),
                 amps.z * sin(1.75 * M_PI_F * x + phases.z)) * env;
    s.c = float3(0.55 * s.f.y, 0.50 * s.f.z, 0.45 * s.f.x);
    return s;
}

/// Each lobe's light at height y over the waterline: a lens of light
/// between the strand and its mirror, crisp-edged so the prism can split its
/// edges into clean bands of colour, translucent inside and a little
/// brighter along its middle. The second and third strands are fainter.
static float3 sgLobes(float y, SGStrands s, float edgeWidth, float fill) {
    float3 a = abs(s.f);
    float3 dy = abs(y - s.c);
    float3 thick = smoothstep(0.6, 7.0, a);
    float3 inside = 1.0 - smoothstep(a - edgeWidth, a + edgeWidth, dy);
    float3 r = dy / (a + edgeWidth);
    float3 body = inside * (0.62 - 0.22 * r * r) * (0.62 + 0.38 * thick);
    return body * fill * float3(1.0, 0.72, 0.52);
}

/// The prism: seven wavelengths, red to violet.
constant float3 kSpectrum[7] = {
    float3(1.00, 0.10, 0.05),
    float3(1.00, 0.50, 0.00),
    float3(0.95, 0.92, 0.05),
    float3(0.15, 1.00, 0.35),
    float3(0.00, 0.85, 1.00),
    float3(0.05, 0.45, 1.00),
    float3(0.30, 0.20, 1.00),
};

/// The lobes' own tints: a warm one, a cool one and a white one.
constant float3 kTint[3] = {
    float3(1.00, 0.70, 0.62),
    float3(0.58, 0.80, 1.00),
    float3(0.92, 0.90, 1.00),
};

// ── Painting over the glass ─────────────────────────────────

/// What the drop lays over its glass: premultiplied colour, and how much
/// of the glass beneath it hides.
struct SGLayer {
    float3 rgb;
    float a;
};

/// Everything beneath, glass included, comes through `k` times as bright.
static inline void sgDim(thread SGLayer &l, float k) {
    l.rgb *= k;
    l.a = 1.0 - (1.0 - l.a) * k;
}

/// Paints colour `c` over everything beneath with opacity `m`.
static inline void sgPaint(thread SGLayer &l, float3 c, float m) {
    l.rgb = mix(l.rgb, c, m);
    l.a = mix(l.a, 1.0, m);
}

/// Adds light on top of whatever shows.
static inline void sgGlow(thread SGLayer &l, float3 c) {
    l.rgb += c;
}

// ── The effect ──────────────────────────────────────────────

[[ stitchable ]] half4 siriGlassDrop(float2 position, half4 color,
                                     float4 island, float4 drop, float4 form,
                                     float4 amps, float4 phases, float4 light, float4 extra) {
    float presence = form.y;
    if (presence <= 0.001) return half4(0.0);

    float n = form.x;
    float neck = form.z;
    float time = form.w;

    // The drop is designed at the size it has under the island (170 x 126
    // pt); `scale` shows it bigger, as an orb, by working in that design
    // space around its centre.
    float S = max(extra.z, 0.01);
    float2 q = drop.xy + (position - drop.xy) / S;

    float d = sgShape(q, island, drop, n, neck);
    float aa = 0.42 / S;                   // a little over one pixel
    if (d > aa) return half4(0.0);
    float inside = 1.0 - smoothstep(-aa, aa, d);

    // Outward normal from the field.
    const float e = 0.6;
    float2 grad = float2(
        sgShape(q + float2(e, 0), island, drop, n, neck) -
        sgShape(q - float2(e, 0), island, drop, n, neck),
        sgShape(q + float2(0, e), island, drop, n, neck) -
        sgShape(q - float2(0, e), island, drop, n, neck));
    float2 nrm = grad / max(length(grad), 1e-5);
    float depth = max(-d, 0.0);
    float under = smoothstep(-0.15, 0.85, nrm.y);   // 1 along the bottom

    if (extra.y > 0.5) return half4(0.0);           // debug: the glass alone

    // ── Glass: thick, a touch darker than what it shows, a little milky.
    // On a light backdrop it is darker still, so the glass shows.
    float onWhite = extra.w;
    SGLayer l = { float3(0.0), 0.0 };
    sgDim(l, mix(kGlass, 0.84, onWhite));
    sgGlow(l, float3(kVeil));

    // ── Where the voice lives ──────────────────────────────
    float level = amps.w;
    float ignite = light.x;
    float think = light.y;
    float span = drop.z * 1.02;
    float x = (q.x - drop.x) / span;
    float y = q.y - (drop.y + light.z);
    float env = sgEnvelope(x);

    // ── Ink: the island's black, fading out round the waterline ─
    // Solid ~22 pt above the line; at the line it drops to about half, holds
    // there a few points, then thins away to nothing ~45 pt below.
    float ink = y < 0.0
        ? mix(0.45, 1.0, 1.0 - smoothstep(-22.0, 0.0, y))
        : 0.45 * (1.0 - smoothstep(3.0, 44.0, y));
    // The rim shades from clear glass at the edge into the ink: a hairline
    // at the top, widening to a broad soft gradient toward the waterline,
    // where the sides bend in the light round them. The very edge stays
    // clear all the way round, so the glass reads as a shell.
    float rise = smoothstep(-38.0, 0.0, y);
    float rimWidth = mix(3.5, 24.0, rise * rise);
    ink *= mix(0.12, 1.0, smoothstep(0.0, rimWidth, depth));
    // A bead still coming out of the island is all ink; the glass clears
    // as it reaches full size.
    ink = mix(1.0, ink, smoothstep(0.7, 1.0, extra.x));
    sgPaint(l, kInkColour, ink * presence);

    // Under the line: the ink's surface, faintly lit down to an arc that
    // dips mid-drop, with a soft shadow along the arc.
    float arc = 5.0 + 15.0 * env;
    float lit = smoothstep(-1.0, 2.0, y) * (1.0 - smoothstep(arc - 3.0, arc + 0.5, y));
    sgPaint(l, float3(0.95, 0.95, 0.97), lit * (0.05 + 0.12 * level) * ignite * presence);
    float shadow = exp(-sgSq((y - arc - 1.5) / 4.0)) + 0.5 * smoothstep(arc, arc + 2.0, y) * exp(-max(y - arc, 0.0) / 10.0);
    sgDim(l, 1.0 - 0.12 * shadow * (1.0 - smoothstep(0.5, 1.02, abs(x))) * presence);
    // Light from the line gathers in the foot of the drop, mid-way across.
    float footT = saturate((y - 4.0) / max(drop.w * 0.92 - 4.0, 1.0));
    float footGlow = smoothstep(0.0, 1.0, footT) * exp(-sgSq(x / 0.62));
    sgGlow(l, float3(footGlow * (0.20 + 0.06 * level) * ignite * presence));

    // ── The voice ──────────────────────────────────────────
    // The line grows out from the middle as the drop wakes, and its tails
    // run all the way to the rim.
    float reach = ignite * 1.15;
    float grow = 1.0 - smoothstep(reach - 0.3, reach, abs(x));
    float gather = mix(1.0, 1.8, think);          // thinking draws the light in
    float taper = pow(sgEnvelope(x * gather), 0.6) * grow * ignite * smoothstep(0.0, 5.0, depth);
    float reachY = amps.x + amps.y + amps.z + 30.0;
    if (taper > 0.001 && abs(y) < reachY) {
        SGStrands s = sgStrands(x * gather, amps, phases);
        float3 a = abs(s.f);

        // A soft halo lights the ink around the lobes, cooler above them.
        float3 outside = max(abs(y - s.c) - a, 0.0);
        float haloWidth = 6.0 + 4.0 * level;
        float3 h3 = exp(-outside / haloWidth);
        float halo = (h3.x + h3.y + h3.z) / 3.0 * (0.08 + 0.20 * level) * taper;
        sgGlow(l, halo * (y < 0.0 ? float3(0.42, 0.48, 0.60) : float3(0.95, 0.93, 0.92)));

        // Lobes through a prism: a white core, edges spread into a spectrum.
        float edgeWidth = 1.1 + 0.35 * level;
        float fill = 0.85 + 0.15 * level;
        float spread = (2.0 + 1.6 * level) * sin(1.35 * x + phases.w);
        spread *= mix(1.0, 1.4 + 0.5 * sin(time * 3.1), think);
        float3 beam = 0.0, weights = 0.0;
        for (int k = 0; k < 7; k++) {
            float sk = float(k) / 3.0 - 1.0;
            float3 lobes = sgLobes(y + sk * spread, s, edgeWidth, fill);
            float3 rgb = lobes.x * kTint[0] + lobes.y * kTint[1] + lobes.z * kTint[2];
            beam += rgb * kSpectrum[k];
            weights += kSpectrum[k];
        }
        beam /= weights;
        // Thinking: the gathered light breathes.
        beam *= mix(1.0, 1.08 + 0.22 * sin(time * 4.2), think);
        beam = 1.0 - exp(-beam * 1.2);
        sgGlow(l, beam * taper);
    }

    // On a light backdrop, the rim shades inward so the silhouette reads.
    sgDim(l, 1.0 - onWhite * 0.22 * exp(-depth / 5.5) * (0.35 + 0.65 * under));

    // ── Rim: a band of light inside the foot, and a hairline ─
    float band = exp(-depth / 3.4) * 0.75 * under;
    sgPaint(l, float3(1.0), band * presence);
    float hair = exp(-sgSq(depth / 0.55)) * (0.22 + 0.5 * under);
    sgGlow(l, float3(hair * presence));

    // ── Liquid Glass: a specular glint along the edge that faces the light,
    // a fainter one opposite, and a soft brightening just inside the rim.
    float2 key = normalize(kKeyLight);
    float facing = pow(saturate(dot(nrm, key)), 2.0) + 0.45 * pow(saturate(dot(nrm, -key)), 3.0);
    float glint = exp(-sgSq(depth / 1.1)) * facing;
    float fresnel = exp(-depth / 7.0) * (0.05 + 0.05 * (1.0 - under));
    sgGlow(l, float3(glint * 0.42 + fresnel) * presence);

    // Keep it SDR: >1 reads as EDR and the system blooms it.
    l.rgb = clamp(l.rgb, 0.0, 1.0);
    float cover = inside * smoothstep(0.0, 0.08, presence);
    return half4(half3(l.rgb * cover), half(saturate(l.a) * cover));
}
