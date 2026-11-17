# Changelog

All notable changes to Velumbra are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - unreleased

### Added
- HDR post chain: an invertible storage curve, half-float passes and one filmic curve at the end.
- Exposure that adapts to caves and nights.
- Quality presets: Low, Medium, High and Ultra.
- Night sky: twinkling stars and a procedural Milky Way that turn with the sky.
- Auroras, more frequent in cold biomes, with an intensity setting.
- Cirrus layer above the cumulus.
- Multiple-scattering approximation for clouds.
- Percentage-closer soft shadows, stained-glass tinted light and underwater caustics.
- Screen-space reflections on water, falling back to the sky and clouds.
- Volumetric mist in caves, the Nether and the End, and fog for both dimensions.
- Block light with a slight direction.
- Jimenez's 13-tap bloom from HDR, temporal filter with colour clipping.
- Blue-noise texture for every ray march and filter.
- Pack icon and an options screen with pages.
- `tools/check.py`, which checks the pack against Horizon's own prelude and rules.
- `tools/preview.py`, offline previews of the sky, clouds, water and tone curve.

### Changed
- Clouds and light shafts moved to a half-resolution post pass with temporal accumulation.
- Vanilla clouds, sun and stars are replaced by the pack's own.
- Fog is applied by the pack instead of Horizon.
- Mirror water reflections are off by default.

## [1.0.0] - 2026-11-17

### Added
- First release: scattering sky, volumetric clouds, soft sun shadows, light shafts, waving plants, reflective
  water, atmospheric fog, filmic tone mapping, bloom and warm grade.
