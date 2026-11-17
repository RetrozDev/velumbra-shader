override exposure: f32 = 1.0;

const PI_F32: f32 = 3.14159265;

const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_WATER: u32 = 5u;

// Optical depths of a vertical column of air: Rayleigh, Mie and ozone.
const TAU_RAYLEIGH: vec3<f32> = vec3<f32>(0.0464, 0.108, 0.265);
const TAU_MIE: f32 = 0.03;
const TAU_OZONE: vec3<f32> = vec3<f32>(0.021, 0.06, 0.003);
const SKY_RADIANCE: f32 = 15.0;
const SUN_IRRADIANCE: f32 = 2.6;
const MOON_LIGHT: vec3<f32> = vec3<f32>(0.035, 0.05, 0.085);
const NIGHT_SKY: vec3<f32> = vec3<f32>(0.007, 0.009, 0.022);

const CLOUD_BOTTOM: f32 = 260.0;
const CLOUD_TOP: f32 = 470.0;

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

// Hable's filmic curve, normalised to a white point of 11.2.
fn filmic_curve(x: vec3<f32>) -> vec3<f32> {
    let a = 0.22;
    let b = 0.30;
    let c = 0.10;
    let d = 0.20;
    let e = 0.01;
    let f = 0.30;
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
}

// Exposure follows the light around the eye, so caves and nights open up a little.
fn scene_exposure() -> f32 {
    let eye_sky = frame.eye_light_smooth.y;
    let adapt = mix(1.7, 1.0, smoothstep(0.1, 0.7, eye_sky));
    return exposure * adapt * 2.0;
}

// Scene-referred linear light to the display-referred value the frame stores.
fn display_linear(hdr: vec3<f32>) -> vec3<f32> {
    let white = filmic_curve(vec3<f32>(11.2));
    return clamp(filmic_curve(hdr * scene_exposure()) / white, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn encode_display(hdr: vec3<f32>) -> vec3<f32> {
    return to_gamma(display_linear(hdr));
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
    let n000 = unit_float(hash_u32(i.x ^ y0z0));
    let n100 = unit_float(hash_u32((i.x + 1u) ^ y0z0));
    let n010 = unit_float(hash_u32(i.x ^ y1z0));
    let n110 = unit_float(hash_u32((i.x + 1u) ^ y1z0));
    let n001 = unit_float(hash_u32(i.x ^ y0z1));
    let n101 = unit_float(hash_u32((i.x + 1u) ^ y0z1));
    let n011 = unit_float(hash_u32(i.x ^ y1z1));
    let n111 = unit_float(hash_u32((i.x + 1u) ^ y1z1));
    let x00 = mix(n000, n100, w.x);
    let x10 = mix(n010, n110, w.x);
    let x01 = mix(n001, n101, w.x);
    let x11 = mix(n011, n111, w.x);
    return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z);
}

// Jimenez's interleaved gradient noise: a per-pixel offset that hides banding and undersampling.
fn pixel_dither(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(floor(pixel), vec2<f32>(0.06711056, 0.00583715))));
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

fn sun_visibility() -> f32 {
    return smoothstep(-0.12, 0.02, frame.sun_direction.y);
}

fn moon_visibility() -> f32 {
    return smoothstep(-0.05, 0.12, frame.moon_direction.y) * (1.0 - sun_visibility());
}

fn sun_transmittance(height_factor: f32) -> vec3<f32> {
    let m = air_mass(frame.sun_direction.y + 0.035) * height_factor;
    return exp(-(TAU_RAYLEIGH + TAU_MIE + TAU_OZONE) * m);
}

fn overcast() -> f32 {
    return clamp(frame.rain * 0.85 + frame.thunder * 0.15, 0.0, 1.0);
}

// Clear-sky radiance along `dir` from single scattering, plus the night sky.
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
    return mix(clear, grey, overcast());
}

// The light the sun (or the moon by night) lands on a surface facing it.
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

fn reconstruct_position(screen: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

fn cloud_coverage_map(xz: vec2<f32>) -> f32 {
    let p = xz / 2400.0;
    let n = value_noise2(p) * 0.6 + value_noise2(p * 2.3 + 7.1) * 0.3 + value_noise2(p * 5.1) * 0.1;
    return n;
}

fn cloud_wind() -> vec2<f32> {
    return vec2<f32>(frame.time * 4.0, frame.time * 1.5);
}

// Water surface height, in blocks around 0, and its slope.
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
