override shadows: bool = true;
override shadow_softness: f32 = 1.0;
override water_reflections: bool = true;

const TORCH_COLOR: vec3<f32> = vec3<f32>(1.0, 0.56, 0.24);
const WATER_ABSORPTION: vec3<f32> = vec3<f32>(0.30, 0.075, 0.055);

fn is_foliage(material_id: u32) -> bool {
    return material_id >= MAT_LEAVES && material_id <= MAT_TALL_UPPER;
}

// Vanilla darkens side and bottom faces; directional sunlight takes over that role.
fn vanilla_face_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if max(a.x, max(a.y, a.z)) < 0.999 {
        return 1.0;
    }
    if n.y > 0.5 {
        return 1.0;
    }
    if n.y < -0.5 {
        return 0.5;
    }
    return select(0.6, 0.8, a.z > 0.5);
}

// The ground one shadow texel covers at `p`, which the distortion stretches away from the centre.
fn shadow_texel_size(p: vec3<f32>) -> f32 {
    let clip = frame.shadow_view_proj * vec4<f32>(p, 1.0);
    let k = frame.shadow_distortion;
    let stretch = (length(clip.xy) * k + 1.0 - k) / max(1.0 - k, 1e-3);
    return frame.shadow_center_texel * stretch * stretch;
}

fn sample_shadow(p: vec3<f32>, n: vec3<f32>, foliage: bool, dither: f32) -> f32 {
    let texel = shadow_texel_size(p);
    let offset_dir = select(n, frame.light_direction, foliage);
    let sp = shadow_position(p + offset_dir * texel * 1.6);
    if any(sp.xy <= vec2<f32>(0.0)) || any(sp.xy >= vec2<f32>(1.0)) {
        return 1.0;
    }
    let radius = (0.6 + shadow_softness * 1.6) / max(frame.shadow_resolution, 1.0);
    let angle_step = 2.39996323;
    var lit = 0.0;
    for (var i = 0; i < 8; i++) {
        let fi = f32(i) + 0.5;
        let r = sqrt(fi / 8.0) * radius;
        let a = fi * angle_step + dither * 2.0 * PI_F32;
        let uv = sp.xy + vec2<f32>(cos(a), sin(a)) * r;
        lit += textureSampleCompareLevel(shadow_map, shadow_sampler, uv, sp.z - 0.0002);
    }
    return lit / 8.0;
}

fn ggx_specular(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32) -> f32 {
    let h = normalize(v + l);
    let nh = max(dot(n, h), 0.0);
    let a2 = roughness * roughness * roughness * roughness;
    let d = nh * nh * (a2 - 1.0) + 1.0;
    return a2 / (PI_F32 * d * d) * max(dot(n, l), 0.0);
}

fn schlick_fresnel(cos_theta: f32, f0: f32) -> f32 {
    return f0 + (1.0 - f0) * pow(1.0 - clamp(cos_theta, 0.0, 1.0), 5.0);
}

fn cheap_clouds(dir: vec3<f32>, background: vec3<f32>) -> vec3<f32> {
    if dir.y <= 0.02 {
        return background;
    }
    let t = (CLOUD_BOTTOM + 60.0 - frame.camera_position.y) / dir.y;
    if t <= 0.0 {
        return background;
    }
    let xz = frame.camera_position.xz + dir.xz * t + cloud_wind();
    let cover = cloud_coverage_map(xz) + value_noise2(xz / 160.0) * 0.35 - 0.9 + frame.rain * 0.3;
    let alpha = smoothstep(0.0, 0.25, cover) * smoothstep(0.02, 0.15, dir.y);
    let tint = direct_light() * 0.35 + sky_radiance(vec3<f32>(0.0, 1.0, 0.0)) * 1.4;
    return mix(background, tint, alpha * 0.85);
}

