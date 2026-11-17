"""Renders previews of Velumbra's sky, night sky, clouds, water and tone curve into preview/.

A NumPy port of the pack's own formulas (common.wgsl, sky.wgsl, post/volume.wgsl, terrain/water.wgsl
and post/final.wgsl), so looks can be judged without the game.
Usage: python tools/preview.py
"""

import pathlib
import numpy as np
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "preview"
np.seterr(over="ignore", invalid="ignore", divide="ignore")
U32 = np.uint32

TAU_R = np.array([0.0464, 0.108, 0.265])
TAU_M = 0.03
TAU_O = np.array([0.035, 0.095, 0.005])
SKY_RADIANCE, SUN_IRRADIANCE, SUN_DISC = 15.0, 2.6, 60.0
MOON_LIGHT = np.array([0.035, 0.05, 0.085])
NIGHT_SKY = np.array([0.007, 0.009, 0.022])
GALACTIC_NORTH = np.array([0.28, 0.42, 0.86])
GALACTIC_CORE = np.array([0.93, -0.33, -0.14])
GALACTIC_NORTH = GALACTIC_NORTH / np.linalg.norm(GALACTIC_NORTH)
GALACTIC_CORE = GALACTIC_CORE / np.linalg.norm(GALACTIC_CORE)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def hash_u32(x):
    x = x.astype(U32)
    h = x * U32(747796405) + U32(2891336453)
    h = ((h >> ((h >> U32(28)) + U32(4))) ^ h) * U32(277803737)
    return (h >> U32(22)) ^ h


def unit_float(h):
    return (h >> U32(8)).astype(np.float64) / 16777216.0


def value_noise2(p):
    i = np.floor(p).astype(np.int64)
    f = p - np.floor(p)
    w = f * f * (3.0 - 2.0 * f)

    def h(ix, iy):
        return unit_float(hash_u32(ix.astype(np.int32).view(U32) ^ hash_u32(iy.astype(np.int32).view(U32))))

    a, b = h(i[..., 0], i[..., 1]), h(i[..., 0] + 1, i[..., 1])
    c, d = h(i[..., 0], i[..., 1] + 1), h(i[..., 0] + 1, i[..., 1] + 1)
    return (a + (b - a) * w[..., 0]) * (1 - w[..., 1]) + (c + (d - c) * w[..., 0]) * w[..., 1]


def value_noise3(p):
    i = np.floor(p).astype(np.int64).astype(np.int32).view(U32)
    f = p - np.floor(p)
    w = f * f * (3.0 - 2.0 * f)
    x, y, z = i[..., 0], i[..., 1], i[..., 2]
    z0, z1 = hash_u32(z), hash_u32(z + U32(1))
    y0z0, y1z0 = hash_u32(y ^ z0), hash_u32((y + U32(1)) ^ z0)
    y0z1, y1z1 = hash_u32(y ^ z1), hash_u32((y + U32(1)) ^ z1)

    def lx(a):
        return unit_float(hash_u32(x ^ a)), unit_float(hash_u32((x + U32(1)) ^ a))

    def mixx(pair):
        return pair[0] + (pair[1] - pair[0]) * w[..., 0]

    x00, x10, x01, x11 = mixx(lx(y0z0)), mixx(lx(y1z0)), mixx(lx(y0z1)), mixx(lx(y1z1))
    a = x00 + (x10 - x00) * w[..., 1]
    b = x01 + (x11 - x01) * w[..., 1]
    return a + (b - a) * w[..., 2]


def hg(c, g):
    return (1 - g * g) / (4 * np.pi * np.power(np.maximum(1 + g * g - 2 * g * c, 1e-4), 1.5))


def air_mass(mu):
    m = np.clip(mu, 0.0, 1.0)
    z = np.degrees(np.arccos(m))
    return 1.0 / (m + 0.50572 * np.power(np.maximum(96.07995 - z, 0.5), -1.6364))


