// Keeps this frame's volumetrics for the next one's temporal blend.
fn post(input: PostInput) -> vec4<f32> {
    return textureLoad(volume, vec2<i32>(input.pixel), 0);
}