fn render_water(input: MaterialInput, dither: f32) -> vec4<f32> {
    let v = -normalize(input.position);
    let distance = length(input.position);
    let top = input.face == 1u && input.normal.y > 0.5;
    var n = input.normal;
    if water_waves && top {
        let w = wave_field(input.position.xz + frame.camera_position.xz, frame.time);
        let strength = 0.16 * exp(-distance / 48.0);
        n = normalize(vec3<f32>(-w.y * strength, 1.0, -w.z * strength));
    }

    let texel = vec2<i32>(input.screen * frame.resolution);
    let surface_depth = distance;
    let refract_screen = clamp(input.screen + n.xz * 0.03 * exp(-distance / 32.0), vec2<f32>(0.001), vec2<f32>(0.999));
    let refract_texel = vec2<i32>(refract_screen * frame.resolution);
    let refract_depth = textureLoad(opaque_depth, refract_texel, 0);
    var behind_texel = refract_texel;
    var behind_depth_raw = refract_depth;
    if refract_depth > 0.0 && length(reconstruct_position(refract_screen, refract_depth)) < surface_depth {
        behind_texel = texel;
        behind_depth_raw = textureLoad(opaque_depth, texel, 0);
    }
    var thickness = 48.0;
    if behind_depth_raw > 0.0 {
        let behind = reconstruct_position(vec2<f32>(behind_texel) / frame.resolution, behind_depth_raw);
        thickness = max(length(behind) - surface_depth, 0.0);
    }
    let behind_color = to_linear(textureLoad(opaque_color, behind_texel, 0).rgb);

    let biome = to_linear(input.tint.rgb);
    let sky_light = input.light.y;
    let ambient = sky_ambient() * sky_light * sky_light + vec3<f32>(0.004);
    let body_hdr = ambient * biome * vec3<f32>(0.12, 0.32, 0.38)
        + direct_light() * sky_light * biome * vec3<f32>(0.02, 0.06, 0.07);
    let body = display_linear(body_hdr);
    let transmit = exp(-WATER_ABSORPTION * thickness * mix(vec3<f32>(1.0), vec3<f32>(1.4) - biome * 0.6, 0.5));
    var color = behind_color * transmit + body * (1.0 - transmit);

    if frame.eye_in == 1u {
        let up_view = normalize(input.position);
        let inside_window = smoothstep(0.6, 0.7, up_view.y);
        let above = display_linear(sky_radiance(normalize(vec3<f32>(up_view.x, max(up_view.y, 0.1), up_view.z))));
        color = mix(body, above * vec3<f32>(0.7, 0.9, 0.95), inside_window);
        return vec4<f32>(to_gamma(color), 1.0);
    }

    let r = reflect(-v, n);
    let sky_dir = normalize(vec3<f32>(r.x, max(r.y, 0.02), r.z));
    var reflected = display_linear(cheap_clouds(sky_dir, sky_radiance(sky_dir)));
    if water_reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.04, vec2<f32>(0.001), vec2<f32>(0.999));
        let mirror = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
        let vanilla_sky = mix(frame.fog_color.rgb, frame.sky_color.rgb, smoothstep(0.0, 0.4, sky_dir.y));
        let solid = smoothstep(0.04, 0.14, length(mirror - vanilla_sky));
        reflected = mix(reflected, to_linear(mirror), solid);
    }
    reflected *= mix(0.15, 1.0, smoothstep(0.1, 0.6, sky_light));

    let fresnel = schlick_fresnel(dot(n, v), 0.02);
    color = mix(color, reflected, fresnel);

    var sun_vis = smoothstep(0.5, 0.9, sky_light);
    if shadows && frame.has_shadow == 1u && distance < frame.shadow_distance {
        sun_vis = sample_shadow(input.position, input.normal, false, dither);
    }
    let spec = direct_light() * ggx_specular(n, v, frame.light_direction, 0.08) * sun_vis * fresnel * 6.0;
    color += display_linear(spec);
    return vec4<f32>(to_gamma(color), 1.0);
}

fn material(input: MaterialInput) -> Surface {
    if !in_overworld() {
        return Surface(vec4<f32>(input.albedo.rgb * input.tint.rgb * input.lightmap, input.albedo.a * input.tint.a));
    }
    let dither = pixel_dither(input.screen * frame.resolution);
    if input.fluid == 1u && input.material == MAT_WATER {
        return Surface(render_water(input, dither));
    }

    let n = input.normal;
    let foliage = is_foliage(input.material);
    let albedo = to_linear(input.albedo.rgb);
    var tint = to_linear(input.tint.rgb);
    if input.fluid == 0u && !foliage {
        tint = min(tint / to_linear(vec3<f32>(vanilla_face_shade(n))), vec3<f32>(1.0));
    }
    var base = albedo * tint;

    let block_level = input.light.x;
    let sky_level = input.light.y;

    let wet = frame.wetness * smoothstep(0.85, 0.95, sky_level) * max(n.y, 0.0) * select(1.0, 0.0, foliage);
    base *= mix(1.0, 0.65, wet);

    let l = frame.light_direction;
    var ndl = max(dot(n, l), 0.0);
    if foliage {
        ndl = 0.55 + 0.45 * abs(dot(n, l));
    }

    var shadow = smoothstep(0.82, 0.97, sky_level);
    if shadows && frame.has_shadow == 1u && ndl > 0.0 {
        let distance = length(input.position);
        let fade = smoothstep(frame.shadow_distance * 0.8, frame.shadow_distance * 0.97, distance);
        if fade < 1.0 {
            shadow = mix(sample_shadow(input.position, n, foliage, dither), shadow, fade);
        }
    }

    let sun = direct_light();
    var direct = sun * ndl * shadow;
    if foliage {
        let v = normalize(input.position);
        let back = pow(max(dot(v, l), 0.0), 6.0);
        direct += sun * shadow * back * 1.2 * albedo;
    }

    let hemisphere = select(0.72 + 0.28 * n.y, 0.86, foliage);
    let ambient = sky_ambient() * hemisphere * sky_level * sky_level
        + sun * 0.035 * sky_level * sky_level * (1.0 - max(n.y, 0.0));
    let torch = TORCH_COLOR * (pow(block_level, 4.0) * 2.2 + pow(block_level, 1.5) * 0.06);
    let minimum = vec3<f32>(0.008, 0.009, 0.012) * (1.0 - sky_level) + vec3<f32>(frame.night_vision * 0.6);
    let colored = to_linear(input.colored_light) * 1.5;

    var color = base * (direct + ambient + torch + minimum + colored);
    color += albedo * input.emission * input.emission * 4.0;
    if input.fluid == 2u {
        color = albedo * 3.0 + base * 0.5;
    }

    if wet > 0.0 {
        let v = -normalize(input.position);
        let r = reflect(-v, n);
        let fresnel = schlick_fresnel(dot(n, v), 0.04);
        color += sky_radiance(r) * fresnel * wet * 0.6 * shadow;
    }

    return Surface(vec4<f32>(encode_display(color), input.albedo.a * input.tint.a));
}
