fn weather(input: WeatherInput) -> vec4<f32> {
    if !in_overworld() {
        return input.color;
    }
    let base = to_linear(input.color.rgb);
    let sky_level = input.light.y;
    let block_level = input.light.x;
    let light = sky_ambient() * sky_level * sky_level * 1.4
        + direct_light() * 0.12 * sky_level
        + vec3<f32>(1.0, 0.56, 0.24) * pow(block_level, 4.0) * 1.5
        + vec3<f32>(0.01);
    let color = base * light * select(0.9, 1.3, input.snow);
    let alpha = input.color.a * select(0.5, 0.85, input.snow);
    return vec4<f32>(encode_display(color), alpha);
}
