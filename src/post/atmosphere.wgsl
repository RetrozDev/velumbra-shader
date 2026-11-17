override fog_density: f32 = 1.0;
override volumetric_light: u32 = 2u;
override volumetric_strength: f32 = 1.0;

const UNDERWATER_ABSORPTION: vec3<f32> = vec3<f32>(0.22, 0.06, 0.045);

fn screen_blend(base: vec3<f32>, light: vec3<f32>) -> vec3<f32> {
    return 1.0 - (1.0 - base) * (1.0 - clamp(light, vec3<f32>(0.0), vec3<f32>(1.0)));
}

fn light_shafts(dir: vec3<f32>, max_distance: f32, dither: f32) -> vec3<f32> {
    if volumetric_light == 0u || frame.has_shadow != 1u {
        return vec3<f32>(0.0);
    }
    var steps = 8;
    if volumetric_light == 2u {
        steps = 14;
    } else if volumetric_light >= 3u {
        steps = 24;
    }
    let reach = min(max_distance, frame.shadow_distance * 0.95);
    let step_len = reach / f32(steps);
    let underwater = frame.eye_in == 1u;
    let density = select(0.0045, 0.03, underwater) * (1.0 + frame.rain * 2.0) * volumetric_strength;
    var transmittance = 1.0;
    var lit = 0.0;
    for (var i = 0; i < steps; i++) {
        let t = step_len * (f32(i) + dither);
        let p = dir * t;
        let sp = shadow_position(p);
        var visible = 1.0;
        if all(sp.xy > vec2<f32>(0.0)) && all(sp.xy < vec2<f32>(1.0)) {
            visible = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
        }
        let height = p.y + frame.camera_position.y;
        let medium = density * exp(-max(height - 64.0, 0.0) / 90.0);
        lit += visible * medium * step_len * transmittance;
        transmittance *= exp(-medium * step_len);
    }
    let cos_theta = dot(dir, frame.light_direction);
    let phase = mix(henyey_greenstein(cos_theta, 0.0), henyey_greenstein(cos_theta, 0.72), 0.75) * 4.0 * PI_F32;
    var tint = vec3<f32>(1.0);
    if underwater {
        tint = vec3<f32>(0.25, 0.75, 0.85);
    }
    let cave = smoothstep(0.05, 0.6, frame.eye_light_smooth.y);
    return direct_light() * tint * phase * lit * cave * 0.6;
}

fn post(input: PostInput) -> vec4<f32> {
    if !in_overworld() {
        return input.color;
    }
    var color = to_linear(input.color.rgb);
    let sky_pixel = input.depth <= 0.0;
    let far_point = reconstruct_position(input.uv, max(input.depth, 1e-6));
    let dir = normalize(far_point);
    var distance = length(far_point);
    if sky_pixel {
        distance = frame.far;
    }
    let dither = pixel_dither(input.pixel);

    if frame.eye_in == 1u {
        let transmit = exp(-UNDERWATER_ABSORPTION * distance * 0.6);
        let ambient = sky_ambient() * frame.eye_light_smooth.y + vec3<f32>(0.003);
        let deep = display_linear(ambient * vec3<f32>(0.08, 0.3, 0.36) + direct_light() * vec3<f32>(0.01, 0.05, 0.06));
        color = color * transmit + deep * (1.0 - transmit);
        let shafts = display_linear(light_shafts(dir, min(distance, 48.0), dither));
        return vec4<f32>(to_gamma(screen_blend(color, shafts)), 1.0);
    }

    if !sky_pixel {
        let horizon_dir = normalize(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.5 + 0.03, dir.z));
        let fog_sky = sky_radiance(horizon_dir);
        let camera_y = frame.camera_position.y;
        let height = max(camera_y + dir.y * distance * 0.5 - 62.0, 0.0);
        let haze = 0.0016 * fog_density * (1.0 + frame.rain * 4.0) * exp(-height / 110.0);
        let aerial = 1.0 - exp(-distance * haze);
        let fog_color = display_linear(fog_sky);
        color = mix(color, fog_color, aerial * smoothstep(0.0, 0.3, frame.eye_light_smooth.y));

        let edge_start = min(frame.fog_start, frame.render_distance * 0.7);
        let edge_end = max(min(frame.fog_end, frame.render_distance), edge_start + 1.0);
        let edge = smoothstep(edge_start, edge_end, distance);
        let sky_dir = normalize(vec3<f32>(dir.x, max(dir.y, 0.0), dir.z));
        color = mix(color, display_linear(sky_radiance(sky_dir)), edge);
    }

    let reach = select(distance, 200.0, sky_pixel);
    let shafts = display_linear(light_shafts(dir, reach, dither));
    color = screen_blend(color, shafts);
    return vec4<f32>(to_gamma(color), 1.0);
}
