override shadows: bool = true;
override shadow_softness: f32 = 1.0;

// The ground one shadow texel covers at `p`, which the distortion stretches away from the centre.
fn shadow_texel_size(p: vec3<f32>) -> f32 {
    let clip = frame.shadow_view_proj * vec4<f32>(p, 1.0);
    let k = frame.shadow_distortion;
    let stretch = (length(clip.xy) * k + 1.0 - k) / max(1.0 - k, 1e-3);
    return frame.shadow_center_texel * stretch * stretch;
}

// Shadow-map depth units per block along the light.
fn shadow_depth_scale() -> f32 {
    let m = frame.shadow_view_proj;
    return max(length(vec3<f32>(m[0][2], m[1][2], m[2][2])), 1e-6);
}

fn vogel_disk(i: i32, count: i32, rotation: f32) -> vec2<f32> {
    let r = sqrt((f32(i) + 0.5) / f32(count));
    let a = f32(i) * GOLDEN_ANGLE + rotation;
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn caustics(world: vec3<f32>, t: f32) -> f32 {
    let p = world.xz * 0.9 + world.y * 0.3;
    let a = value_noise2(p + vec2<f32>(t * 0.6, t * 0.4));
    let b = value_noise2(p * 1.7 - vec2<f32>(t * 0.5, -t * 0.3) + 13.7);
    let c = 1.0 - abs(a - b) * 2.4;
    return 0.35 + 1.6 * pow(clamp(c, 0.0, 1.0), 6.0);
}

fn blocker_taps() -> i32 {
    return array<i32, 4>(0, 5, 8, 12)[min(quality, 3u)];
}

fn filter_taps() -> i32 {
    return array<i32, 4>(4, 8, 12, 16)[min(quality, 3u)];
}

// Sunlight reaching `p`: percentage-closer soft shadows whose penumbra widens with the distance
// to the occluder, tinted by the stained glass or water the light went through.
fn sun_shadow(p: vec3<f32>, n: vec3<f32>, foliage: bool, noise: vec2<f32>) -> vec3<f32> {
    let texel = shadow_texel_size(p);
    let offset_dir = select(n, frame.light_direction, foliage);
    let sp = shadow_position(p + offset_dir * texel * 1.5);
    if any(sp.xy <= vec2<f32>(0.0)) || any(sp.xy >= vec2<f32>(1.0)) || sp.z >= 1.0 {
        return vec3<f32>(1.0);
    }
    let resolution = max(frame.shadow_resolution, 1.0);
    let depth_scale = shadow_depth_scale();
    let bias = depth_scale * texel * 0.6;
    let receiver = sp.z - bias;
    let rotation = noise.x * 2.0 * PI_F32;
    let max_radius = clamp(0.5 * shadow_softness / max(texel, 1e-4), 1.0, 14.0);

    var radius = 0.75 + shadow_softness;
    let searches = blocker_taps();
    if searches > 0 {
        var blocker_sum = 0.0;
        var blockers = 0;
        for (var i = 0; i < 12; i++) {
            if i >= searches {
                break;
            }
            let uv = sp.xy + vogel_disk(i, searches, rotation) * max_radius / resolution;
            let d = textureLoad(shadow_map, vec2<i32>(uv * resolution), 0);
            if d < receiver {
                blocker_sum += d;
                blockers += 1;
            }
        }
        if blockers == 0 {
            return translucent_tint(p, sp, receiver, 1.0, depth_scale, resolution);
        }
        let occluder_blocks = (receiver - blocker_sum / f32(blockers)) / depth_scale;
        radius = clamp(occluder_blocks * 0.035 * shadow_softness / max(texel, 1e-4), 0.6, max_radius);
    }

    let taps = filter_taps();
    var lit = 0.0;
    for (var i = 0; i < 16; i++) {
        if i >= taps {
            break;
        }
        let uv = sp.xy + vogel_disk(i, taps, rotation + 1.3) * radius / resolution;
        lit += textureSampleCompareLevel(shadow_map, shadow_sampler, uv, receiver);
    }
    lit /= f32(taps);
    if lit <= 0.001 {
        return vec3<f32>(0.0);
    }
    return translucent_tint(p, sp, receiver, lit, depth_scale, resolution);
}

fn translucent_tint(p: vec3<f32>, sp: vec3<f32>, receiver: f32, lit: f32, depth_scale: f32, resolution: f32) -> vec3<f32> {
    let clear = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, sp.xy, receiver);
    let covered = max(lit - clear, 0.0);
    if covered <= 0.001 {
        return vec3<f32>(lit);
    }
    let color_texel = vec2<i32>(sp.xy * vec2<f32>(textureDimensions(shadow_color)));
    let surface = textureLoad(shadow_color, color_texel, 0);
    var tint = mix(vec3<f32>(1.0), to_linear(surface.rgb), surface.a);
    if surface.a >= 0.999 {
        let top = textureLoad(shadow_map_translucent, vec2<i32>(sp.xy * resolution), 0);
        let depth = max((receiver - top) / depth_scale, 0.0);
        tint = exp(-WATER_ABSORPTION * depth);
        if quality >= QUALITY_MEDIUM {
            tint *= caustics(p + frame.camera_position, frame.time);
        }
    }
    return vec3<f32>(lit - covered) + tint * covered;
}
