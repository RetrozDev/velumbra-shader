override temporal_filter: bool = true;

// History blends tone-weighted (c / (1 + max c)), so a few very bright pixels don't own it.
fn compress(c: vec3<f32>) -> vec3<f32> {
    return c / (1.0 + max(c.r, max(c.g, c.b)));
}

fn expand(c: vec3<f32>) -> vec3<f32> {
    return c / max(1.0 - max(c.r, max(c.g, c.b)), 1e-3);
}

fn to_ycocg(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
        0.5 * c.r - 0.5 * c.b,
        -0.25 * c.r + 0.5 * c.g - 0.25 * c.b,
    );
}

fn from_ycocg(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

// Temporal accumulation: last frame's resolved picture, reprojected through the depth and
// clipped to the colour range around this pixel, settles the noise of the soft shadows and
// ray-marched volumetrics.
fn post(input: PostInput) -> vec4<f32> {
    let current = input.color.rgb;
    if !temporal_filter || frame.delta_time <= 0.0 {
        return vec4<f32>(current, input.color.a);
    }
    let p = scene_position(input.uv, input.depth);
    let before = previous_uv(p);
    if !on_screen(before) {
        return vec4<f32>(current, input.color.a);
    }

    let texel = vec2<i32>(input.pixel);
    let size = vec2<i32>(textureDimensions(previous)) - 1;
    var mean = vec3<f32>(0.0);
    var square = vec3<f32>(0.0);
    for (var i = 0; i < 9; i++) {
        let offset = vec2<i32>(i % 3 - 1, i / 3 - 1);
        let c = to_ycocg(compress(textureLoad(previous, clamp(texel + offset, vec2<i32>(0), size), 0).rgb));
        mean += c;
        square += c * c;
    }
    mean /= 9.0;
    let sigma = sqrt(max(square / 9.0 - mean * mean, vec3<f32>(0.0)));
    let low = mean - sigma * 1.25;
    let high = mean + sigma * 1.25;

    let past = to_ycocg(compress(textureSampleLevel(history, linear_sampler, before, 0.0).rgb));
    let clipped = clamp(past, low, high);
    let moved = length((before - input.uv) * frame.resolution);
    let weight = clamp(0.08 + moved * 0.04, 0.08, 0.5);
    let resolved = mix(clipped, to_ycocg(compress(current)), weight);
    return vec4<f32>(expand(from_ycocg(resolved)), input.color.a);
}
