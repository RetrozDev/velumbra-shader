// Extracted from Horizon's horizon-shader-api (MIT, Copyright (c) 2026 Ludovic Marie and the Horizon contributors), commit 9f42064.
struct HorizonWeatherIn {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) light: vec2<f32>,
    @location(2) world: vec3<f32>,
    @location(3) @interpolate(flat) snow: u32,
}
@fragment fn horizon_fs_weather(in: HorizonWeatherIn) -> @location(0) vec4<f32> {
    return weather(WeatherInput(in.color, in.light, in.world, in.snow != 0u));
}
