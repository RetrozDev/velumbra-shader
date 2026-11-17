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

// A star per lit cell of a fine grid on the sphere. Its spot never shrinks below a pixel, with
// its energy kept, so stars stay sharp without crawling as the view turns.
fn star_field(c: vec3<f32>, density: f32, pixel_angle: f32) -> vec3<f32> {
    let cells = 220.0;
    let grid = c * cells;
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
    let intrinsic = 0.19;
    let spot = max(intrinsic, pixel_angle * cells * 0.7);
    let energy = (intrinsic * intrinsic) / (spot * spot);
    let magnitude = pow(unit_float(hash_u32(h2 + 7u)), 6.0);
    let twinkle = 0.7 + 0.3 * sin(frame.time * (2.0 + 5.0 * unit_float(h2 + 3u)) + presence * 60.0);
    let temperature = unit_float(hash_u32(h2 + 11u));
    let tint = mix(vec3<f32>(1.0, 0.72, 0.5), vec3<f32>(0.7, 0.82, 1.0), temperature);
    return tint * (0.05 + magnitude * 2.5) * twinkle * energy * exp(-d * d / (spot * spot));
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

// Where the curtains stand at one height of the layer: x the signed distance to a curtain's
// line (0 on it), y how strongly that stretch of sky glows.
fn aurora_field(xz: vec2<f32>, drift: vec2<f32>) -> vec2<f32> {
    let warp = vec2<f32>(value_noise2(xz * 1.3 + drift * 3.0), value_noise2(xz * 1.3 + 9.1)) * 0.6;
    let line = value_noise2((xz + warp) * vec2<f32>(2.2, 0.6) + drift) * 2.0 - 1.0;
    return vec2<f32>(line, smoothstep(0.3, 0.6, value_noise2(xz * 0.5 - drift)));
}

// The integral over s in 0..1 of exp(-k |g0 + (g1 - g0) s|): a curtain's glow along a stretch
// of the ray where its distance to the curtain changes linearly.
fn curtain_integral(g0: f32, g1: f32, k: f32) -> f32 {
    let a = exp(-k * abs(g0));
    let b = exp(-k * abs(g1));
    let span = abs(g1 - g0) * k;
    if span < 1e-3 {
        return 0.5 * (a + b);
    }
    if g0 * g1 >= 0.0 {
        return abs(a - b) / span;
    }
    return (2.0 - a - b) / span;
}

// Curtains rising through a layer of the sky: the ray's path through the layer is cut into a few
// stretches, and each stretch's glow is integrated exactly, so there is no sampling noise.
fn aurora_light(dir: vec3<f32>) -> vec3<f32> {
    if dir.y <= 0.02 {
        return vec3<f32>(0.0);
    }
    let segments = array<i32, 4>(2, 3, 4, 6)[min(quality, 3u)];
    let drift = vec2<f32>(frame.time * 0.004, frame.time * 0.0015);
    let base = dir.xz / dir.y * 0.55;
    var below = aurora_field(base, drift);
    var light = vec3<f32>(0.0);
    for (var i = 0; i < 6; i++) {
        if i >= segments {
            break;
        }
        let top = f32(i + 1) / f32(segments);
        let above = aurora_field(base * (1.0 + top * 0.45), drift);
        let middle = (f32(i) + 0.5) / f32(segments);
        let glow = curtain_integral(below.x, above.x, 14.0) * 0.5 * (below.y + above.y);
        let color = mix(vec3<f32>(0.1, 1.0, 0.45), vec3<f32>(0.55, 0.2, 0.9), smoothstep(0.25, 1.0, middle));
        light += color * glow * exp(-middle * 2.2);
        below = above;
    }
    return light / f32(segments) * 0.35 * smoothstep(0.02, 0.25, dir.y);
}

fn night(dir: vec3<f32>, pixel_angle: f32) -> vec3<f32> {
    let darkness = (1.0 - sun_visibility()) * (1.0 - overcast());
    if darkness <= 0.0 || dir.y <= -0.05 {
        return vec3<f32>(0.0);
    }
    let extinction = smoothstep(-0.05, 0.25, dir.y);
    var light = vec3<f32>(0.0);
    if night_sky {
        let c = celestial(dir);
        light += (star_field(c, 0.06, pixel_angle) + milky_way(c)) * extinction;
    }
    if aurora && aurora_intensity > 0.0 {
        light += aurora_light(dir) * aurora_intensity * aurora_activity();
    }
    return light * darkness;
}

fn sky(input: SkyInput) -> vec4<f32> {
    let dir = input.direction;
    let pixel_angle = length(fwidth(dir));
    if !in_overworld() {
        return input.color;
    }
    let color = sky_radiance(dir) + sun_disc(dir) * sun_visibility() + night(dir, pixel_angle);
    var out = store_color(color);
    if frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 {
        let obscured = max(max(frame.blindness, frame.darkness), select(0.0, 1.0, frame.eye_in != 0u));
        out = mix(out, input.color.rgb, obscured);
    }
    return vec4<f32>(out, 1.0);
}