class Frame:
    def __init__(self, sun_height, rain=0.0, time=100.0, temperature=0.8, quality=1, exposure=1.0):
        a = np.arcsin(np.clip(sun_height, -1, 1))
        self.sun = np.array([np.cos(a), np.sin(a), 0.0])
        self.moon = -self.sun
        self.rain, self.time, self.temperature, self.quality, self.exposure = rain, time, temperature, quality, exposure

    def sun_visibility(self):
        return smoothstep(-0.12, 0.02, self.sun[1])

    def moon_visibility(self):
        return smoothstep(-0.05, 0.12, self.moon[1]) * (1 - self.sun_visibility())

    def overcast(self):
        return np.clip(self.rain * 0.85, 0, 1)

    def scene_exposure(self):
        return self.exposure * 1.15 * (1 + 1.3 * (1 - self.sun_visibility()))

    def sun_transmittance(self, height_factor=1.0):
        m = air_mass(np.array(self.sun[1] + 0.035)) * height_factor
        return np.exp(-(TAU_R + TAU_M + TAU_O) * np.asarray(m)[..., None])

    def clear_sky(self, d):
        up = np.maximum(d[..., 1], 0)
        c = d @ self.sun
        mv = air_mass(up)[..., None]
        sv = self.sun_visibility()
        st = self.sun_transmittance(1 - 0.65 * np.sqrt(up)) * sv
        tr = TAU_R * 2
        tau = tr + TAU_M
        pr = 3 / (16 * np.pi) * (1 + c * c)
        pm = hg(c, 0.8)
        scatter = (tr * pr[..., None] + TAU_M * pm[..., None] * 0.5) / tau * (1 - np.exp(-tau * mv))
        night = NIGHT_SKY * (1 - sv * 0.85) * (0.5 + 0.5 * (1 - np.exp(-mv * 0.3)))
        glow = MOON_LIGHT * 0.12 * hg(d @ self.moon, 0.7)[..., None] * self.moon_visibility()
        return SKY_RADIANCE * st * scatter + night + glow

    def sky_radiance(self, d):
        clear = self.clear_sky(d)
        grey = (clear @ np.array([0.2126, 0.7152, 0.0722]))[..., None] * np.array([0.62, 0.66, 0.72])
        sky = clear + (grey - clear) * self.overcast()
        below = np.where(d[..., 1] < 0, 1 - 0.65 * smoothstep(0.0, -0.3, d[..., 1]), 1.0)
        return sky * below[..., None]

    def direct_light(self):
        sun = SUN_IRRADIANCE * self.sun_transmittance()[0] * self.sun_visibility()
        return (sun + MOON_LIGHT * self.moon_visibility()) * (1 - self.overcast() * 0.88)

    def sun_disc(self, d):
        dist = np.sqrt(np.maximum(2 - 2 * (d @ self.sun), 0))
        r = np.clip(dist / 0.0125, 0, 1)
        limb = np.power(np.maximum(1 - r * r, 0), 0.3)
        edge = 1 - smoothstep(0.85, 1.0, dist / 0.0125)
        return SUN_DISC * self.sun_transmittance()[0] * (limb * edge * smoothstep(-0.02, 0.01, d[..., 1]))[..., None] * self.sun_visibility()

    def celestial(self, d):
        angle = np.arctan2(self.sun[0], self.sun[1])
        c, n = np.cos(angle), np.sin(angle)
        return np.stack([c * d[..., 0] - n * d[..., 1], n * d[..., 0] + c * d[..., 1], d[..., 2]], -1)

    def stars(self, cdir):
        grid = cdir * 220.0
        cell = np.floor(grid)
        idv = cell.astype(np.int64).astype(np.int32).view(U32)
        h = hash_u32(idv[..., 0] ^ hash_u32(idv[..., 1] ^ hash_u32(idv[..., 2])))
        presence = unit_float(h)
        h2 = hash_u32(h)
        centre = cell + 0.25 + 0.5 * np.stack([unit_float(h2), unit_float(hash_u32(h2)), unit_float(hash_u32(h2 ^ U32(0x9E3779B9)))], -1)
        dd = np.linalg.norm(grid - centre, axis=-1)
        mag = unit_float(hash_u32(h2 + U32(7))) ** 6
        tw = 0.7 + 0.3 * np.sin(self.time * (2 + 5 * unit_float(h2 + U32(3))) + presence * 60)
        temp = unit_float(hash_u32(h2 + U32(11)))[..., None]
        tint = np.array([1.0, 0.72, 0.5]) * (1 - temp) + np.array([0.7, 0.82, 1.0]) * temp
        v = (0.05 + mag * 2.5) * tw * np.exp(-dd * dd * 28) * (presence <= 0.06)
        return tint * v[..., None]

    def milky_way(self, c):
        lat = c @ GALACTIC_NORTH
        band = np.exp(-lat * lat / 0.018)
        core = np.power(np.maximum(c @ GALACTIC_CORE, 0), 3)
        p = c * 9.0
        glow = value_noise3(p) * 0.6 + value_noise3(p * 2.1 + 3.7) * 0.4
        dust = 0.0
        if self.quality >= 1:
            glow = glow * 0.75 + value_noise3(p * 4.7) * 0.25
            lane = np.exp(-np.power(lat - 0.02 * np.sin((c @ GALACTIC_CORE) * 9), 2) / 0.0016)
            dust = lane * smoothstep(0.35, 0.75, value_noise3(p * 3.3 + 11.0)) * 0.85
        core3 = core[..., None]
        tint = np.array([0.55, 0.62, 0.9]) * (1 - core3) + np.array([1.0, 0.82, 0.62]) * core3
        return tint * (band * glow * (0.025 + core * 0.06) * (1 - dust))[..., None]

    def aurora(self, d, layers=14):
        drift = np.array([self.time * 0.004, self.time * 0.0015])
        light = np.zeros(d.shape)
        dy = np.maximum(d[..., 1], 0.02)
        for i in range(layers):
            h = (i + 0.5) / layers
            xz = d[..., [0, 2]] / dy[..., None] * (1 + h * 0.45) * 0.55
            warp = np.stack([value_noise2(xz * 1.3 + drift * 3), value_noise2(xz * 1.3 + 9.1)], -1) * 0.6
            ridge = 1 - np.abs(value_noise2((xz + warp) * np.array([2.2, 0.6]) + drift) * 2 - 1)
            curtain = ridge ** 14 * smoothstep(0.3, 0.6, value_noise2(xz * 0.5 - drift))
            s = smoothstep(0.25, 1.0, h)
            color = np.array([0.1, 1.0, 0.45]) * (1 - s) + np.array([0.55, 0.2, 0.9]) * s
            light += color * (curtain * np.exp(-h * 2.2))[..., None]
        return light / layers * 0.35 * (smoothstep(0.02, 0.25, d[..., 1]) * (d[..., 1] > 0.02))[..., None]

    def night(self, d, aurora_activity=1.0):
        darkness = (1 - self.sun_visibility()) * (1 - self.overcast())
        if darkness <= 0:
            return np.zeros(d.shape)
        ext = smoothstep(-0.05, 0.25, d[..., 1])[..., None]
        c = self.celestial(d)
        light = (self.stars(c) + self.milky_way(c)) * ext
        light += self.aurora(d) * aurora_activity
        return light * darkness * (d[..., 1] > -0.05)[..., None]

    def sky(self, d, aurora_activity=1.0):
        return self.sky_radiance(d) + self.sun_disc(d) + self.night(d, aurora_activity)


