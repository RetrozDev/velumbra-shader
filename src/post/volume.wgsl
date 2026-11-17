override volumetric_clouds: bool = true;
override cirrus_clouds: bool = true;
override light_shafts: bool = true;
override shaft_strength: f32 = 1.0;
override cave_fog: bool = true;

struct Medium {
    inscatter: vec3<f32>,
    transmittance: f32,
}

fn cloud_steps() -> i32 {
    return array<i32, 4>(8, 14, 22, 32)[min(quality, 3u)];
}

fn cloud_light_steps() -> i32 {
    return array<i32, 4>(2, 3, 4, 6)[min(quality, 3u)];
}

fn shaft_steps() -> i32 {
    return array<i32, 4>(6, 10, 16, 24)[min(quality, 3u)];
}

fn mist_steps() -> i32 {
    return array<i32, 4>(3, 4, 6, 8)[min(quality, 3u)];
}

fn cumulus_density(p: vec3<f32>, detail: bool) -> f32 {
    let h = (p.y - CUMULUS_BOTTOM) / (CUMULUS_TOP - CUMULUS_BOTTOM);
    if h <= 0.0 || h >= 1.0 {
        return 0.0;
    }
    let q = p + vec3<f32>(cloud_wind().x, 0.0, cloud_wind().y);
    let coverage = cloud_coverage_map(q.xz) + cumulus_coverage_bias();
    if coverage < 0.35 {
        return 0.0;
    }
    let profile = smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.35, h);
    var shape = value_noise3(q / 190.0) * 0.62 + value_noise3(q / 85.0) * 0.38;
    if detail {
        shape -= value_noise3(q / 29.0 + frame.time * 0.01) * 0.16 * (1.0 - h * 0.5);
    }
    return clamp((shape * profile + coverage - 1.0) * 3.2, 0.0, 1.0);
}

fn light_toward() -> vec3<f32> {
    return select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.05);
}

// Wrenninge's approximation of multiple scattering: octaves of ever weaker extinction and a
// flatter phase, which brightens the cores and silver linings of thick clouds.
fn multiple_scattering(optical_depth: f32, cos_theta: f32) -> f32 {
    var sum = 0.0;
    var a = 1.0;
    var b = 1.0;
    var c = 1.0;
    for (var i = 0; i < 3; i++) {
        let phase = mix(henyey_greenstein(cos_theta, -0.15 * c), henyey_greenstein(cos_theta, 0.7 * c), 0.7);
        sum += b * phase * exp(-optical_depth * a);
        a *= 0.45;
        b *= 0.55;
        c *= 0.5;
    }
    return sum * 4.0 * PI_F32;
}

