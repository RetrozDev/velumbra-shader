struct HarnessSkyIn {
    @builtin(position) position: vec4<f32>,
    @location(0) direction: vec3<f32>,
    @location(1) color: vec4<f32>,
}

@fragment fn harness_sky(in: HarnessSkyIn) -> @location(0) vec4<f32> {
    return sky(SkyInput(normalize(in.direction), in.color));
}
