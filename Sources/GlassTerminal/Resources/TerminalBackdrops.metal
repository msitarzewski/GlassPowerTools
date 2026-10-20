//
//  TerminalBackdrops.metal
//  Glass Power Tools — GlassTerminal
//
//  What a terminal window can show behind its text (D84): SwiftUI shaders, drawn under the terminal,
//  which is transparent, and never over it. Each takes the view's size and a time in seconds; each
//  stays dark enough to read over, and `intensity` scales it.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {
    float hash11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
    float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    /// A blocky 5 × 7 glyph from a seed: about half its dots lit, never a blank cell.
    float glyphDot(float2 inCell, float seed) {
        float2 dot = floor(inCell * float2(5.0, 7.0));
        if (dot.x < 0.0 || dot.x > 4.0 || dot.y < 0.0 || dot.y > 6.0) return 0.0;
        float bit = hash21(dot + seed * 17.0);
        // Symmetric glyphs read as letters more often than noise does.
        float mirrored = hash21(float2(4.0 - dot.x, dot.y) + seed * 17.0);
        return step(0.52, mix(bit, mirrored, 0.5));
    }
}

/// Falling columns of glyphs. `speed` is rows a second at 1; it is what follows the terminal's output.
[[ stitchable ]] half4 glassRain(float2 position, half4 color, float2 size, float time, float cellWidth,
                                 float speed, half4 tint, float intensity) {
    float cellHeight = cellWidth * 1.35;
    float column = floor(position.x / cellWidth);
    float row = floor(position.y / cellHeight);
    float rows = size.y / cellHeight;
    float2 inCell = float2(fract(position.x / cellWidth), fract(position.y / cellHeight));
    // Glyphs sit inside their cells with a gap.
    inCell = (inCell - 0.12) / 0.76;

    float columnSeed = hash11(column + 1.0);
    float trail = 8.0 + columnSeed * 18.0;
    float fall = speed * (0.45 + 0.9 * columnSeed);
    float head = fmod(time * fall + columnSeed * 97.0, rows + trail);
    float behind = head - row;
    if (behind < 0.0 || behind > trail) return half4(0.0);

    float fade = pow(1.0 - behind / trail, 1.6);
    // Each glyph changes now and then; the head's changes fastest.
    float change = floor(time * (behind < 1.0 ? 14.0 : 1.5 + 3.0 * hash21(float2(column, row))));
    float lit = glyphDot(inCell, hash21(float2(column, row) + change));
    float3 base = float3(tint.rgb);
    float3 rgb = behind < 1.0 ? mix(base, float3(1.0), 0.75) : base * (0.35 + 0.65 * fade);
    float alpha = lit * fade * intensity;
    return half4(half3(rgb * alpha), half(alpha));
}

/// A sunset over a grid that rolls toward you: sky, a striped sun, and the floor's lines.
[[ stitchable ]] half4 glassSynthwave(float2 position, half4 color, float2 size, float time, half4 skyTop,
                                      half4 skyBottom, half4 sunTop, half4 sunBottom, half4 grid, float intensity) {
    float2 uv = position / size;
    float horizon = 0.62;
    float3 rgb;
    float alpha;
    if (uv.y < horizon) {
        float t = uv.y / horizon;
        rgb = mix(float3(skyTop.rgb), float3(skyBottom.rgb), t);
        alpha = mix(0.55, 0.85, t);
        // The sun: a disc above the horizon, cut by bands that thicken toward its foot.
        float aspect = size.x / size.y;
        float2 centre = float2(0.5, horizon - 0.17);
        float2 d = (uv - centre) * float2(aspect, 1.0);
        float radius = 0.2;
        float inside = 1.0 - smoothstep(radius - 0.004, radius, length(d));
        float v = (uv.y - (centre.y - radius)) / (2.0 * radius);
        float band = step(0.5, v) * step(fract(v * 9.0 - time * 0.12), 0.18 + 0.5 * (v - 0.5));
        float3 sun = mix(float3(sunTop.rgb), float3(sunBottom.rgb), saturate(v));
        rgb = mix(rgb, sun, inside * (1.0 - band));
        alpha = mix(alpha, 1.0, inside * (1.0 - band));
        // A glow around the sun.
        rgb += float3(sunBottom.rgb) * 0.25 * exp(-6.0 * max(0.0, length(d) - radius));
    } else {
        // The floor: lines along and across, in perspective, rolling toward you.
        float depth = 1.0 / max(uv.y - horizon, 0.002);
        float x = (uv.x - 0.5) * depth;
        float z = depth * 0.35 + time * 0.6;
        float width = 0.02 * depth;
        // A line where the pattern wraps: within `width` of each cell's edge.
        float along = smoothstep(1.0 - min(width, 0.6), 1.0, abs(fract(x * 0.9) - 0.5) * 2.0);
        float across = smoothstep(1.0 - min(width * 0.8, 0.6), 1.0, abs(fract(z) - 0.5) * 2.0);
        float line = saturate(max(along, across));
        float nearness = saturate((uv.y - horizon) / (1.0 - horizon));
        float3 floorColour = mix(float3(skyBottom.rgb) * 0.25, float3(0.02, 0.0, 0.06), nearness);
        rgb = mix(floorColour, float3(grid.rgb), line * (0.35 + 0.65 * nearness));
        alpha = 0.9;
    }
    alpha *= intensity;
    return half4(half3(rgb * alpha), half(alpha));
}

