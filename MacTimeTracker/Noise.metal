#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Gaussian blur (used for the mode-transition effect)

[[ stitchable ]] half4 gaussianBlur(float2 position, SwiftUI::Layer layer, float2 dir, float radius, float2 size) {
    int r = int(clamp(radius, 0.0, 60.0));
    if (r <= 0) { return layer.sample(position); }
    float sigma = max(float(r) * 0.5, 1.0);
    half4 sum = half4(0.0);
    float total = 0.0;
    float2 hi = max(size - 1.0, float2(0.0));
    for (int i = -r; i <= r; i++) {
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        float2 sp = clamp(position + dir * float(i), float2(0.0), hi);
        sum += half(w) * layer.sample(sp);
        total += w;
    }
    return sum / half(max(total, 1e-4));
}

// MARK: - Icon (three concentric circles)

// Base field: deep red-brown in the center warming to gold at the edge — a
// two-stop gradient for richer color depth.
static float3 baseField(float r) {
    float t = clamp(r / 0.55, 0.0, 1.0);
    return mix(float3(0.36, 0.13, 0.04), float3(1.0, 0.72, 0.14), t);
}

// The studio environment a glass surface reflects: cool sky up top, neutral in
// the middle, warm below. `ny` runs −1 (up) … +1 (down).
static float3 envColor(float ny) {
    float t = clamp(ny * 0.5 + 0.5, 0.0, 1.0);
    float3 sky  = float3(0.55, 0.78, 1.00);
    float3 mid  = float3(0.90, 0.90, 0.94);
    float3 warm = float3(1.00, 0.60, 0.32);
    return t < 0.5 ? mix(sky, mid, t / 0.5) : mix(mid, warm, (t - 0.5) / 0.5);
}

// Luminance-preserving hue rotation around the grey axis (radians).
static float3 hueRotate(float3 c, float a) {
    const float3 k = float3(0.57735027);
    float cs = cos(a);
    return c * cs + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cs);
}

/// The app icon's concentric circles as continuously emanating **liquid-glass**
/// rings that fill the frame. A smooth warm-orange field is overlaid with glassy
/// concentric rims that refract the field (with chromatic fringing), catch a
/// cool top-left light, and glint along their edges — no hard lines. A soft
/// wet-glass hotspot and a gentle vignette add depth. Rings grow outward from
/// the center forever.
///
/// `speed` = expansion, `circles` = ring frequency, `refraction` = lens bend,
/// `gloss` = highlight strength, `aberration` = color fringing, `rimWidth` =
/// glass edge width, `hue` = manual overall hue shift (0…1 → full wheel),
/// `iridescence` = thin-film rainbow sheen + depth, `reflection` = environment
/// reflection strength (cool sky above, warm below), `caustics` = focused light
/// filaments on the rims, `saturation` = overall color saturation (1 = normal,
/// 0 = greyscale, >1 = boosted).
[[ stitchable ]] half4 iconCircles(float2 position, half4 color, float2 size, float time,
                                   float speed, float circles, float refraction, float gloss,
                                   float aberration, float rimWidth, float hue, float iridescence,
                                   float reflection, float caustics, float saturation) {
    // Normalize by the largest dimension so the rings reach every corner.
    float scale = max(max(size.x, size.y), 1.0);
    float2 uv = (position - 0.5 * size) / scale;
    float d = length(uv);
    float2 radial = uv / max(d, 1e-4);   // unit outward direction

    // Constant-phase contours march outward as time grows; fract repeats, so new
    // circles are continuously born at the center and grow past the edges.
    float g = fract(d * max(circles, 0.5) - time * speed);   // 0..1 within each ring
    float e = min(g, 1.0 - g);                               // distance to nearest edge
    float sideSign = sign(g - 0.5);                          // −1 inside edge, +1 outside

    // Glass rim centered on each circle boundary (where the dark line used to be).
    float rim = smoothstep(max(rimWidth, 0.01), 0.0, e);     // 1 at the edge → 0 mid-ring

    // Refraction: bend the sampled radius near the rim like a convex lens edge.
    float bend = sideSign * rim * rim * refraction * 0.12;
    float dRef = d + bend;

    // Base field with per-channel chromatic offset at the rims → glassy fringing.
    float ca = rim * aberration * 0.03;
    float3 col = float3(baseField(dRef + ca).r,
                        baseField(dRef).g,
                        baseField(dRef - ca).b);

    // Pseudo-reflection: blend in the environment, strongest at the rims (grazing
    // angles). Top ridges catch cool sky, bottom ridges catch warm.
    float3 env = envColor(clamp(radial.y + sideSign * rim * 0.5, -1.0, 1.0));
    col = mix(col, env, reflection * (0.1 + 0.7 * rim));

    // Directional glass lighting from a slowly rotating key light — the moving
    // reflection sweeps around the rings. Starts near the top-left.
    float la = time * 0.12 - 2.18;
    float2 lightDir = float2(cos(la), sin(la));
    float ndl = dot(radial, lightDir);
    float spec = pow(max(ndl, 0.0), 1.6) * rim * gloss;
    float shade = pow(max(-ndl, 0.0), 1.6) * rim;
    float glint = smoothstep(0.035, 0.0, e);                 // thin all-around edge light

    col += float3(0.9, 0.95, 1.0) * spec * 0.5;              // cool-white highlight
    col += glint * 0.12 * clamp(gloss, 0.0, 2.0);
    col *= (1.0 - 0.16 * shade);

    // Caustics: sharp, thin focused light filaments hugging the rims, brightest
    // on the light-facing side — the bright lines seen in cymatics / refraction.
    float caustic = pow(smoothstep(max(rimWidth, 0.01), 0.0, e), 9.0)
                    * (0.35 + 0.65 * max(ndl, 0.0)) * caustics;
    col += float3(1.0, 0.97, 0.88) * caustic * 1.3;

    // --- Richness: thin-film iridescence on the rims + a bit of depth. ---
    // A spectral (rainbow) sheen whose hue cycles with the ring band, the radius
    // and the viewing angle — like light dispersing through beveled crystal.
    float iph = g * 12.566 + d * 6.0 + ndl * 3.0;
    float3 spectral = 0.5 + 0.5 * cos(iph + float3(0.0, 2.094, 4.188));
    col = mix(col, col * 0.55 + spectral * spectral, rim * iridescence * 0.6);
    // Deepen the band interiors (away from the rims) so the glass reads thicker
    // and the highlights pop — more tonal range.
    col *= mix(1.0 - 0.12 * iridescence, 1.0, smoothstep(0.5, 0.08, e));

    // Soft wet-glass reflection that slowly orbits with the light.
    float2 hotspot = 0.26 * float2(cos(la * 0.7), sin(la * 0.7));
    float hs = smoothstep(0.5, 0.0, length(uv - hotspot));
    col += float3(1.0, 0.98, 0.92) * hs * 0.08 * clamp(gloss, 0.0, 2.0);

    // Gentle vignette for depth.
    col *= mix(0.8, 1.0, smoothstep(0.72, 0.15, d));

    // Manual overall hue shift (0…1 → a full turn around the wheel).
    col = hueRotate(col, hue * 6.2831853);

    // Overall saturation about the luma grey point.
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(luma), col, saturation);

    // Fine ordered-ish dither to break up gradient banding.
    float dth = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    col += (dth - 0.5) / 255.0;

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}
