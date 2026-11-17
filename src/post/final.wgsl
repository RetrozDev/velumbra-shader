override bloom: f32 = 0.6;
override saturation: f32 = 1.1;
override warmth: f32 = 1.0;
override vignette: bool = true;

// The same curve the stages stored the world through, so vanilla's own draws come out as they
// went in; then a warm grade in display space.
fn post(input: PostInput) -> vec4<f32> {
    var hdr = input.color.rgb;
    if bloom > 0.0 {
        let glow = textureSampleLevel(bloom_blur, linear_sampler, input.uv, 0.0).rgb;
        hdr += glow * bloom * 0.5 * (1.0 + frame.rain * 0.5);
    }

    var color = 1.0 - exp(-max(hdr, vec3<f32>(0.0)));
    color *= mix(vec3<f32>(1.0), vec3<f32>(1.05, 1.0, 0.92), warmth);
    color = max(mix(vec3<f32>(luminance(color)), color, saturation), vec3<f32>(0.0));

    var g = to_gamma(color);
    g = mix(g, g * g * (3.0 - 2.0 * g), 0.12);
    if vignette {
        let centred = input.uv - 0.5;
        g *= clamp(1.0 - dot(centred, centred) * 0.55, 0.0, 1.0);
    }
    g += (blue_noise(input.pixel).w - 0.5) / 255.0;
    return vec4<f32>(clamp(g, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