/// Blocks of the picture: each block one sample, from its middle.
[[ stitchable ]] half4 glassPixelate(float2 position, SwiftUI::Layer layer, float blockSize) {
    float size = max(blockSize, 1.0);
    float2 middle = (floor(position / size) + 0.5) * size;
    return layer.sample(middle);
}

/// The picture in two colours: its dark in `dark`, its light in `light`, so it sits under the theme.
[[ stitchable ]] half4 glassDuotone(float2 position, half4 color, half4 dark, half4 light, float amount) {
    if (color.a <= 0.0) return color;
    half3 straight = color.rgb / color.a;
    half luminance = dot(straight, half3(0.2126, 0.7152, 0.0722));
    half3 toned = mix(dark.rgb, light.rgb, luminance);
    half3 mixed = mix(straight, toned, half(amount));
    return half4(mixed * color.a, color.a);
}

/// Scanlines: every other line of points a little darker, as a phosphor screen's were.
[[ stitchable ]] half4 glassScanlines(float2 position, half4 color, float spacing, float strength) {
    float line = step(0.5, fract(position.y / max(spacing, 1.0)));
    half dim = half(1.0 - strength * line);
    return half4(color.rgb * dim, color.a);
}

/// A phosphor screen: the tube's faint glow in the text's colour, brightest in the middle and
/// falling off toward the edges, with scanlines across it. Still: it never moves.
[[ stitchable ]] half4 glassPhosphorScreen(float2 position, half4 color, float2 size, half4 phosphor,
                                           float scanlineSpacing, float intensity) {
    float2 uv = position / size;
    float2 centred = (uv - 0.5) * float2(size.x / max(size.y, 1.0), 1.0);
    float glow = exp(-2.2 * dot(centred, centred));
    float vignette = smoothstep(1.05, 0.35, length((uv - 0.5) * 1.6));
    float line = step(0.5, fract(position.y / max(scanlineSpacing, 1.0)));
    float3 rgb = float3(phosphor.rgb) * (0.10 + 0.30 * glow) * (1.0 - 0.5 * line);
    float alpha = (0.55 + 0.4 * (1.0 - vignette)) * intensity;
    rgb *= vignette;
    return half4(half3(rgb * intensity), half(alpha));
}

/// Nothing brighter than `maxLuminance` (relative luminance, linear): a brighter pixel keeps its
/// colour and is darkened to it, so a sun in a picture stays a sun, only no brighter than text,
/// dim text included, can be read over. Darker pixels are left as they are.
[[ stitchable ]] half4 glassCeiling(float2 position, half4 color, float maxLuminance) {
    if (color.a <= 0.0) return color;
    float3 straight = float3(color.rgb) / float(color.a);
    float3 linear = pow(max(straight, 0.0), 2.2);
    float luminance = dot(linear, float3(0.2126, 0.7152, 0.0722));
    if (luminance <= maxLuminance || luminance <= 0.0) return color;
    linear *= maxLuminance / luminance;
    half3 encoded = half3(pow(linear, 1.0 / 2.2));
    return half4(encoded * color.a, color.a);
}