fn cumulus(dir: vec3<f32>, limit: f32, jitter: f32) -> Medium {
    var medium = Medium(vec3<f32>(0.0), 1.0);
    let camera_y = frame.camera_position.y;
    if abs(dir.y) < 1e-3 {
        return medium;
    }
    let t_bottom = (CUMULUS_BOTTOM - camera_y) / dir.y;
    let t_top = (CUMULUS_TOP - camera_y) / dir.y;
    let t_start = max(min(t_bottom, t_top), 0.0);
    let t_end = min(min(max(t_bottom, t_top), 9000.0), limit);
    if t_end <= t_start {
        return medium;
    }
    let steps = cloud_steps();
    let light_steps = cloud_light_steps();
    let step_len = (t_end - t_start) / f32(steps);
    let to_light = light_toward();
    let cos_theta = dot(dir, to_light);
    let sun = direct_light() * 1.4;
    let ambient = sky_radiance(vec3<f32>(0.0, 1.0, 0.0)) * 1.6 + vec3<f32>(0.002, 0.003, 0.006);
    let camera_xz = frame.camera_position.xz;

    for (var i = 0; i < 32; i++) {
        if i >= steps {
            break;
        }
        let t = t_start + step_len * (f32(i) + jitter);
        let local = dir * t;
        let p = vec3<f32>(local.x + camera_xz.x, local.y + camera_y, local.z + camera_xz.y);
        let density = cumulus_density(p, true);
        if density <= 0.0 {
            continue;
        }
        var light_depth = 0.0;
        for (var j = 0; j < 6; j++) {
            if j >= light_steps {
                break;
            }
            let reach = 36.0 * (f32(j) + 0.5) * (1.0 + f32(j) * 0.7);
            light_depth += cumulus_density(p + to_light * reach, false) * 36.0 * (1.0 + f32(j) * 0.7);
        }
        let extinction = density * 0.045;
        let step_t = exp(-extinction * step_len);
        let powder = 1.0 - exp(-density * 2.5);
        let h = (p.y - CUMULUS_BOTTOM) / (CUMULUS_TOP - CUMULUS_BOTTOM);
        let lit = sun * multiple_scattering(light_depth * 0.045, cos_theta) * mix(0.6, 1.0, powder)
            + ambient * mix(0.35, 1.0, h);
        medium.inscatter += medium.transmittance * (1.0 - step_t) * lit;
        medium.transmittance *= step_t;
        if medium.transmittance < 0.02 {
            break;
        }
    }
    let fade = exp(-t_start / 7000.0) * smoothstep(0.0, 0.06, abs(dir.y));
    medium.inscatter *= fade;
    medium.transmittance = mix(1.0, medium.transmittance, fade);
    return medium;
}

fn cirrus(dir: vec3<f32>) -> Medium {
    var medium = Medium(vec3<f32>(0.0), 1.0);
    if dir.y <= 0.0 {
        return medium;
    }
    let t = (CIRRUS_HEIGHT - frame.camera_position.y) / dir.y;
    if t <= 0.0 {
        return medium;
    }
    let xz = frame.camera_position.xz + dir.xz * t;
    let density = cirrus_density(xz) * smoothstep(0.0, 0.12, dir.y);
    if density <= 0.0 {
        return medium;
    }
    let cos_theta = dot(dir, light_toward());
    let phase = mix(henyey_greenstein(cos_theta, 0.6), henyey_greenstein(cos_theta, 0.0), 0.5) * 4.0 * PI_F32;
    let lit = direct_light() * phase * 0.5 + sky_radiance(vec3<f32>(0.0, 1.0, 0.0)) * 1.2;
    let alpha = density * 0.55;
    medium.inscatter = lit * alpha;
    medium.transmittance = 1.0 - alpha;
    return medium;
}

fn light_shaft_medium(dir: vec3<f32>, reach: f32, jitter: f32) -> Medium {
    var medium = Medium(vec3<f32>(0.0), 1.0);
    let underground = 1.0 - smoothstep(0.02, 0.4, frame.eye_light_smooth.y);
    let sun = direct_light();
    if !light_shafts || frame.has_shadow != 1u || underground >= 1.0 || luminance(sun) < 1e-4 {
        return medium;
    }
    let steps = shaft_steps();
    let distance = min(reach, frame.shadow_distance * 0.95);
    let step_len = distance / f32(steps);
    let underwater = frame.eye_in == 1u;
    let density = select(0.0045, 0.03, underwater) * (1.0 + frame.rain * 2.0) * shaft_strength;
    var lit = 0.0;
    for (var i = 0; i < 24; i++) {
        if i >= steps {
            break;
        }
        let p = dir * step_len * (f32(i) + jitter);
        let sp = shadow_position(p);
        var visible = 1.0;
        if all(sp.xy > vec2<f32>(0.0)) && all(sp.xy < vec2<f32>(1.0)) {
            visible = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
        }
        let height = p.y + frame.camera_position.y;
        let local = density * exp(-max(height - 64.0, 0.0) / 90.0);
        lit += visible * local * step_len * medium.transmittance;
        medium.transmittance *= exp(-local * step_len * 0.3);
    }
    let cos_theta = dot(dir, frame.light_direction);
    let phase = mix(henyey_greenstein(cos_theta, 0.0), henyey_greenstein(cos_theta, 0.72), 0.75) * 4.0 * PI_F32;
    let tint = select(vec3<f32>(1.0), vec3<f32>(0.25, 0.75, 0.85), underwater);
    medium.inscatter = sun * tint * phase * lit * 0.6 * (1.0 - underground);
    return medium;
}

