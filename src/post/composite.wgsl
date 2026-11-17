const UNDERWATER_ABSORPTION: vec3<f32> = vec3<f32>(0.22, 0.06, 0.045);

// The half-resolution volumetrics brought up to this pixel, weighting the four nearest texels
// by how close their depth is to this pixel's, so fog and clouds don't bleed across edges.
fn upsampled_volume(uv: vec2<f32>, distance: f32) -> vec4<f32> {
    let size = vec2<f32>(textureDimensions(volume));
    let base = uv * size - 0.5;
    let origin = floor(base);
    let f = base - origin;
    var sum = vec4<f32>(0.0);
    var weight_sum = 0.0;
    for (var i = 0; i < 4; i++) {
        let offset = vec2<f32>(f32(i & 1), f32(i >> 1));
        let texel = clamp(origin + offset, vec2<f32>(0.0), size - 1.0);
        let texel_uv = (texel + 0.5) / size;
        let neighbour = length(scene_position(texel_uv, depth_at(texel_uv)));
        let bilinear = mix(1.0 - f.x, f.x, offset.x) * mix(1.0 - f.y, f.y, offset.y);
        let w = bilinear / (1e-3 + abs(neighbour - distance) / max(distance, 1.0) * 8.0) + 1e-5;
        sum += textureLoad(volume, vec2<i32>(texel), 0) * w;
        weight_sum += w;
    }
    return sum / weight_sum;
}

fn overworld_fog(color: vec3<f32>, dir: vec3<f32>, distance: f32) -> vec3<f32> {
    let skyline_dir = normalize(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.5 + 0.03, dir.z));
    let height = max(frame.camera_position.y + dir.y * distance * 0.5 - 62.0, 0.0);
    let haze = 0.0016 * fog_density * (1.0 + frame.rain * 4.0) * exp(-height / 110.0);
    let outdoors = smoothstep(0.0, 0.3, frame.eye_light_smooth.y);
    let aerial = (1.0 - exp(-distance * haze)) * outdoors;
    var out = mix(color, exposed(sky_radiance(skyline_dir)), aerial);

    let edge_start = min(frame.fog_start, frame.render_distance * 0.7);
    let edge_end = max(min(frame.fog_end, frame.render_distance), edge_start + 1.0);
    let edge = smoothstep(edge_start, edge_end, distance);
    let sky_dir = normalize(vec3<f32>(dir.x, max(dir.y, 0.0), dir.z));
    return mix(out, exposed(sky_radiance(sky_dir)), edge);
}

fn dimension_fog(color: vec3<f32>, distance: f32) -> vec3<f32> {
    var fog_color = vec3<f32>(0.05, 0.035, 0.07);
    var start = frame.render_distance * 0.3;
    if in_nether() {
        fog_color = to_linear(frame.fog_color) * 0.8;
        start = 0.0;
    }
    let density = select(0.004, 0.012, in_nether()) * fog_density;
    let amount = 1.0 - exp(-max(distance - start, 0.0) * density);
    let edge = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 1.0), distance);
    return mix(color, exposed(fog_color), max(amount, edge));
}

fn post(input: PostInput) -> vec4<f32> {
    var color = load_color(input.color.rgb);
    let sky_pixel = input.depth <= 0.0;
    let p = scene_position(input.uv, input.depth);
    let distance = length(p);
    let dir = p / max(distance, 1e-4);

    if frame.eye_in == 1u {
        let transmit = exp(-UNDERWATER_ABSORPTION * min(distance, 96.0) * 0.6);
        let ambient = sky_ambient() * frame.eye_light_smooth.y + vec3<f32>(0.003);
        let deep = exposed(ambient * vec3<f32>(0.08, 0.3, 0.36) + direct_light() * vec3<f32>(0.01, 0.05, 0.06));
        color = color * transmit + deep * (1.0 - transmit);
    } else if frame.eye_in == 2u {
        color = mix(color, vec3<f32>(3.0, 0.9, 0.2), 1.0 - exp(-distance * 0.6));
    } else if !sky_pixel {
        if in_overworld() {
            color = overworld_fog(color, dir, distance);
        } else {
            color = dimension_fog(color, distance);
        }
    }

    let volume = upsampled_volume(input.uv, distance);
    color = color * volume.a + volume.rgb;

    let obscured = max(frame.blindness, frame.darkness);
    if obscured > 0.0 {
        color *= mix(1.0, exp(-distance * 0.25), obscured);
    }
    return vec4<f32>(color, input.color.a);
}
