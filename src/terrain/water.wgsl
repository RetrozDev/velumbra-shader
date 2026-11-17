override mirror_reflections: bool = false;

fn ssr_steps() -> i32 {
    return array<i32, 4>(0, 14, 22, 32)[min(quality, 3u)];
}

fn schlick_fresnel(cos_theta: f32, f0: f32) -> f32 {
    return f0 + (1.0 - f0) * pow(1.0 - clamp(cos_theta, 0.0, 1.0), 5.0);
}

fn ggx_specular(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32) -> f32 {
    let h = normalize(v + l);
    let nh = max(dot(n, h), 0.0);
    let a2 = roughness * roughness * roughness * roughness;
    let d = nh * nh * (a2 - 1.0) + 1.0;
    return a2 / (PI_F32 * d * d) * max(dot(n, l), 0.0);
}

fn project_to_screen(p: vec3<f32>) -> vec3<f32> {
    let clip = frame.projection * frame.view * vec4<f32>(p, 1.0);
    if clip.w <= 1e-4 {
        return vec3<f32>(-1.0);
    }
    let ndc = clip.xyz / clip.w;
    return vec3<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, ndc.z);
}

// The sky a reflection sees: the scattering sky, the sun's glow and both cloud layers.
fn reflected_sky(dir: vec3<f32>) -> vec3<f32> {
    let d = normalize(vec3<f32>(dir.x, max(dir.y, 0.01), dir.z));
    var color = sky_radiance(d);
    let ambient = sky_radiance(vec3<f32>(0.0, 1.0, 0.0)) * 1.4;
    let lit = direct_light() * 0.4 + ambient;
    let cirrus_t = (CIRRUS_HEIGHT - frame.camera_position.y) / d.y;
    if cirrus_t > 0.0 {
        let xz = frame.camera_position.xz + d.xz * cirrus_t;
        color = mix(color, lit * 1.2, cirrus_density(xz) * 0.5 * smoothstep(0.02, 0.2, d.y));
    }
    let cumulus_t = (CUMULUS_BOTTOM + 60.0 - frame.camera_position.y) / d.y;
    if cumulus_t > 0.0 {
        let xz = frame.camera_position.xz + d.xz * cumulus_t + cloud_wind();
        let cover = cloud_coverage_map(xz) + value_noise2(xz / 160.0) * 0.35 - 0.9 + cumulus_coverage_bias() * 0.8;
        color = mix(color, lit, smoothstep(0.0, 0.25, cover) * smoothstep(0.02, 0.15, d.y) * 0.85);
    }
    return color;
}

// A ray marched against the depth of the world behind the water. rgb: what it hit, in scene
// light; a: how much to trust it (0 for a miss).
fn screen_space_reflection(origin: vec3<f32>, dir: vec3<f32>, jitter: f32) -> vec4<f32> {
    let steps = ssr_steps();
    if steps == 0 || dir.y <= -0.05 {
        return vec4<f32>(0.0);
    }
    let size = vec2<f32>(textureDimensions(opaque_depth));
    var step_len = 0.6;
    var t = step_len * (0.5 + jitter);
    for (var i = 0; i < 32; i++) {
        if i >= steps {
            break;
        }
        let p = origin + dir * t;
        let s = project_to_screen(p);
        if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) {
            break;
        }
        let texel = vec2<i32>(s.xy * size);
        let scene = textureLoad(opaque_depth, texel, 0);
        if scene > s.z && scene > 0.0 {
            let hit = reconstruct_position(s.xy, scene);
            let gap = length(p) - length(hit);
            if gap < step_len * 1.5 + 0.5 {
                let edge = smoothstep(0.0, 0.08, min(min(s.x, 1.0 - s.x), min(s.y, 1.0 - s.y)));
                let fade = 1.0 - f32(i) / f32(steps);
                let color = load_color(textureLoad(opaque_color, texel, 0).rgb) / scene_exposure();
                return vec4<f32>(color, edge * sqrt(fade));
            }
        }
        t += step_len;
        step_len *= 1.18;
    }
    return vec4<f32>(0.0);
}

