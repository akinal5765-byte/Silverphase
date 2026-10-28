#include <metal_stdlib>
using namespace metal;
// Linked from the unchanged desktop Shaders.metal in SilverphaseUI.metallib.
float3 developPaper(float3 printed, float t);
struct MobileDevelopVertex { float4 position [[position]]; float2 uv; };
vertex MobileDevelopVertex mobileDevelopVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}
fragment float4 mobileDevelopFragment(MobileDevelopVertex in [[stage_in]],
    texture2d<float> printed [[texture(0)]], texture2d<float> negative [[texture(1)]],
    constant float &progress [[buffer(0)]], constant uint &scanStyle [[buffer(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 film = negative.sample(s, in.uv).rgb;
    float3 paper = printed.sample(s, in.uv).rgb;
    if (progress <= 0) return float4(film, 1);
    if (progress >= 1) return float4(paper, 1);
    if (scanStyle != 0) return float4(mix(film, paper, smoothstep(0.0, 1.0, progress)), 1);
    float t = saturate((progress - 0.10) / 0.90);
    return float4(mix(film, developPaper(paper, t), smoothstep(0.0, 0.10, progress)), 1);
}
// Same texel-centred Cineon lookup as desktop Shaders.metal's layer2.
kernel void mobileCineonView(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             texture3d<float> lut [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    float n = float(lut.get_width());
    float3 c = lut.sample(s, (clamp(src.read(gid).rgb, 0.0f, 1.0f) * (n - 1.0f) + 0.5f) / n).rgb;
    dst.write(float4(c, 1), gid);
}
