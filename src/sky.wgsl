override night_sky: bool = true;
override aurora: bool = true;
override aurora_intensity: f32 = 1.0;

// The galactic plane's normal and the direction of its bright core, in the celestial frame.
const GALACTIC_NORTH: vec3<f32> = vec3<f32>(0.28, 0.42, 0.86);
const GALACTIC_CORE: vec3<f32> = vec3<f32>(0.93, -0.33, -0.14);

fn sun_disc(dir: vec3<f32>) -> vec3<f32> {
    let cos_angle = dot(dir, frame.sun_direction);
    let radius = 0.0125;
    let distance = sqrt(max(2.0 - 2.0 * cos_angle, 0.0));
    if distance > radius * 1.5 {
        return vec3<f32>(0.0);
    }
    let r = clamp(distance / radius, 0.0, 1.0);
    let limb = pow(max(1.0 - r * r, 0.0), 0.3);
    let edge = 1.0 - smoothstep(0.85, 1.0, distance / radius);
    let horizon = smoothstep(-0.02, 0.01, dir.y);
    return SUN_DISC_RADIANCE * sun_transmittance(1.0) * limb * edge * horizon * (1.0 - overcast());
}

// The view ray in the frame the stars are fixed in: the sky turns with the sun about the
// north-south axis.
fn celestial(dir: vec3<f32>) -> vec3<f32> {
    let s = frame.sun_direction;
    let angle = atan2(s.x, s.y);
    let c = cos(angle);
    let n = sin(angle);
    return vec3<f32>(c * dir.x - n * dir.y, n * dir.x + c * dir.y, dir.z);
}

fn star_field(c: vec3<f32>, density: f32) -> vec3<f32> {
    let grid = c * 220.0;
    let cell = floor(grid);
    let id = bitcast<vec3<u32>>(vec3<i32>(cell));
    let h = hash_u32(id.x ^ hash_u32(id.y ^ hash_u32(id.z)));
    let presence = unit_float(h);
    if presence > density {
        return vec3<f32>(0.0);
    }
    let h2 = hash_u32(h);
    let centre = cell + 0.25 + 0.5 * vec3<f32>(unit_float(h2), unit_float(hash_u32(h2)), unit_float(hash_u32(h2 ^ 0x9e3779b9u)));
    let d = length(grid - centre);
    let magnitude = pow(unit_float(hash_u32(h2 + 7u)), 6.0);
    let twinkle = 0.7 + 0.3 * sin(frame.time * (2.0 + 5.0 * unit_float(h2 + 3u)) + presence * 60.0);
    let temperature = unit_float(hash_u32(h2 + 11u));
    let tint = mix(vec3<f32>(1.0, 0.72, 0.5), vec3<f32>(0.7, 0.82, 1.0), temperature);
    return tint * (0.05 + magnitude * 2.5) * twinkle * exp(-d * d * 28.0);
}

fn milky_way(c: vec3<f32>) -> vec3<f32> {
    let latitude = dot(c, GALACTIC_NORTH);
    let band = exp(-latitude * latitude / 0.018);
    if band < 0.01 {
        return vec3<f32>(0.0);
    }
    let core = pow(max(dot(c, GALACTIC_CORE), 0.0), 3.0);
    let p = c * 9.0;
    var glow = value_noise3(p) * 0.6 + value_noise3(p * 2.1 + 3.7) * 0.4;
    var dust = 0.0;
    if quality >= QUALITY_MEDIUM {
        glow = glow * 0.75 + value_noise3(p * 4.7) * 0.25;
        let lane = exp(-pow(latitude - 0.02 * sin(dot(c, GALACTIC_CORE) * 9.0), 2.0) / 0.0016);
        dust = lane * smoothstep(0.35, 0.75, value_noise3(p * 3.3 + 11.0)) * 0.85;
    }
    let tint = mix(vec3<f32>(0.55, 0.62, 0.9), vec3<f32>(1.0, 0.82, 0.62), core);
    return tint * band * glow * (0.025 + core * 0.06) * (1.0 - dust);
}

fn aurora_activity() -> f32 {
    let cold = 1.0 - smoothstep(0.0, 0.8, frame.temperature);
    let nightly = smoothstep(0.45, 0.75, value_noise2(vec2<f32>(frame.time / 900.0, 4.2)));
    return clamp(max(nightly, cold), 0.0, 1.0);
}

// Curtains as layers stacked along the ray above a height: each layer's thin ridges of noise
// glow green at the bottom and violet toward the top.
fn aurora_light(dir: vec3<f32>, jitter: f32) -> vec3<f32> {
    if dir.y <= 0.02 {
        return vec3<f32>(0.0);
    }
    let layers = array<i32, 4>(6, 10, 14, 20)[min(quality, 3u)];
    let drift = vec2<f32>(frame.time * 0.004, frame.time * 0.0015);
    var light = vec3<f32>(0.0);
    for (var i = 0; i < 20; i++) {
        if i >= layers {
            break;
        }
        let h = (f32(i) + jitter) / f32(layers);
        let xz = dir.xz / dir.y * (1.0 + h * 0.45) * 0.55;
        let warp = vec2<f32>(value_noise2(xz * 1.3 + drift * 3.0), value_noise2(xz * 1.3 + 9.1)) * 0.6;
        let ridge = 1.0 - abs(value_noise2((xz + warp) * vec2<f32>(2.2, 0.6) + drift) * 2.0 - 1.0);
        let curtain = pow(ridge, 14.0) * smoothstep(0.3, 0.6, value_noise2(xz * 0.5 - drift));
        let color = mix(vec3<f32>(0.1, 1.0, 0.45), vec3<f32>(0.55, 0.2, 0.9), smoothstep(0.25, 1.0, h));
        light += color * curtain * exp(-h * 2.2);
    }
    return light / f32(layers) * 0.35 * smoothstep(0.02, 0.25, dir.y);
}

fn night(dir: vec3<f32>, jitter: f32) -> vec3<f32> {
    let darkness = (1.0 - sun_visibility()) * (1.0 - overcast());
    if darkness <= 0.0 || dir.y <= -0.05 {
        return vec3<f32>(0.0);
    }
    let extinction = smoothstep(-0.05, 0.25, dir.y);
    var light = vec3<f32>(0.0);
    if night_sky {
        let c = celestial(dir);
        light += (star_field(c, 0.06) + milky_way(c)) * extinction;
    }
    if aurora && aurora_intensity > 0.0 {
        light += aurora_light(dir, jitter) * aurora_intensity * aurora_activity();
    }
    return light * darkness;
}

fn sky(input: SkyInput) -> vec4<f32> {
    if !in_overworld() {
        return input.color;
    }
    let dir = input.direction;
    let bits = bitcast<vec3<u32>>(dir);
    let jitter = unit_float(hash_u32(bits.x ^ hash_u32(bits.y ^ hash_u32(bits.z))));
    let color = sky_radiance(dir) + sun_disc(dir) * sun_visibility() + night(dir, jitter);
    var out = store_color(color);
    if frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 {
        let obscured = max(max(frame.blindness, frame.darkness), select(0.0, 1.0, frame.eye_in != 0u));
        out = mix(out, input.color.rgb, obscured);
    }
    return vec4<f32>(out, 1.0);
}
