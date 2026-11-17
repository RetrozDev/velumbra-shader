<p align="center">
  <img src="assets/logo-256.png" alt="Velumbra" width="256">
</p>

<h1 align="center">Velumbra</h1>

<p align="center">A warm, cinematic shader pack for <a href="https://playhorizon.dev">Horizon</a>, the Minecraft client rewritten in Rust.</p>

Velumbra is written from scratch in WGSL for Horizon's native shader API. It aims for the soft, golden look
of classic Minecraft shader packs using publicly documented techniques:

- **Sky**: analytic single scattering (Rayleigh and Mie phase functions, Kasten–Young air mass, ozone
  absorption) for deep blue noons, orange sunsets and blue twilights.
- **Volumetric clouds**: ray-marched cumulus slab with Beer–Lambert extinction, a powder term and a
  dual-lobe Henyey–Greenstein phase.
- **Soft shadows**: sun and moon shadow maps filtered with a rotated golden-angle disc, with a bias that
  follows the shadow map's distortion.
- **Light shafts**: volumetric god rays ray-marched through the shadow map, also under water.
- **Water**: animated wave normals, Fresnel blend of planar reflections and the scattered sky, refraction,
  depth-based absorption and a sun glint.
- **Lighting**: warm sunlight, blue sky ambient, warm block light, translucent foliage, wet surfaces in rain.
- **Atmosphere and grade**: height fog tinted by the sky, render-distance fog that blends into it, filmic
  tone mapping (Hable), soft two-ring bloom, warm grade and vignette.
- **Motion**: leaves, grass, flowers and crops sway with the wind; water surfaces move.

## Installation

1. Download `velumbra-<version>.hshader` from the releases, or build it (below).
2. Put it in Horizon's shader pack folder:
   - Windows: `%APPDATA%\horizon\shaderpacks\`
   - Or use the button that opens the pack folder in the game's shader pack screen.
3. In the game, pick **Velumbra** in the shader pack list.
4. Recommended: set **Clouds** to **Off** in the video settings, so vanilla clouds do not draw over the
   volumetric ones.

## Settings

Every setting is in the shader pack's option screen in game.

| Setting | Default | What it does |
|---|---|---|
| Exposure | 1.0 | Brightness before the filmic curve. |
| Sun shadows | on | Shadow maps cast by terrain, trees and entities. |
| Shadow resolution | 1536 | 1024, 1536 or 2048 texels. |
| Shadow distance | 128 | 64 to 160 blocks. |
| Shadow softness | 1.0 | Width of the penumbra. |
| Volumetric clouds | Medium | Off, Low, Medium or High (ray-march steps). |
| Cloud coverage | 0.5 | How much of the sky the clouds cover. |
| Light shafts | Medium | Off, Low, Medium or High. |
| Light shaft strength | 1.0 | Density of the lit air. |
| Atmospheric fog | 1.0 | Distance haze. |
| Water waves | on | Moving waves and normals. |
| Water reflections | on | Planar terrain reflections (renders the world a second time). |
| Waving plants | on | Wind on leaves, grass, flowers and crops. |
| Bloom | 0.6 | Glow around bright light; 0 turns it off. |
| Saturation | 1.1 | Colour intensity. |
| Warmth | 1.0 | Warm grade; 0 is neutral. |
| Vignette | on | Darkened corners. |

On a low-end GPU, lower the cloud quality and light shafts first, then the shadow resolution.

## Building

The pack is a zip of `src/` (plus this README and the license) named `dist/velumbra-<version>.hshader`.

```powershell
./build.ps1                  # Windows PowerShell
```

```bash
./build.sh                   # Linux, macOS, Git Bash
```

Both scripts validate every shader module with [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga)
first (`cargo install naga-cli`). A module is checked the way Horizon compiles it: a stand-in for Horizon's
prelude (`tools/prelude/`), then `common.wgsl`, then the stage's files. Pass `-SkipValidation` or
`--skip-validation` to package without naga.

## Layout

```
src/horizon-shaders.toml   manifest: stages, materials, shadow map, options
src/common.wgsl            shared: atmosphere, noise, tone mapping, waves
src/sky.wgsl               sky and volumetric clouds
src/material.wgsl          terrain lighting, shadows, water
src/vertex.wgsl            wind and waves
src/weather.wgsl           rain and snow
src/post/atmosphere.wgsl   fog and light shafts
src/post/grade.wgsl        bloom and colour grade
tools/prelude/             validation stand-ins for Horizon's prelude
```

## Limits

Horizon's shader API 0.1 renders into an 8-bit frame, so each stage tone maps its own output and bloom
works on the display-referred picture. Entities and the vanilla sun, moon and stars are drawn by Horizon
itself, and the Nether and the End keep vanilla lighting.

## License

[MIT](LICENSE). The logo is part of the project and shares its license.
