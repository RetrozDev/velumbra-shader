// Two golden-angle spirals over the quarter-resolution bright parts: a tight glow and a wide,
// faint halo, roughly the falloff of light scattered in a lens and the eye.
fn post(input: PostInput) -> vec4<f32> {
    let size = vec2<f32>(textureDimensions(bloom_down));
    let texel = 1.0 / size;
    let rotation = blue_noise(input.pixel).x * 2.0 * PI_F32;
    var core = textureSampleLevel(bloom_down, linear_sampler, input.uv, 0.0).rgb;
    var halo = vec3<f32>(0.0);
    for (var i = 0; i < 12; i++) {
        let fi = f32(i) + 0.5;
        let a = fi * GOLDEN_ANGLE + rotation;
        let offset = vec2<f32>(cos(a), sin(a)) * sqrt(fi / 12.0);
        core += textureSampleLevel(bloom_down, linear_sampler, input.uv + offset * texel * 4.0, 0.0).rgb;
        halo += textureSampleLevel(bloom_down, linear_sampler, input.uv + offset * texel * 18.0, 0.0).rgb;
    }
    return vec4<f32>(core / 13.0 * 0.65 + halo / 12.0 * 0.35, 1.0);
}
