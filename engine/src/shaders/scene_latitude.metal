// scene_latitude.metal -- RFC-023's Scene Latitude Mapping.
//
// One pointwise kernel, before `filming.expose.upsample`: a positive scalar
// gain per pixel, computed on the stop axis and applied to the linear triple.
// The signal never becomes log (§5.6): `log2` and `exp2` only compute `k`.
//
//     n  = norm(max(RGB, 0))               power | Y | max  (§5.2, §15.5)
//     E  = clamp(log2(max(n, floor) / n_ref), -24, 24)
//     d  = f(E) - E                        0.0 exactly in the core
//     d  = d > 0 ? d L / sqrt(L^2 + d^2)   the bounded lift (§15.5)
//     RGB' = 2^d * RGB
//
// `core/latitude_fit.cpp::delta` is the double-precision reference of the
// same arithmetic, in the same order. The node is not dispatched at all when
// the feature is off (the bypass is structural); inside it, a pixel in the core
// takes `exp2(0.0f) = 1.0f` and is written back unchanged.
//
// §11's rule: this node never changes what the pipeline does with a
// pathological pixel -- a norm that is zero, negative, NaN or infinite takes
// k = 1 and passes through as it came. Negative components are not clamped in
// the signal; only the scalar sees `max(RGB, 0)` (§11.2).
//
// `p`:
//   0 K_h   1 H_h (0 = off)   2 K_s   3 H_s (0 = off)
//   4 m     5 L_max           6 norm (0 power, 1 Y, 2 max)
//   7..9 the Y row of the working space's RGB -> XYZ   10 n_ref
//   11 width  12 height  13 split (0 = none)  14..17 the second frame's K_h H_h K_s H_s
//   18 the image's first row in the frame (RFC-035 §9: a band; RFC-020: a strip; 0 for a whole render)
#include "spk_common.h"

// g_m(D) - D, the branch's departure, in the forms that do not cancel near the
// knee: exactly 0 at D = 0 through the multiply, negative beyond it.
inline float slm_departure(float D, float H, float m) {
    if (!(D > 0.0f)) return 0.0f;
    if (m == 2.0f) {
        float r = sqrt(H * H + D * D);
        return -(D * D * D) / (r * (H + r));
    }
    if (m == 1.0f) return -(D * D) / (H + D);
    return D * (H / pow(pow(H, m) + pow(D, m), 1.0f / m) - 1.0f);
}

kernel void spk_scene_latitude(device const float* rgb [[buffer(0)]],
                               device const float* p [[buffer(1)]],
                               device const uint* n [[buffer(2)]],
                               device float* out [[buffer(3)]],
                               uint3 thread_position_in_grid [[thread_position_in_grid]]) {
    uint i = thread_position_in_grid.x;
    if (i >= n[0]) return;
    float r = rgb[3u * i], g = rgb[3u * i + 1u], b = rgb[3u * i + 2u];
    float cr = max(r, 0.0f), cg = max(g, 0.0f), cb = max(b, 0.0f);

    float v;
    uint norm = uint(p[6]);
    if (norm == 1u) {
        v = p[7] * cr + p[8] * cg + p[9] * cb;
    } else if (norm == 2u) {
        v = max(cr, max(cg, cb));
    } else {
        float s2 = cr * cr + cg * cg + cb * cb;
        v = s2 > 0.0f ? (cr * cr * cr + cg * cg * cg + cb * cb * cb) / s2 : 0.0f;
    }

    float k = 1.0f;
    if (v > 0.0f && isfinite(v)) {
        float n_ref = p[10];
        float E = clamp(log2(max(v, n_ref * exp2(-24.0f)) / n_ref), -24.0f, 24.0f);
        float d = 0.0f;
        // A half-frame pair: from `split` along the long edge, the second
        // frame's own knees and rooms (p[14..17]).
        float Kh = p[0], Hh = p[1], Ks = p[2], Hs = p[3];
        if (p[13] > 0.0f) {
            uint w = uint(p[11]), h = uint(p[12]);
            float along = w >= h ? (float(i % w) + 0.5f) / float(w) : (float(i / w) + p[18] + 0.5f) / float(h);
            if (along >= p[13]) { Kh = p[14]; Hh = p[15]; Ks = p[16]; Hs = p[17]; }
        }
        if (Hh > 0.0f && E > Kh) d = slm_departure(E - Kh, Hh, p[4]);
        else if (Hs > 0.0f && E < Ks) d = -slm_departure(Ks - E, Hs, p[4]);
        if (d > 0.0f) { float L = p[5]; d = d * L / sqrt(L * L + d * d); }
        k = clamp(exp2(d), exp2(-30.0f), exp2(30.0f));
    }
    out[3u * i] = r * k;
    out[3u * i + 1u] = g * k;
    out[3u * i + 2u] = b * k;
}

