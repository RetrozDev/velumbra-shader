override exposure: f32 = 1.0;
override quality: u32 = 1u;
override cloud_coverage: f32 = 0.5;

const PI_F32: f32 = 3.14159265;
const GOLDEN_ANGLE: f32 = 2.39996323;

const QUALITY_LOW: u32 = 0u;
const QUALITY_MEDIUM: u32 = 1u;
const QUALITY_HIGH: u32 = 2u;
const QUALITY_ULTRA: u32 = 3u;

const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_WATER: u32 = 5u;

const TAU_RAYLEIGH: vec3<f32> = vec3<f32>(0.0464, 0.108, 0.265);
const TAU_MIE: f32 = 0.03;
const TAU_OZONE: vec3<f32> = vec3<f32>(0.035, 0.095, 0.005);
const SKY_RADIANCE: f32 = 15.0;
const SUN_IRRADIANCE: f32 = 2.6;
const SUN_DISC_RADIANCE: f32 = 60.0;
const MOON_LIGHT: vec3<f32> = vec3<f32>(0.035, 0.05, 0.085);
const NIGHT_SKY: vec3<f32> = vec3<f32>(0.007, 0.009, 0.022);
const TORCH_COLOR: vec3<f32> = vec3<f32>(1.0, 0.56, 0.24);

const CUMULUS_BOTTOM: f32 = 260.0;
const CUMULUS_TOP: f32 = 470.0;
const CIRRUS_HEIGHT: f32 = 1100.0;

const WATER_ABSORPTION: vec3<f32> = vec3<f32>(0.30, 0.075, 0.055);

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_gamma(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn in_overworld() -> bool {
    return frame.dimension == 0;
}

fn in_nether() -> bool {
    return frame.dimension == -1;
}

fn sun_visibility() -> f32 {
    return smoothstep(-0.12, 0.02, frame.sun_direction.y);
}

fn moon_visibility() -> f32 {
    return smoothstep(-0.05, 0.12, frame.moon_direction.y) * (1.0 - sun_visibility());
}

// Eased by Horizon (half-life of 2 s), so exposure follows caves and nights without stepping.
fn scene_exposure() -> f32 {
    let outdoors = smoothstep(0.1, 0.7, frame.eye_light_smooth.y);
    let night = mix(1.0, 2.3, (1.0 - sun_visibility()) * outdoors);
    let indoors = mix(2.0, 1.0, outdoors);
    var dimension = 1.0;
    if !in_overworld() {
        dimension = 1.6;
    }
    return exposure * 1.15 * night * indoors * dimension;
}

// The frame is 8-bit, so every stage stores light through one invertible curve (1 - e^-x);
// the post chain undoes it, works in half floats, and applies the same curve once at the end.
// Vanilla's own draws (entities, moon, stars) pass through it unchanged.
fn store_color(hdr: vec3<f32>) -> vec3<f32> {
    return to_gamma(1.0 - exp(-max(hdr, vec3<f32>(0.0)) * scene_exposure()));
}

fn load_color(stored: vec3<f32>) -> vec3<f32> {
    return -log(max(1.0 - to_linear(min(stored, vec3<f32>(1.0))), vec3<f32>(1.0 / 512.0)));
}

fn hash_u32(x: u32) -> u32 {
    var h = x * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    return (h >> 22u) ^ h;
}

fn unit_float(h: u32) -> f32 {
    return f32(h >> 8u) * (1.0 / 16777216.0);
}

fn hash2(p: vec2<i32>) -> f32 {
    let u = bitcast<vec2<u32>>(p);
    return unit_float(hash_u32(u.x ^ hash_u32(u.y)));
}

fn value_noise2(p: vec2<f32>) -> f32 {
    let i = vec2<i32>(floor(p));
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<i32>(1, 0));
    let c = hash2(i + vec2<i32>(0, 1));
    let d = hash2(i + vec2<i32>(1, 1));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn value_noise3(p: vec3<f32>) -> f32 {
    let i = bitcast<vec3<u32>>(vec3<i32>(floor(p)));
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let z0 = hash_u32(i.z);
    let z1 = hash_u32(i.z + 1u);
    let y0z0 = hash_u32(i.y ^ z0);
    let y1z0 = hash_u32((i.y + 1u) ^ z0);
    let y0z1 = hash_u32(i.y ^ z1);
    let y1z1 = hash_u32((i.y + 1u) ^ z1);
    let x00 = mix(unit_float(hash_u32(i.x ^ y0z0)), unit_float(hash_u32((i.x + 1u) ^ y0z0)), w.x);
    let x10 = mix(unit_float(hash_u32(i.x ^ y1z0)), unit_float(hash_u32((i.x + 1u) ^ y1z0)), w.x);
    let x01 = mix(unit_float(hash_u32(i.x ^ y0z1)), unit_float(hash_u32((i.x + 1u) ^ y0z1)), w.x);
    let x11 = mix(unit_float(hash_u32(i.x ^ y1z1)), unit_float(hash_u32((i.x + 1u) ^ y1z1)), w.x);
    return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z);
}

// Four decorrelated blue-noise values for a pixel, shifted along the golden ratio every frame so
// temporal accumulation sees a different, still well-spread pattern each time.
fn blue_noise(pixel: vec2<f32>) -> vec4<f32> {
    let texel = vec2<i32>(floor(pixel)) & vec2<i32>(63);
    let n = textureLoad(blue_noise_tex, texel, 0);
    return fract(n + f32(frame.frame_index % 64u) * 0.61803398);
}

fn henyey_greenstein(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * PI_F32 * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 1e-4), 1.5));
}