def display(hdr, frame, bloom=None, saturation=1.1, warmth=1.0, vignette=True):
    x = np.maximum(hdr * frame.scene_exposure(), 0)
    if bloom is not None:
        x = x + bloom
    c = 1 - np.exp(-x)
    c = c * (1 + (np.array([1.05, 1.0, 0.92]) - 1) * warmth)
    lum = (c @ np.array([0.2126, 0.7152, 0.0722]))[..., None]
    c = np.maximum(lum + (c - lum) * saturation, 0)
    g = np.power(c, 1 / 2.2)
    g = g + (g * g * (3 - 2 * g) - g) * 0.12
    if vignette:
        h, w = g.shape[:2]
        v, u = np.meshgrid(np.linspace(-0.5, 0.5, h), np.linspace(-0.5, 0.5, w), indexing="ij")
        g = g * np.clip(1 - (u * u + v * v) * 0.55, 0, 1)[..., None]
    return np.clip(g, 0, 1)


def camera_rays(width, height, yaw, pitch, fov=70.0):
    aspect = width / height
    t = np.tan(np.radians(fov) / 2)
    xs = np.linspace(-t * aspect, t * aspect, width)
    ys = np.linspace(t, -t, height)
    x, y = np.meshgrid(xs, ys)
    d = np.stack([x, y, -np.ones_like(x)], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    cp, sp, cy, sy = np.cos(pitch), np.sin(pitch), np.cos(yaw), np.sin(yaw)
    d = np.stack([d[..., 0], d[..., 1] * cp - d[..., 2] * sp, d[..., 1] * sp + d[..., 2] * cp], -1)
    return np.stack([d[..., 0] * cy + d[..., 2] * sy, d[..., 1], -d[..., 0] * sy + d[..., 2] * cy], -1)


def panorama(width, height, top=1.0, bottom=-0.15):
    v = np.linspace(top, bottom, height)
    u = np.linspace(-np.pi, np.pi, width)
    el = np.arcsin(v)[:, None]
    az = u[None, :]
    return np.stack([np.cos(el) * np.sin(az), np.sin(el) * np.ones_like(az), np.cos(el) * np.cos(az)], -1)


def label(img, text):
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, 8 + 7 * len(text), 18], fill=(0, 0, 0))
    draw.text((4, 3), text, fill=(255, 255, 255))
    return img


