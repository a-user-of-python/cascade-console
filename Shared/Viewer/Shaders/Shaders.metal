//
//  Shaders.metal
//  Cascade Console - Viewer
//
//  Direct lighting only: one headlight-style directional light plus a
//  hemisphere ambient term. No ray tracing of any kind (standing rule).
//  Section clipping is a fragment discard against a world-space plane.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct Uniforms {
    float4x4 mvp;
    float4x4 model;
    float4   color;          // RGBA, linear
    float4   sectionPlane;   // xyz = normal, w = constant
    uint     sectionEnabled; // 0 / 1
    uint     padding0;
    uint     padding1;
    uint     padding2;
};

struct VertexOut {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
};

vertex VertexOut meshVertex(VertexIn in [[stage_in]],
                            constant Uniforms &u [[buffer(1)]]) {
    VertexOut out;
    float4 world = u.model * float4(in.position, 1.0);
    out.worldPosition = world.xyz;
    // Model matrices here are translation-only (explode) or identity,
    // so transforming the normal by the model rotation part is exact.
    out.worldNormal = normalize((u.model * float4(in.normal, 0.0)).xyz);
    out.clipPosition = u.mvp * float4(in.position, 1.0);
    return out;
}

fragment float4 meshFragment(VertexOut in [[stage_in]],
                             constant Uniforms &u [[buffer(1)]]) {
    if (u.sectionEnabled != 0) {
        if (dot(in.worldPosition, u.sectionPlane.xyz) + u.sectionPlane.w > 0.0) {
            discard_fragment();
        }
    }
    float3 n = normalize(in.worldNormal);
    float3 lightDir = normalize(float3(0.4, 0.6, 0.75));
    float diffuse = max(dot(n, lightDir), 0.0);
    float3 ambient = mix(float3(0.22), float3(0.38), n.z * 0.5 + 0.5);
    float3 rgb = u.color.rgb * (ambient + diffuse * 0.75);
    return float4(rgb, u.color.a);
}

// MARK: - Lines (grid, axes, edge overlay, measure)

struct LineVertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct LineUniforms {
    float4x4 mvp;
};

struct LineOut {
    float4 clipPosition [[position]];
    float4 color;
};

vertex LineOut lineVertex(LineVertexIn in [[stage_in]],
                          constant LineUniforms &u [[buffer(1)]]) {
    LineOut out;
    out.clipPosition = u.mvp * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 lineFragment(LineOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Background gradient (fullscreen triangle)

struct BackgroundUniforms {
    float4 topColor;
    float4 bottomColor;
};

struct BackgroundOut {
    float4 clipPosition [[position]];
    float  y;               // 0 at bottom, 1 at top of the view
};

vertex BackgroundOut backgroundVertex(uint vid [[vertex_id]],
                                      constant BackgroundUniforms &u [[buffer(0)]]) {
    // One oversized triangle covering the viewport.
    float2 p = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
    BackgroundOut out;
    out.clipPosition = float4(p, 1.0, 1.0);   // drawn at the far plane
    out.y = p.y * 0.5 + 0.5;
    return out;
}

fragment float4 backgroundFragment(BackgroundOut in [[stage_in]],
                                   constant BackgroundUniforms &u [[buffer(0)]]) {
    return mix(u.bottomColor, u.topColor, in.y);
}
