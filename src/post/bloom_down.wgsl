// Keeps what is brighter than the picture's white, smoothly, so bloom grows from light sources.
fn bright_part(c: vec3<f32>) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let knee = 0.6;
    let threshold = 1.2;
    let soft = clamp(peak - threshold + knee, 0.0, 2.0 * knee);
    let amount = max(soft * soft / (4.0 * knee + 1e-4), peak - threshold) / max(peak, 1e-4);
    return c * max(amount, 0.0) + c * 0.04;
}

fn tap(uv: vec2<f32>) -> vec3<f32> {
    return min(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb, vec3<f32>(64.0));
}

// Jimenez's 13-tap downsample, its five boxes averaged by Karis' weights so single bright
// pixels don't flicker.
fn post(input: PostInput) -> vec4<f32> {
    let texel = 2.0 / vec2<f32>(textureDimensions(previous));
    let uv = input.uv;
    let a = tap(uv + texel * vec2<f32>(-2.0, -2.0));
    let b = tap(uv + texel * vec2<f32>(0.0, -2.0));
    let c = tap(uv + texel * vec2<f32>(2.0, -2.0));
    let d = tap(uv + texel * vec2<f32>(-2.0, 0.0));
    let e = tap(uv);
    let f = tap(uv + texel * vec2<f32>(2.0, 0.0));
    let g = tap(uv + texel * vec2<f32>(-2.0, 2.0));
    let h = tap(uv + texel * vec2<f32>(0.0, 2.0));
    let i = tap(uv + texel * vec2<f32>(2.0, 2.0));
    let j = tap(uv + texel * vec2<f32>(-1.0, -1.0));
    let k = tap(uv + texel * vec2<f32>(1.0, -1.0));
    let l = tap(uv + texel * vec2<f32>(-1.0, 1.0));
    let m = tap(uv + texel * vec2<f32>(1.0, 1.0));

    let boxes = array<vec3<f32>, 5>(
        (j + k + l + m) * 0.25,
        (a + b + d + e) * 0.25,
        (b + c + e + f) * 0.25,
        (d + e + g + h) * 0.25,
        (e + f + h + i) * 0.25,
    );
    let weights = array<f32, 5>(0.5, 0.125, 0.125, 0.125, 0.125);
    var sum = vec3<f32>(0.0);
    var total = 0.0;
    for (var n = 0; n < 5; n++) {
        let w = weights[n] / (1.0 + luminance(boxes[n]));
        sum += bright_part(boxes[n]) * w;
        total += w;
    }
    return vec4<f32>(sum / total, 1.0);
}
