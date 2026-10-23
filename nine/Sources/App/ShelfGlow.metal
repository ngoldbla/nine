// ShelfGlow.metal — the Apple TV shelf page's light (tvOS input pass, 1.2 beta).
//
// The glow behind each shelf board was a two-stop `RadialGradient` from the
// band's hue at 28% to clear over 900pt. On a near-black ground that is a
// ramp a few dozen 8-bit codes deep spread across ~1800 4K pixels, so every
// code became a visible ring tens of pixels wide, and the ramp ended in a
// crease where it hit zero. A television's own processing (local contrast,
// motion smoothing, its own panel's bit depth) turned the rings into the
// "blob that looks compressed" the beta reported.
//
// Two fixes, in one function:
//   • **Gaussian falloff**, not linear-in-radius: smooth to zero with no edge
//     of its own, so there is no crease to find.
//   • **Triangular dither of ±1 code**, added before the frame is quantised:
//     the average of each neighbourhood is still the exact ramp, but no two
//     neighbouring pixels sit on the same step, so a step cannot form a ring.
//     Faded out where the glow itself has faded, so the empty ground stays
//     perfectly still and perfectly black (the idle-pixel test).
//
// Stitchable functions resolve BY NAME at runtime — keep the signature in
// lockstep with the `ShaderLibrary.shelfGlow` call in TVShelf.swift.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Hash without sine (Dave Hoskins): stable across GPUs, no visible pattern.
static float shelfHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// - position: this pixel, in points (a 4K Apple TV is 2× — hashed below at a
///   resolution finer than a pixel so every pixel draws its own noise).
/// - center, radius: the glow's centre and its 1/e-ish reach, in points.
/// - tint: the band's hue, opaque.
/// - peak: the glow's opacity at its centre.
[[stitchable]] half4 shelfGlow(
    float2 position,
    half4 color,
    float2 center,
    float radius,
    half4 tint,
    float peak
) {
    float d = length(position - center) / radius;
    float alpha = peak * exp(-2.4 * d * d);

    // Two uniforms summed: a triangular distribution on (-1, 1) codes, which
    // (unlike a single uniform) leaves no brightness-dependent noise pattern.
    float2 cell = floor(position * 4.0);
    float noise = shelfHash(cell) + shelfHash(cell + 71.7) - 1.0;
    // Only where there is a ramp to break up.
    float amount = saturate(alpha * 60.0) / 255.0;

    // Premultiplied: the ground shows through by (1 - alpha), and the noise
    // lands on the composited pixel as-is.
    float3 rgb = float3(tint.rgb) * alpha + noise * amount;
    return half4(half3(rgb), half(alpha));
}
