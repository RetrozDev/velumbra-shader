override fog_density: f32 = 1.0;

const SKY_DISTANCE: f32 = 4096.0;

// Camera-relative position of the pixel at `uv`; the sky is pushed far along its ray.
fn scene_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    if depth <= 0.0 {
        return normalize(view_position(uv, 1e-6)) * SKY_DISTANCE;
    }
    return view_position(uv, depth);
}

// Where the camera-relative point `p` was on screen last frame (x < 0 when it was not).
fn previous_uv(p: vec3<f32>) -> vec2<f32> {
    let clip = frame.previous_view_projection * vec4<f32>(p + frame.camera_motion, 1.0);
    if clip.w <= 1e-4 {
        return vec2<f32>(-1.0);
    }
    let ndc = clip.xy / clip.w;
    return vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

fn on_screen(uv: vec2<f32>) -> bool {
    return all(uv >= vec2<f32>(0.0)) && all(uv <= vec2<f32>(1.0));
}

// Light a picture holds, in the units of the stored frame (exposure applied).
fn exposed(hdr: vec3<f32>) -> vec3<f32> {
    return hdr * scene_exposure();
}
