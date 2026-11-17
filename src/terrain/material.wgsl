fn is_foliage(material_id: u32) -> bool {
    return material_id >= MAT_LEAVES && material_id <= MAT_TALL_UPPER;
}

// Vanilla darkens side and bottom faces; directional sunlight takes over that role.
fn vanilla_face_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if max(a.x, max(a.y, a.z)) < 0.999 || n.y > 0.5 {
        return 1.0;
    }
    if n.y < -0.5 {
        return 0.5;
    }
    return select(0.6, 0.8, a.z > 0.5);
}

// Block light's direction from how its level changes across the face: brightest facing the
// source, a little dimmer where it grazes the face.
fn block_light_facing(n: vec3<f32>, gradient: vec3<f32>) -> f32 {
    let toward = normalize(gradient * 7.0 + n);
    return mix(0.72, 1.0, max(dot(n, toward), 0.0));
}

fn torch_light(level: f32) -> vec3<f32> {
    return TORCH_COLOR * (pow(level, 4.0) * 2.2 + pow(level, 1.5) * 0.06);
}

fn other_dimension(input: MaterialInput, base: vec3<f32>, albedo: vec3<f32>, facing: f32) -> vec3<f32> {
    let ambient = dimension_ambient() * mix(0.55, 1.0, input.light.x);
    let colored = to_linear(input.colored_light) * 1.5;
    var color = base * (ambient + torch_light(input.light.x) * facing + colored);
    color += albedo * input.emission * input.emission * 4.0;
    if input.fluid == 2u {
        color = albedo * 3.0 + base * 0.5;
    }
    return color;
}

fn material(input: MaterialInput) -> Surface {
    // Derivatives first, while every invocation of the quad still runs this code.
    let dx = dpdx(input.position);
    let dy = dpdy(input.position);
    let dl = vec2<f32>(dpdx(input.light.x), dpdy(input.light.x));
    let n = input.normal;
    let area = dot(n, cross(dx, dy));
    var gradient = vec3<f32>(0.0);
    if abs(area) > 1e-8 {
        gradient = (dl.x * cross(dy, n) + dl.y * cross(n, dx)) / area;
    }

    let noise = blue_noise(input.screen * frame.resolution);
    if input.fluid == 1u && input.material == MAT_WATER {
        return Surface(render_water(input, noise));
    }

    let foliage = is_foliage(input.material);
    let albedo = to_linear(input.albedo.rgb);
    var tint = to_linear(input.tint.rgb);
    if input.fluid == 0u && !foliage {
        tint = min(tint / to_linear(vec3<f32>(vanilla_face_shade(n))), vec3<f32>(1.0));
    }
    var base = albedo * tint;
    let alpha = input.albedo.a * input.tint.a;
    let facing = block_light_facing(n, gradient);

    if !in_overworld() {
        return Surface(vec4<f32>(store_color(other_dimension(input, base, albedo, facing)), alpha));
    }

    let block_level = input.light.x;
    let sky_level = input.light.y;
    let wet = frame.wetness * smoothstep(0.85, 0.95, sky_level) * max(n.y, 0.0) * select(1.0, 0.0, foliage);
    base *= mix(1.0, 0.65, wet);

    let l = frame.light_direction;
    var ndl = max(dot(n, l), 0.0);
    if foliage {
        ndl = 0.55 + 0.45 * abs(dot(n, l));
    }

    var shadow = vec3<f32>(smoothstep(0.82, 0.97, sky_level));
    if shadows && frame.has_shadow == 1u && ndl > 0.0 {
        let distance = length(input.position);
        let fade = smoothstep(frame.shadow_distance * 0.8, frame.shadow_distance * 0.97, distance);
        if fade < 1.0 {
            shadow = mix(sun_shadow(input.position, n, foliage, noise.xy), shadow, fade);
        }
    }

    let sun = direct_light();
    var direct = sun * ndl * shadow;
    if foliage {
        let back = pow(max(dot(normalize(input.position), l), 0.0), 6.0);
        direct += sun * shadow * back * 1.2 * albedo;
    }

    let hemisphere = select(0.72 + 0.28 * n.y, 0.86, foliage);
    let sky_occlusion = sky_level * sky_level;
    let ambient = sky_ambient() * hemisphere * sky_occlusion
        + sun * 0.035 * sky_occlusion * (1.0 - max(n.y, 0.0));
    let minimum = vec3<f32>(0.008, 0.009, 0.012) * (1.0 - sky_level) + vec3<f32>(frame.night_vision * 0.6);
    let colored = to_linear(input.colored_light) * 1.5;

    var color = base * (direct + ambient + torch_light(block_level) * facing + minimum + colored);
    color += albedo * input.emission * input.emission * 4.0;
    if input.fluid == 2u {
        color = albedo * 3.0 + base * 0.5;
    }

    if wet > 0.0 {
        let v = -normalize(input.position);
        let fresnel = schlick_fresnel(dot(n, v), 0.04);
        color += reflected_sky(reflect(-v, n)) * fresnel * wet * 0.6 * shadow;
    }
    return Surface(vec4<f32>(store_color(color), alpha));
}