fn render_water(input: MaterialInput, noise: vec4<f32>) -> vec4<f32> {
    let v = -normalize(input.position);
    let distance = length(input.position);
    let top = input.face == 1u && input.normal.y > 0.5;
    var n = input.normal;
    if water_waves && top {
        let w = wave_field(input.position.xz + frame.camera_position.xz, frame.time);
        let strength = 0.16 * exp(-distance / 48.0);
        n = normalize(vec3<f32>(-w.y * strength, 1.0, -w.z * strength));
    }

    let size = vec2<f32>(textureDimensions(opaque_depth));
    let texel = vec2<i32>(input.screen * size);
    let refract_screen = clamp(input.screen + n.xz * 0.03 * exp(-distance / 32.0), vec2<f32>(0.001), vec2<f32>(0.999));
    var behind_texel = vec2<i32>(refract_screen * size);
    var behind_depth = textureLoad(opaque_depth, behind_texel, 0);
    if behind_depth > 0.0 && length(reconstruct_position(refract_screen, behind_depth)) < distance {
        behind_texel = texel;
        behind_depth = textureLoad(opaque_depth, texel, 0);
    }
    var thickness = 48.0;
    if behind_depth > 0.0 {
        let behind = reconstruct_position((vec2<f32>(behind_texel) + 0.5) / size, behind_depth);
        thickness = max(length(behind) - distance, 0.0);
    }
    let exposure_now = scene_exposure();
    let behind_color = load_color(textureLoad(opaque_color, behind_texel, 0).rgb) / exposure_now;

    let biome = to_linear(input.tint.rgb);
    let sky_light = input.light.y;
    let ambient = sky_ambient() * sky_light * sky_light + vec3<f32>(0.004);
    let body = ambient * biome * vec3<f32>(0.12, 0.32, 0.38)
        + direct_light() * sky_light * biome * vec3<f32>(0.02, 0.06, 0.07);
    let transmit = exp(-WATER_ABSORPTION * thickness * mix(vec3<f32>(1.0), vec3<f32>(1.4) - biome * 0.6, 0.5));
    var color = behind_color * transmit + body * (1.0 - transmit);

    if frame.eye_in == 1u {
        let up_view = normalize(input.position);
        let window = smoothstep(0.6, 0.7, up_view.y);
        let above = sky_radiance(normalize(vec3<f32>(up_view.x, max(up_view.y, 0.1), up_view.z)));
        color = mix(body, above * vec3<f32>(0.7, 0.9, 0.95), window);
        return vec4<f32>(store_color(color), 1.0);
    }

    let r = reflect(-v, n);
    var reflected = reflected_sky(r);
    if mirror_reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.04, vec2<f32>(0.001), vec2<f32>(0.999));
        let mirror = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
        let vanilla_sky = mix(frame.fog_color, frame.sky_color, smoothstep(0.0, 0.4, r.y));
        let solid = smoothstep(0.04, 0.14, length(mirror - vanilla_sky));
        reflected = mix(reflected, load_color(mirror) / exposure_now, solid);
    }
    let traced = screen_space_reflection(input.position + n * 0.05, r, noise.y);
    reflected = mix(reflected, traced.rgb, traced.a);
    reflected *= mix(0.15, 1.0, smoothstep(0.1, 0.6, sky_light));

    let fresnel = schlick_fresnel(dot(n, v), 0.02);
    color = mix(color, reflected, fresnel);

    var sun_vis = vec3<f32>(smoothstep(0.5, 0.9, sky_light));
    if shadows && frame.has_shadow == 1u && distance < frame.shadow_distance {
        sun_vis = sun_shadow(input.position, input.normal, false, noise.xy);
    }
    color += direct_light() * ggx_specular(n, v, frame.light_direction, 0.08) * sun_vis * fresnel * 8.0;
    return vec4<f32>(store_color(color), 1.0);
}