def to_image(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))


def sky_times():
    rows = []
    for h, name in [(0.9, "noon"), (0.35, "afternoon"), (0.08, "golden hour"), (0.0, "sunset"),
                    (-0.06, "dusk"), (-0.5, "night")]:
        f = Frame(h)
        d = panorama(720, 150)
        rows.append(label(to_image(display(f.sky(d, aurora_activity=0.0), f, vignette=False)), name))
    out = Image.new("RGB", (720, 150 * len(rows)))
    for i, r in enumerate(rows):
        out.paste(r, (0, 150 * i))
    out.save(OUT / "sky-times.png")


def night_sky():
    f = Frame(-0.6, temperature=0.0, quality=1)
    d = camera_rays(960, 540, yaw=np.radians(100), pitch=np.radians(28), fov=80)
    label(to_image(display(f.sky(d, aurora_activity=1.0), f)), "night, cold biome: stars, Milky Way, aurora").save(OUT / "night-aurora.png")
    d = camera_rays(960, 540, yaw=np.radians(-60), pitch=np.radians(45), fov=80)
    label(to_image(display(f.sky(d, aurora_activity=0.0), f)), "night, temperate: Milky Way").save(OUT / "night-milky-way.png")
    f_low = Frame(-0.6, quality=0)
    label(to_image(display(f_low.sky(d, aurora_activity=0.0), f_low)), "night, Low preset (simplified Milky Way)").save(OUT / "night-milky-way-low.png")


def cumulus_density(p, time, coverage=0.5, rain=0.0, detail=True):
    h = (p[..., 1] - 260.0) / 210.0
    wind = np.array([time * 4.0, 0.0, time * 1.5])
    q = p + wind
    pxz = q[..., [0, 2]] / 2400.0
    cov = value_noise2(pxz) * 0.6 + value_noise2(pxz * 2.3 + 7.1) * 0.3 + value_noise2(pxz * 5.1) * 0.1
    cov = cov + (-0.28 + 0.6 * coverage) + rain * 0.3
    profile = smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.35, h)
    shape = value_noise3(q / 190.0) * 0.62 + value_noise3(q / 85.0) * 0.38
    if detail:
        shape = shape - value_noise3(q / 29.0) * 0.16 * (1 - h * 0.5)
    d = np.clip((shape * profile + cov - 1.0) * 3.2, 0, 1)
    return np.where((h > 0) & (h < 1) & (cov >= 0.35), d, 0.0)


def multiple_scattering(tau, cos_theta):
    total, a, b, c = 0.0, 1.0, 1.0, 1.0
    for _ in range(3):
        phase = hg(cos_theta, -0.15 * c) * 0.3 + hg(cos_theta, 0.7 * c) * 0.7
        total = total + b * phase * np.exp(-tau * a)
        a, b, c = a * 0.45, b * 0.55, c * 0.5
    return total * 4 * np.pi