// Kasten and Young's relative air mass for a ray at cosine `mu` from the zenith.
fn air_mass(mu: f32) -> f32 {
    let m = clamp(mu, 0.0, 1.0);
    let zenith = degrees(acos(m));
    return 1.0 / (m + 0.50572 * pow(max(96.07995 - zenith, 0.5), -1.6364));
}

fn sun_transmittance(height_factor: f32) -> vec3<f32> {
    let m = air_mass(frame.sun_direction.y + 0.035) * height_factor;
    return exp(-(TAU_RAYLEIGH + TAU_MIE + TAU_OZONE) * m);
}

fn overcast() -> f32 {
    return clamp(frame.rain * 0.85 + frame.thunder * 0.15, 0.0, 1.0);
}

// Single scattering along `dir` with an air-mass approximation, plus the night sky.
fn clear_sky(dir: vec3<f32>) -> vec3<f32> {
    let up = max(dir.y, 0.0);
    let sun = frame.sun_direction;
    let cos_theta = dot(dir, sun);
    let view_mass = air_mass(up);
    let sun_vis = sun_visibility();
    let sun_t = sun_transmittance(1.0 - 0.65 * sqrt(up)) * sun_vis;
    let tau_r = TAU_RAYLEIGH * 2.0;
    let tau = tau_r + TAU_MIE;
    let phase_r = 3.0 / (16.0 * PI_F32) * (1.0 + cos_theta * cos_theta);
    let phase_m = henyey_greenstein(cos_theta, 0.8);
    let scatter = (tau_r * phase_r + TAU_MIE * phase_m * 0.5) / tau * (1.0 - exp(-tau * view_mass));
    let day = SKY_RADIANCE * sun_t * scatter;
    let night = NIGHT_SKY * (1.0 - sun_vis * 0.85) * (0.5 + 0.5 * (1.0 - exp(-view_mass * 0.3)));
    let moon_glow = MOON_LIGHT * 0.12 * henyey_greenstein(dot(dir, frame.moon_direction), 0.7)
        * moon_visibility();
    return day + night + moon_glow;
}

fn sky_radiance(dir: vec3<f32>) -> vec3<f32> {
    let clear = clear_sky(dir);
    let grey = vec3<f32>(luminance(clear)) * vec3<f32>(0.62, 0.66, 0.72);
    var sky = mix(clear, grey, overcast());
    if dir.y < 0.0 {
        sky *= mix(1.0, 0.35, smoothstep(0.0, -0.3, dir.y));
    }
    return sky;
}

// What the sun (or the moon by night) lands on a surface facing it.
fn direct_light() -> vec3<f32> {
    let sun = SUN_IRRADIANCE * sun_transmittance(1.0) * sun_visibility();
    let moon = MOON_LIGHT * moon_visibility();
    return (sun + moon) * (1.0 - overcast() * 0.88);
}

fn sky_ambient() -> vec3<f32> {
    let zenith = sky_radiance(vec3<f32>(0.0, 1.0, 0.0));
    let horizon = sky_radiance(normalize(vec3<f32>(-frame.sun_direction.x, 0.25, -frame.sun_direction.z)));
    return (zenith * 0.65 + horizon * 0.5) * 1.1;
}

fn dimension_ambient() -> vec3<f32> {
    if in_nether() {
        return mix(vec3<f32>(0.16, 0.07, 0.04), to_linear(frame.fog_color) * 0.6, 0.5);
    }
    return vec3<f32>(0.075, 0.06, 0.1);
}

fn reconstruct_position(screen: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

fn cloud_wind() -> vec2<f32> {
    return vec2<f32>(frame.time * 4.0, frame.time * 1.5);
}

fn cloud_coverage_map(xz: vec2<f32>) -> f32 {
    let p = xz / 2400.0;
    return value_noise2(p) * 0.6 + value_noise2(p * 2.3 + 7.1) * 0.3 + value_noise2(p * 5.1) * 0.1;
}

fn cumulus_coverage_bias() -> f32 {
    return mix(-0.28, 0.32, cloud_coverage) + frame.rain * 0.3;
}

// A thin, streaky layer high above the cumulus: density 0..1 at a world-space point of it.
fn cirrus_density(xz: vec2<f32>) -> f32 {
    let p = (xz + cloud_wind() * 3.0) / 900.0;
    let warp = vec2<f32>(value_noise2(p * 0.7), value_noise2(p * 0.7 + 5.2)) * 1.6;
    let streak = value_noise2(vec2<f32>(p.x * 0.35, p.y * 2.6) + warp);
    let detail = value_noise2(p * 4.0 + warp * 2.0);
    let shape = streak * 0.75 + detail * 0.25;
    return smoothstep(0.52 - cloud_coverage * 0.2, 0.85, shape) * (1.0 - frame.rain * 0.6);
}

// Water surface height (x, blocks around 0) and its slope (yz).
fn wave_field(xz: vec2<f32>, t: f32) -> vec3<f32> {
    var height = 0.0;
    var slope = vec2<f32>(0.0);
    var dir = vec2<f32>(0.8, 0.6);
    var freq = 0.55;
    var amp = 0.5;
    var speed = 1.3;
    for (var i = 0; i < 5; i++) {
        let phase = dot(dir, xz) * freq + t * speed;
        height += amp * sin(phase);
        slope += amp * freq * cos(phase) * dir;
        dir = vec2<f32>(dir.x * 0.6 - dir.y * 0.8, dir.x * 0.8 + dir.y * 0.6);
        freq *= 1.73;
        amp *= 0.52;
        speed *= 1.21;
    }
    return vec3<f32>(height, slope) / 1.1;
}
