// Validation stand-in for the declarations Horizon prepends to every stage (shader API 0.1).
// Field types follow Horizon's shaders reference; layout and bindings here are arbitrary.

struct Frame {
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
    view_inverse: mat4x4<f32>,
    projection_inverse: mat4x4<f32>,
    camera_position: vec3<f32>,
    time: f32,
    sun_direction: vec3<f32>,
    day_time: f32,
    moon_direction: vec3<f32>,
    game_time: f32,
    sky_color: vec3<f32>,
    rain: f32,
    fog_color: vec3<f32>,
    thunder: f32,
    resolution: vec2<f32>,
    eye_light: vec2<f32>,
    fog_start: f32,
    fog_end: f32,
    render_distance: f32,
    far: f32,
    night_vision: f32,
    blindness: f32,
    darkness: f32,
    brightness: f32,
    eye_in: u32,
    dimension: i32,
    frame_index: u32,
    hide_gui: u32,
    precipitation: u32,
    temperature: f32,
    downfall: f32,
    wetness: f32,
    previous_view_projection: mat4x4<f32>,
    camera_motion: vec3<f32>,
    delta_time: f32,
    eye_light_smooth: vec2<f32>,
    in_water: f32,
    in_lava: f32,
    water_plane: f32,
    has_reflection: u32,
    reflection_resolution: vec2<f32>,
    mods: array<vec4<f32>, 8>,
    light_direction: vec3<f32>,
    has_shadow: u32,
    shadow_view_proj: mat4x4<f32>,
    shadow_distance: f32,
    shadow_distortion: f32,
    shadow_resolution: f32,
    shadow_center_texel: f32,
}

@group(0) @binding(0) var<uniform> frame: Frame;

struct SkyInput {
    direction: vec3<f32>,
    color: vec4<f32>,
}

struct MaterialInput {
    albedo: vec4<f32>,
    tint: vec4<f32>,
    light: vec2<f32>,
    lightmap: vec3<f32>,
    position: vec3<f32>,
    uv: vec2<f32>,
    translucent: bool,
    tags: u32,
    material: u32,
    screen: vec2<f32>,
    face: u32,
    fluid: u32,
    emission: f32,
    normal: vec3<f32>,
    tangent: vec4<f32>,
    colored_light: vec3<f32>,
    displaced: f32,
}

struct Surface {
    color: vec4<f32>,
}

struct VertexInput {
    position: vec3<f32>,
    uv: vec2<f32>,
    material: u32,
    light: vec2<f32>,
    tint: vec4<f32>,
    face: u32,
    fluid: u32,
}

struct WeatherInput {
    color: vec4<f32>,
    light: vec2<f32>,
    position: vec3<f32>,
    snow: bool,
}

struct PostInput {
    uv: vec2<f32>,
    pixel: vec2<f32>,
    color: vec4<f32>,
    depth: f32,
}
