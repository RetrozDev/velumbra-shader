fn weather(input: WeatherInput) -> vec4<f32> {
    let base = to_linear(input.color.rgb);
    let sky_level = input.light.y;
    var light = TORCH_COLOR * pow(input.light.x, 4.0) * 1.5 + vec3<f32>(0.01);
    if in_overworld() {
        light += sky_ambient() * sky_level * sky_level * 1.4 + direct_light() * 0.12 * sky_level;
    } else {
        light += dimension_ambient();
    }
    let color = base * light * select(0.9, 1.3, input.snow);
    let alpha = input.color.a * select(0.5, 0.85, input.snow);
    return vec4<f32>(store_color(color), alpha);
}