// Map metered scene luminance in stops about middle grey. Ramp up the
// highlight/shadow gain and crossfade into the white/black gain early
// enough to affect subjects within the film's useful exposure range.
// Apply one gain to all three channels.
kernel void spk_camera_tone(device const float* rgb [[buffer(0)]],
                            constant float* p [[buffer(1)]],
                            constant uint& n [[buffer(2)]],
                            device float* out [[buffer(3)]],
                            uint i [[thread_position_in_grid]]) {
    if (i >= n) return;
    float3 c = float3(rgb[3u * i], rgb[3u * i + 1u], rgb[3u * i + 2u]);
    float y = dot(max(c, 0.0f), float3(p[4], p[5], p[6]));
    if (y > 0.0f && isfinite(y)) {
        float stops = log2(y) - log2(p[7]);
        float distance = abs(stops);
        float region = stops >= 0.0f ? p[0] : p[1];
        float end = stops >= 0.0f ? p[2] : p[3];
        float region_gain = region * smoothstep(0.0f, 2.25f, distance);
        // Whites have a wider useful adjustment on the shoulder of the
        // film. Keep the black endpoint at its existing response.
        float end_weight = stops >= 0.0f
            ? smoothstep(0.2f, 4.2f, distance)
            : smoothstep(0.5f, 4.0f, distance);
        float end_gain = (stops >= 0.0f ? 1.55f : 1.25f) * end;
        float gain = mix(region_gain, end_gain, end_weight);
        c *= exp2(gain);
    }
    out[3u * i] = c.r;
    out[3u * i + 1u] = c.g;
    out[3u * i + 2u] = c.b;
}

// Local camera tone: estimate a self-guided base on a small log-luminance grid.
// The full-resolution application only samples the fitted coefficients, retaining
// the original RGB and its texture. No display curve or gamut clipping here.
inline float local_tone_luma(float3 rgb, float3 y, float grey) {
    return clamp(log2(max(dot(max(rgb, 0.0f), y), grey * exp2(-16.0f)) / grey), -16.0f, 16.0f);
}

kernel void spk_local_tone_moments(device const packed_float3* rgb [[buffer(0)]],
                                   constant uint4& shape [[buffer(1)]],
                                   constant float4& luminance [[buffer(2)]],
                                   constant float& exposure [[buffer(3)]],
                                   device packed_float3* moments [[buffer(4)]],
                                   uint i [[thread_position_in_grid]]) {
    if (i >= shape.z * shape.w) return;
    uint2 xy = uint2(i % shape.z, i / shape.z);
    uint2 start = xy * shape.xy / shape.zw;
    uint2 end = (xy + 1u) * shape.xy / shape.zw;
    float sum = 0.0f;
    float squared = 0.0f;
    for (uint y = start.y; y < end.y; ++y) {
        for (uint x = start.x; x < end.x; ++x) {
            float3 c = float3(rgb[y * shape.x + x]) * exposure;
            if (!all(isfinite(c))) c = float3(luminance.w);
            float l = local_tone_luma(c, luminance.xyz, luminance.w);
            sum += l;
            squared += l * l;
        }
    }
    float count = float((end.x - start.x) * (end.y - start.y));
    moments[i] = float3(sum / count, squared / count, 0.0f);
}

