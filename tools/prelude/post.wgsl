@group(1) @binding(0) var scene_color: texture_2d<f32>;
@group(1) @binding(1) var scene_depth: texture_depth_2d;
@group(1) @binding(2) var previous: texture_2d<f32>;
@group(1) @binding(3) var linear_sampler: sampler;
@group(1) @binding(4) var nearest_sampler: sampler;
@group(1) @binding(5) var history: texture_2d<f32>;
@group(1) @binding(6) var shadow_map: texture_depth_2d;
@group(1) @binding(7) var shadow_sampler: sampler_comparison;

fn shadow_distort(xy: vec2<f32>) -> vec2<f32> {
    let k = frame.shadow_distortion;
    return xy / (length(xy) * k + 1.0 - k);
}

fn shadow_position(position: vec3<f32>) -> vec3<f32> {
    let clip = frame.shadow_view_proj * vec4<f32>(position, 1.0);
    let xy = shadow_distort(clip.xy);
    return vec3<f32>(xy.x * 0.5 + 0.5, 0.5 - xy.y * 0.5, min(clip.z, 1.0));
}

fn depth_at(uv: vec2<f32>) -> f32 {
    let size = vec2<f32>(textureDimensions(scene_depth));
    let texel = vec2<i32>(clamp(uv * size, vec2<f32>(0.0), size - 1.0));
    return textureLoad(scene_depth, texel, 0);
}

fn view_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

struct HarnessPostOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@fragment fn harness_post(in: HarnessPostOut) -> @location(0) vec4<f32> {
    let color = textureSampleLevel(previous, linear_sampler, in.uv, 0.0);
    return post(PostInput(in.uv, in.position.xy, color, depth_at(in.uv)));
}