def clouds_view(frame, d, camera_y=80.0, steps=22, light_steps=4):
    sky = frame.sky(d, aurora_activity=0.0)
    dy = np.where(np.abs(d[..., 1]) < 1e-3, 1e-3, d[..., 1])
    tb, tt = (260 - camera_y) / dy, (470 - camera_y) / dy
    t0 = np.maximum(np.minimum(tb, tt), 0)
    t1 = np.minimum(np.maximum(tb, tt), 9000)
    valid = (t1 > t0) & (d[..., 1] > 0.0)
    step = np.where(valid, (t1 - t0) / steps, 0)
    to_light = frame.sun if frame.sun[1] > -0.05 else frame.moon
    cos_t = d @ to_light
    high_sun = SUN_IRRADIANCE * frame.sun_transmittance(0.55)[0] * frame.sun_visibility() + MOON_LIGHT * frame.moon_visibility()
    sun = high_sun * (1 - frame.overcast() * 0.88) * 1.8
    ambient = frame.sky_radiance(np.array([[0.0, 1.0, 0.0]]))[0] * 1.1 + np.array([0.002, 0.003, 0.006])
    T = np.ones(d.shape[:-1])
    S = np.zeros(d.shape)
    rng = np.random.default_rng(1)
    jitter = rng.random(d.shape[:-1])
    cam = np.array([0.0, camera_y, 0.0])
    for i in range(steps):
        t = t0 + step * (i + jitter)
        p = cam + d * t[..., None]
        dens = np.where(valid, cumulus_density(p, frame.time), 0)
        ld = np.zeros_like(dens)
        for j in range(light_steps):
            reach = 36 * (j + 0.5) * (1 + j * 0.7)
            ld += cumulus_density(p + to_light * reach, frame.time, detail=False) * 36 * (1 + j * 0.7)
        st = np.exp(-dens * 0.045 * step)
        powder = 1 - np.exp(-dens * 2.5)
        h = (p[..., 1] - 260) / 210
        lit = sun * (multiple_scattering(ld * 0.045, cos_t) * (0.6 + 0.4 * powder))[..., None] + ambient * (0.35 + 0.65 * h)[..., None]
        S += (T * (1 - st))[..., None] * lit
        T *= st
    fade = (np.exp(-t0 / 7000) * smoothstep(0, 0.06, np.abs(d[..., 1])) * valid)[..., None]
    return sky * (1 - fade + fade * T[..., None]) + S * fade


def clouds():
    for h, name in [(0.55, "clouds-day"), (0.04, "clouds-sunset")]:
        f = Frame(h)
        d = camera_rays(640, 360, yaw=np.radians(-60 if h < 0.3 else 30), pitch=np.radians(12), fov=75)
        label(to_image(display(clouds_view(f, d), f)), f"{name.replace('-', ' ')} (Medium: 14 steps, here 22 for the still)").save(OUT / f"{name}.png")