kernel void spk_local_tone_fit(device const packed_float3* moments [[buffer(0)]],
                               constant uint& count [[buffer(1)]],
                               device packed_float3* coefficients [[buffer(2)]],
                               uint i [[thread_position_in_grid]]) {
    if (i >= count) return;
    float2 m = float3(moments[i]).xy;
    float variance = max(m.y - m.x * m.x, 0.0f);
    float a = variance / (variance + 0.36f);
    coefficients[i] = float3(a, (1.0f - a) * m.x, 0.0f);
}

kernel void spk_local_tone_apply(device const packed_float3* rgb [[buffer(0)]],
                                 device const packed_float3* coefficients [[buffer(1)]],
                                 constant uint4& shape [[buffer(2)]],
                                 constant float4& luminance [[buffer(3)]],
                                 constant float2& gains [[buffer(4)]],
                                 constant float4& tone [[buffer(5)]],
                                 constant float4& colour [[buffer(6)]],
                                 device packed_float3* out [[buffer(7)]],
                                 uint i [[thread_position_in_grid]]) {
    if (i >= shape.x * shape.y) return;
    float3 source = rgb[i];
    float3 c = source * colour.x;
    if (!all(isfinite(c))) { out[i] = source; return; }

    // Colour-only and exposure-only edits do not need log luminance or a grid.
    if (shape.z > 0u || any(tone.xyz != 0.0f)) {
        float x = local_tone_luma(c, luminance.xyz, luminance.w);
        float delta = 0.0f;
        if (shape.z > 0u) {
            float2 uv = (float2(i % shape.x, i / shape.x) + 0.5f) * float2(shape.zw) / float2(shape.xy) - 0.5f;
            uv = clamp(uv, 0.0f, float2(shape.zw - 1u));
            uint2 lo = uint2(uv);
            uint2 hi = min(lo + 1u, shape.zw - 1u);
            float2 t = uv - float2(lo);
            float3 a = mix(float3(coefficients[lo.y * shape.z + lo.x]),
                           float3(coefficients[lo.y * shape.z + hi.x]), t.x);
            float3 b = mix(float3(coefficients[hi.y * shape.z + lo.x]),
                           float3(coefficients[hi.y * shape.z + hi.x]), t.x);
            float2 fit = mix(a, b, t.y).xy;
            float base = clamp(fit.x * x + fit.y, x - 1.5f, x + 1.5f);

            // Move the local base in stops, leaving its residual alone unless
            // the midtone detail control explicitly changes it.
            float bright = min(smoothstep(0.0f, 2.2f, base), smoothstep(0.0f, 2.2f, x));
            float dark = min(smoothstep(0.0f, 2.2f, -base), smoothstep(0.0f, 2.2f, -x));
            dark *= smoothstep(-10.0f, -5.0f, x);
            delta = gains.x * bright + gains.y * dark;
            if (tone.w != 0.0f) {
                float mid = 1.0f - smoothstep(0.4f, 3.0f, abs(base + delta));
                delta += 0.65f * tone.w * mid * (x - base);
            }
        }
        // Broad global contrast about middle grey, then low/high end shaping.
        // The corrections are bounded in stops and never clip HDR or create a
        // pedestal at digital zero.
        float e = x + delta;
        delta += 1.6f * tone.x * e / (3.0f + abs(e));
        e = x + delta;
        delta += 1.4f * (tone.y * smoothstep(0.25f, 4.5f, -e)
                      + tone.z * smoothstep(0.25f, 4.5f, e));
        c *= exp2(delta);
    }
    if (colour.y != 0.0f || colour.z != 0.0f) {
        float y = dot(c, luminance.xyz);
        float hi = max(c.r, max(c.g, c.b));
        float lo = min(c.r, min(c.g, c.b));
        float muted = 1.0f - clamp((hi - lo) / max(max(abs(hi), abs(lo)), 1e-4f), 0.0f, 1.0f);
        float chroma = (1.0f + colour.z) * (1.0f + 0.85f * colour.y * muted);
        c = float3(y) + chroma * (c - float3(y));
    }
    out[i] = all(isfinite(c)) ? c : source;
}
