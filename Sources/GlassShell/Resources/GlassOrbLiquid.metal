//
//  GlassOrbLiquid.metal
//  Glass Power Tools — GlassShell
//
//  An orb's picture as liquid (the owner, 2026-11-05: "actual liquid effects with metal ... like awesome water effects,
//  not cheesy animations"): stretched with its drop's wobbling rim, and, while its session is busy, rippled by drops
//  falling into its middle, the rings bending the picture as water does what lies under it, light glinting off the faces
//  of the rings turned to it and gathering where they curve like a lens. `GlassOrbJelly.swift` says how the rim wobbles
//  and when drops fall; `GlassOrbLiquid.swift` draws it.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {
    /// The rim at `theta`, as a share of the round drop's radius: modes 2 to 5 (`GlassDropletDeformation`).
    float rimAt(float theta, float4 cosines, float4 sines, float mean) {
        float4 angles = float4(2.0, 3.0, 4.0, 5.0) * theta;
        return 1.0 + mean + dot(cosines, cos(angles)) + dot(sines, sin(angles));
    }

    /// Between rings, as a share of the radius.
    constant float wavelength = 0.2;
    constant float waveNumber = 2.0 * M_PI_F / wavelength;

    /// The water's height at `r` from the middle (a share of the radius) from drops that fell `ages` seconds ago
    /// (negative: none), their leading ring reaching the rim after `reach` seconds.
    float waterAt(float r, float4 ages, float reach) {
        float height = 0.0;
        for (int i = 0; i < 4; i++) {
            float age = ages[i];
            if (age < 0.0) continue;
            float front = age / reach;
            // Behind the leading ring a train of two or three, the first the strongest; ahead of it, still water.
            float behind = front - r;
            float train = behind > 0.0 ? exp(-behind * behind / (wavelength * wavelength * 2.4))
                                       : exp(-behind * behind / (wavelength * wavelength * 0.06));
            // Lower as they spread, dying away, and gone at the rim, where the rim shivers instead.
            float spread = 1.0 / sqrt(1.0 + 5.0 * front);
            float fade = exp(-age * 1.2) * (1.0 - smoothstep(0.86, 1.0, r));
            height += sin(waveNumber * behind) * train * spread * fade;
            // Where it fell: a splash in the middle, settling at once.
            height += 0.8 * exp(-age * 9.0) * exp(-r * r / 0.01);
        }
        return height;
    }
}

/// The picture of a drop centred at `center`, round at `radius`: stretched to the rim the modes give, and seen through
/// rippling water. `strength` scales the ripples' bending and light (0 for the rim's wobble alone).
[[ stitchable ]] half4 glassOrbLiquid(float2 position, SwiftUI::Layer layer, float2 center, float radius,
                                      float4 cosines, float4 sines, float mean, float4 ages, float reach,
                                      float strength) {
    float2 offset = position - center;
    float distance = length(offset);
    float2 way = distance > 0.001 ? offset / distance : float2(0.0, 0.0);
    float rim = rimAt(atan2(offset.y, offset.x), cosines, sines, mean);
    // Where this point stood on the round drop: the picture stretched and squashed with the rim.
    float r = distance / (radius * rim);
    float coverage = saturate((1.0 - r) * radius * rim + 0.5);
    if (coverage <= 0.0) return half4(0.0);

    float2 source = center + way * (r * radius);
    half3 light = half3(0.0);
    if (strength > 0.0 && any(ages >= 0.0)) {
        // The water's tilt and curve here, from its height a little either side.
        const float step = 0.012;
        float here = waterAt(r, ages, reach);
        float outside = waterAt(r + step, ages, reach);
        float inside = waterAt(max(r - step, 0.0), ages, reach);
        float tilt = (outside - inside) / (2.0 * step) / waveNumber;
        float curve = ((outside - 2.0 * here + inside) / (step * step) + (outside - inside) / (2.0 * step) / max(r, step))
                      / (waveNumber * waveNumber);
        // Seen through the surface, the picture shifts downhill.
        source -= way * tilt * radius * 0.1 * strength;
        // Light from the upper leading side: faces turned to it glint, faces turned away darken a little, and where the
        // surface curves like a lens the light gathers.
        float facing = -tilt * dot(way, normalize(float2(-0.6, -0.8)));
        float glint = pow(saturate(facing * 2.5), 1.5) * 0.5 - saturate(-facing) * 0.18;
        float caustic = saturate(-curve * 2.2) * 0.35;
        light = half3((glint + caustic) * strength);
    }
    half4 color = layer.sample(source);
    color.rgb = max(color.rgb + light * color.a, half3(0.0));
    return color * half(coverage);
}
