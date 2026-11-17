// Extracted from Horizon's horizon-shader-api (MIT, Copyright (c) 2026 Ludovic Marie and the Horizon contributors), commit 9f42064.
struct HorizonSkyIn {
    @builtin(position) position: vec4<f32>,
    @location(0) direction: vec3<f32>,
    @location(1) color: vec4<f32>,
}
@fragment fn horizon_fs_sky(in: HorizonSkyIn) -> @location(0) vec4<f32> {
    return sky(SkyInput(normalize(in.direction), in.color));
}
