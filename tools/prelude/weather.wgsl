struct HarnessWeatherIn {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) light: vec2<f32>,
    @location(2) world: vec3<f32>,
    @location(3) @interpolate(flat) snow: u32,
}

@fragment fn harness_weather(in: HarnessWeatherIn) -> @location(0) vec4<f32> {
    return weather(WeatherInput(in.color, in.light, in.world, in.snow != 0u));
}
