// The material and vertex stages are drawn together, so they are validated as one module.
@group(1) @binding(0) var reflection: texture_2d<f32>;
@group(1) @binding(1) var reflection_sampler: sampler;
@group(1) @binding(2) var shadow_map: texture_depth_2d;
@group(1) @binding(3) var shadow_sampler: sampler_comparison;
@group(1) @binding(6) var opaque_depth: texture_depth_2d;
@group(1) @binding(7) var opaque_color: texture_2d<f32>;

fn shadow_distort(xy: vec2<f32>) -> vec2<f32> {
    let k = frame.shadow_distortion;
    return xy / (length(xy) * k + 1.0 - k);
}

fn shadow_position(position: vec3<f32>) -> vec3<f32> {
    let clip = frame.shadow_view_proj * vec4<f32>(position, 1.0);
    let xy = shadow_distort(clip.xy);
    return vec3<f32>(xy.x * 0.5 + 0.5, 0.5 - xy.y * 0.5, min(clip.z, 1.0));
}

struct HarnessMaterialIn {
    @builtin(position) position: vec4<f32>,
    @location(0) albedo: vec4<f32>,
    @location(1) tint: vec4<f32>,
    @location(2) light: vec2<f32>,
    @location(3) lightmap: vec3<f32>,
    @location(4) world: vec3<f32>,
    @location(5) uv: vec2<f32>,
    @location(6) @interpolate(flat) translucent: u32,
    @location(7) @interpolate(flat) tags: u32,
    @location(8) @interpolate(flat) face: u32,
    @location(9) @interpolate(flat) fluid: u32,
    @location(10) @interpolate(flat) emission: f32,
    @location(11) @interpolate(flat) material: u32,
}

@fragment fn harness_material(in: HarnessMaterialIn) -> @location(0) vec4<f32> {
    let n = normalize(cross(dpdx(in.world), dpdy(in.world)));
    let input = MaterialInput(in.albedo, in.tint, in.light, in.lightmap, in.world, in.uv,
        in.translucent != 0u, in.tags, in.material, in.position.xy / frame.resolution, in.face,
        in.fluid, in.emission, n, vec4<f32>(1.0, 0.0, 0.0, 1.0), vec3<f32>(0.0), 0.0);
    return material(input).color;
}

@vertex fn harness_vertex(
    @location(0) position: vec3<f32>, @location(1) uv: vec2<f32>, @location(2) light: vec2<f32>,
    @location(3) tint: vec4<f32>, @location(4) material: u32, @location(5) flags: u32,
) -> @builtin(position) vec4<f32> {
    let input = VertexInput(position, uv, material, light, tint, flags & 7u, flags >> 31u);
    return frame.projection * frame.view * vec4<f32>(vertex(input), 1.0);
}
