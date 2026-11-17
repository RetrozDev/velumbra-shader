override bloom: f32 = 0.6;
override saturation: f32 = 1.1;
override warmth: f32 = 1.0;
override vignette: bool = true;

fn bloom_source(uv: vec2<f32>) -> vec3<f32> {
    let c = to_linear(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
    let knee = smoothstep(0.35, 0.9, luminance(c));
    return c * knee;
}

// Two golden-angle spirals: a tight core and a wide, soft halo.
fn gather_bloom(uv: vec2<f32>, dither: f32) -> vec3<f32> {
    let aspect = vec2<f32>(frame.resolution.y / frame.resolution.x, 1.0);
    let angle_step = 2.39996323;
    var core = vec3<f32>(0.0);
    var halo = vec3<f32>(0.0);
    for (var i = 0; i < 12; i++) {
        let fi = f32(i) + 0.5;
        let a = fi * angle_step + dither * 2.0 * PI_F32;
        let offset = vec2<f32>(cos(a), sin(a)) * aspect;
        let r = sqrt(fi / 12.0);
        core += bloom_source(uv + offset * r * 0.012);
        halo += bloom_source(uv + offset * r * 0.05);
    }
    return core / 12.0 * 0.6 + halo / 12.0 * 0.4;
}

fn post(input: PostInput) -> vec4<f32> {
    var color = to_linear(input.color.rgb);
    let dither = pixel_dither(input.pixel);

    if bloom > 0.0 {
        let glow = gather_bloom(input.uv, dither);
        color += glow * bloom * 0.45 * (1.0 + frame.rain * 0.5);
    }

    let warm = vec3<f32>(1.05, 1.0, 0.92);
    color *= mix(vec3<f32>(1.0), warm, warmth);
    let grey = luminance(color);
    color = max(mix(vec3<f32>(grey), color, saturation), vec3<f32>(0.0));

    var g = to_gamma(color);
    g = mix(g, g * g * (3.0 - 2.0 * g), 0.12);

    if vignette {
        let centred = input.uv - 0.5;
        let falloff = 1.0 - dot(centred, centred) * 0.55;
        g *= clamp(falloff, 0.0, 1.0);
    }

    g += (dither - 0.5) / 255.0;
    return vec4<f32>(clamp(g, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}