def water():
    f = Frame(0.18)
    w, hgt = 800, 450
    d = camera_rays(w, hgt, yaw=np.radians(-75), pitch=np.radians(-8), fov=75)
    eye = 2.5
    below = d[..., 1] < -1e-3
    t = np.where(below, eye / np.maximum(-d[..., 1], 1e-3), 0)
    p = d * t[..., None]
    xz = p[..., [0, 2]]
    height, slope = np.zeros(xz.shape[:-1]), np.zeros(xz.shape)
    direc, freq, amp, speed = np.array([0.8, 0.6]), 0.55, 0.5, 1.3
    for _ in range(5):
        phase = xz @ direc * freq + 100 * speed
        height += amp * np.sin(phase)
        slope += (amp * freq * np.cos(phase))[..., None] * direc
        direc = np.array([direc[0] * 0.6 - direc[1] * 0.8, direc[0] * 0.8 + direc[1] * 0.6])
        freq, amp, speed = freq * 1.73, amp * 0.52, speed * 1.21
    slope /= 1.1
    strength = 0.16 * np.exp(-t / 48)
    n = np.stack([-slope[..., 0] * strength, np.ones_like(strength), -slope[..., 1] * strength], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    v = -d
    r = d - 2 * (d * n).sum(-1, keepdims=True) * n
    r[..., 1] = np.maximum(r[..., 1], 0.01)
    r /= np.linalg.norm(r, axis=-1, keepdims=True)
    refl = f.sky_radiance(r) + f.sun_disc(r) * 0.0
    cos_v = np.clip((n * v).sum(-1), 0, 1)
    fresnel = (0.02 + 0.98 * (1 - cos_v) ** 5)[..., None]
    biome = np.array([0.247, 0.463, 0.894]) ** 2.2
    amb = f.sky_radiance(np.array([[0, 1.0, 0]]))[0] * 1.1
    body = amb * biome * np.array([0.12, 0.32, 0.38]) + f.direct_light() * biome * np.array([0.02, 0.06, 0.07])
    floor = np.array([0.35, 0.3, 0.2]) * (f.direct_light() * 0.6 + amb * 0.5)
    thickness = 3.0 + 0.04 * t
    transmit = np.exp(-np.array([0.30, 0.075, 0.055]) * thickness[..., None])
    col = floor * transmit + body * (1 - transmit)
    col = col * (1 - fresnel) + refl * fresnel
    h_vec = v + f.sun
    h_vec /= np.linalg.norm(h_vec, axis=-1, keepdims=True)
    nh = np.clip((n * h_vec).sum(-1), 0, 1)
    a2 = 0.08 ** 4
    dterm = a2 / (np.pi * (nh * nh * (a2 - 1) + 1) ** 2) * np.clip(n @ f.sun, 0, 1)
    col += f.direct_light() * (dterm * 8)[..., None] * fresnel
    sky = f.sky(d, aurora_activity=0.0)
    img = np.where(below[..., None], col, sky)
    hdr = img * f.scene_exposure()
    bright = np.maximum(hdr - 1.2, 0)
    small = Image.fromarray(np.clip(bright / 8 * 255, 0, 255).astype(np.uint8)).resize((w // 4, hgt // 4), Image.BILINEAR)
    blur = np.asarray(small.resize((w, hgt), Image.BICUBIC)).astype(float) / 255 * 8
    label(to_image(display(img, f, bloom=blur * 0.3)), "water at golden hour (sky reflection, waves, sun glint, bloom)").save(OUT / "water.png")


def tone_curve():
    w, h = 640, 360
    img = Image.new("RGB", (w, h), (24, 24, 28))
    draw = ImageDraw.Draw(img)
    xs = np.linspace(0, 8, 400)
    pts = [(40 + x / 8 * (w - 60), h - 30 - (1 - np.exp(-x)) ** (1 / 2.2) * (h - 60)) for x in xs]
    draw.line(pts, fill=(255, 196, 120), width=3)
    draw.line([(40, h - 30), (w - 20, h - 30)], fill=(120, 120, 120))
    draw.line([(40, 30), (40, h - 30)], fill=(120, 120, 120))
    draw.text((50, 10), "stored and final curve: gamma(1 - e^-x), x = scene light x exposure (0..8)", fill=(230, 230, 230))
    ramp = np.linspace(0, 6, w)[None, :, None] * np.ones((40, 1, 3))
    f = Frame(0.5)
    f.exposure = 1 / f.scene_exposure()
    strip = to_image(display(ramp, f, vignette=False))
    out = Image.new("RGB", (w, h + 40))
    out.paste(img, (0, 0))
    out.paste(strip, (0, h))
    out.save(OUT / "tone-curve.png")


def blue_noise():
    src = pathlib.Path(__file__).resolve().parent.parent / "src" / "textures" / "blue_noise.png"
    a = np.asarray(Image.open(src))
    tiles = [Image.fromarray(a[..., c]).resize((256, 256), Image.NEAREST) for c in range(4)]
    spectrum = np.abs(np.fft.fftshift(np.fft.fft2(a[..., 0] - a[..., 0].mean())))
    spectrum = Image.fromarray(np.clip(spectrum / spectrum.max() * 255 * 2, 0, 255).astype(np.uint8)).resize((256, 256), Image.NEAREST)
    out = Image.new("L", (256 * 5, 256))
    for i, t in enumerate(tiles + [spectrum]):
        out.paste(t, (256 * i, 0))
    out.save(OUT / "blue-noise.png")


def main():
    OUT.mkdir(exist_ok=True)
    import sys
    names = sys.argv[1:]
    for step in (sky_times, night_sky, clouds, water, tone_curve, blue_noise):
        if names and step.__name__ not in names:
            continue
        step()
        print(f"{step.__name__}: done")


if __name__ == "__main__":
    main()