// Drifting fog in caves and in the other dimensions, lit by the ambient and the light at the eye.
fn mist(dir: vec3<f32>, reach: f32, jitter: f32) -> Medium {
    var medium = Medium(vec3<f32>(0.0), 1.0);
    var amount = 0.0;
    var color = vec3<f32>(0.0);
    if in_overworld() {
        amount = (1.0 - smoothstep(0.05, 0.5, frame.eye_light_smooth.y)) * 0.05;
        color = vec3<f32>(0.03, 0.035, 0.045) + TORCH_COLOR * pow(frame.eye_light_smooth.x, 3.0) * 0.5;
    } else if in_nether() {
        amount = 0.035;
        color = to_linear(frame.fog_color) * 0.9 + vec3<f32>(0.08, 0.03, 0.01);
    } else {
        amount = 0.02;
        color = vec3<f32>(0.09, 0.06, 0.13);
    }
    if !cave_fog || amount <= 1e-4 {
        return medium;
    }
    amount *= fog_density;
    let steps = mist_steps();
    let distance = min(reach, 64.0);
    let step_len = distance / f32(steps);
    let drift = vec3<f32>(frame.time * 0.3, frame.time * 0.05, frame.time * 0.2);
    var optical = 0.0;
    for (var i = 0; i < 8; i++) {
        if i >= steps {
            break;
        }
        let p = dir * step_len * (f32(i) + jitter) + frame.camera_position;
        let n = value_noise3(p / 7.0 + drift) * 0.7 + value_noise3(p / 2.9 - drift) * 0.3;
        optical += amount * smoothstep(0.3, 0.8, n) * 2.0 * step_len;
    }
    medium.transmittance = exp(-optical);
    medium.inscatter = color * (1.0 - medium.transmittance);
    return medium;
}

fn combine(front: Medium, back: Medium) -> Medium {
    return Medium(front.inscatter + front.transmittance * back.inscatter, front.transmittance * back.transmittance);
}

fn post(input: PostInput) -> vec4<f32> {
    let p = scene_position(input.uv, input.depth);
    let distance = length(p);
    let dir = p / max(distance, 1e-4);
    let sky_pixel = input.depth <= 0.0;
    let noise = blue_noise(input.pixel);

    var medium = mist(dir, distance, noise.z);
    if in_overworld() {
        medium = combine(medium, light_shaft_medium(dir, select(distance, 256.0, sky_pixel), noise.x));
        var clouds = Medium(vec3<f32>(0.0), 1.0);
        if volumetric_clouds {
            clouds = cumulus(dir, select(distance, 1e9, sky_pixel), noise.y);
        }
        if cirrus_clouds && sky_pixel {
            clouds = combine(clouds, cirrus(dir));
        }
        medium = combine(medium, clouds);
    }
    let current = vec4<f32>(exposed(medium.inscatter), medium.transmittance);

    let before = previous_uv(p);
    if frame.delta_time <= 0.0 || !on_screen(before) {
        return vec4<f32>(current.rgb, max(current.a, 1e-3));
    }
    let history = textureSampleLevel(volume_history, linear_sampler, before, 0.0);
    if history.a <= 0.0 {
        return vec4<f32>(current.rgb, max(current.a, 1e-3));
    }
    let moved = length((before - input.uv) * frame.resolution) * 0.5;
    let weight = clamp(0.1 + moved * 0.08, 0.1, 0.6);
    let blended = mix(history, current, weight);
    return vec4<f32>(blended.rgb, max(blended.a, 1e-3));
}
