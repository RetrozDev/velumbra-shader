override cloud_quality: u32 = 2u;
override cloud_coverage: f32 = 0.5;

fn cloud_density(p: vec3<f32>, detail: bool) -> f32 {
    let h = (p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM);
    if h <= 0.0 || h >= 1.0 {
        return 0.0;
    }
    let drift = vec3<f32>(cloud_wind().x, 0.0, cloud_wind().y);
    let q = p + drift;
    let coverage = cloud_coverage_map(q.xz) + mix(-0.28, 0.32, cloud_coverage) + frame.rain * 0.3;
    let profile = smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.35, h);
    var shape = value_noise3(q / 190.0) * 0.62 + value_noise3(q / 85.0) * 0.38;
    if detail {
        shape -= value_noise3(q / 29.0 + frame.time * 0.01) * 0.16 * (1.0 - h * 0.5);
    }
    return clamp((shape * profile + coverage - 1.0) * 3.2, 0.0, 1.0);
}

fn cloud_light_depth(p: vec3<f32>, steps: i32) -> f32 {
    let dir = select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.05);
    let step_len = 34.0;
    var depth = 0.0;
    for (var i = 0; i < steps; i++) {
        let s = p + dir * step_len * (f32(i) + 0.5) * (1.0 + f32(i) * 0.6);
        depth += cloud_density(s, false) * step_len * (1.0 + f32(i) * 0.6);
    }
    return depth;
}

fn render_clouds(dir: vec3<f32>, background: vec3<f32>, dither: f32) -> vec3<f32> {
    if cloud_quality == 0u {
        return background;
    }
    let camera_y = frame.camera_position.y;
    if abs(dir.y) < 1e-3 {
        return background;
    }
    let t_bottom = (CLOUD_BOTTOM - camera_y) / dir.y;
    let t_top = (CLOUD_TOP - camera_y) / dir.y;
    let t_start = max(min(t_bottom, t_top), 0.0);
    let t_end = min(max(t_bottom, t_top), 9000.0);
    if t_end <= t_start {
        return background;
    }

    var steps = 12;
    var light_steps = 3;
    if cloud_quality == 2u {
        steps = 20;
        light_steps = 4;
    } else if cloud_quality >= 3u {
        steps = 32;
        light_steps = 5;
    }
    let step_len = (t_end - t_start) / f32(steps);

    let to_light = select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.05);
    let cos_theta = dot(dir, to_light);
    let phase = mix(henyey_greenstein(cos_theta, -0.2), henyey_greenstein(cos_theta, 0.65), 0.7) * 4.0 * PI_F32;
    let sun = direct_light() * 1.4;
    let ambient = sky_radiance(vec3<f32>(0.0, 1.0, 0.0)) * 1.6 + vec3<f32>(0.002, 0.003, 0.006);
    let camera_xz = frame.camera_position.xz;

    var transmittance = 1.0;
    var scattered = vec3<f32>(0.0);
    for (var i = 0; i < steps; i++) {
        let t = t_start + step_len * (f32(i) + dither);
        let local = dir * t;
        let p = vec3<f32>(local.x + camera_xz.x, local.y + camera_y, local.z + camera_xz.y);
        let density = cloud_density(p, true);
        if density <= 0.0 {
            continue;
        }
        let extinction = density * 0.045;
        let step_t = exp(-extinction * step_len);
        let light_depth = cloud_light_depth(p, light_steps) * 0.045;
        let beer = exp(-light_depth) + 0.25 * exp(-light_depth * 0.25);
        let powder = 1.0 - exp(-density * 2.5);
        let h = (p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM);
        let lit = sun * beer * phase * mix(0.6, 1.0, powder) + ambient * mix(0.35, 1.0, h);
        scattered += transmittance * (1.0 - step_t) * lit;
        transmittance *= step_t;
        if transmittance < 0.02 {
            break;
        }
    }

    let distance_fade = exp(-t_start / 7000.0) * smoothstep(0.0, 0.06, abs(dir.y));
    let clouds = background * transmittance + scattered;
    return mix(background, clouds, distance_fade);
}

fn sky(input: SkyInput) -> vec4<f32> {
    if !in_overworld() {
        return input.color;
    }
    let dir = input.direction;
    var color = sky_radiance(dir);
    if dir.y < 0.0 {
        color *= mix(1.0, 0.35, smoothstep(0.0, -0.3, dir.y));
    }
    // The sky stage gets no pixel position: a hash of the ray stands in for per-pixel noise.
    let bits = bitcast<vec3<u32>>(dir);
    let dither = unit_float(hash_u32(bits.x ^ hash_u32(bits.y ^ hash_u32(bits.z))));
    color = render_clouds(dir, color, dither);
    var out = encode_display(color);
    if frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 {
        let obscured = max(max(frame.blindness, frame.darkness), select(0.0, 1.0, frame.eye_in != 0u));
        out = mix(out, input.color.rgb, obscured);
    }
    return vec4<f32>(out, 1.0);
}
