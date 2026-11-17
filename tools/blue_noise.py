"""Writes src/textures/blue_noise.png: four independent 64x64 blue-noise channels.

Ulichney's void-and-cluster method on a torus, one channel per seed.
Usage: python tools/blue_noise.py
"""

import pathlib
import numpy as np
from PIL import Image

SIZE = 64
SIGMA = 1.9


def gaussian_kernel(size: int, sigma: float) -> np.ndarray:
    d = np.minimum(np.arange(size), size - np.arange(size))
    d2 = d[:, None] ** 2 + d[None, :] ** 2
    return np.exp(-d2 / (2.0 * sigma * sigma))


def energy_of(pattern: np.ndarray, kernel_fft: np.ndarray) -> np.ndarray:
    return np.real(np.fft.ifft2(np.fft.fft2(pattern) * kernel_fft))


def void_and_cluster(rng: np.random.Generator) -> np.ndarray:
    n = SIZE * SIZE
    kernel = gaussian_kernel(SIZE, SIGMA)
    kernel_fft = np.fft.fft2(kernel)

    def shifted(y: int, x: int) -> np.ndarray:
        return np.roll(np.roll(kernel, y, axis=0), x, axis=1)

    pattern = np.zeros((SIZE, SIZE), dtype=bool)
    pattern.flat[rng.choice(n, n // 10, replace=False)] = True

    energy = energy_of(pattern.astype(float), kernel_fft)
    while True:
        tight = np.unravel_index(np.argmax(np.where(pattern, energy, -np.inf)), pattern.shape)
        pattern[tight] = False
        energy -= shifted(*tight)
        void = np.unravel_index(np.argmin(np.where(pattern, np.inf, energy)), pattern.shape)
        if void == tight:
            pattern[tight] = True
            energy += shifted(*tight)
            break
        pattern[void] = True
        energy += shifted(*void)

    ranks = np.zeros((SIZE, SIZE), dtype=np.int64)
    ones = int(pattern.sum())

    work = pattern.copy()
    energy = energy_of(work.astype(float), kernel_fft)
    for rank in range(ones - 1, -1, -1):
        tight = np.unravel_index(np.argmax(np.where(work, energy, -np.inf)), work.shape)
        work[tight] = False
        energy -= shifted(*tight)
        ranks[tight] = rank

    work = pattern.copy()
    energy = energy_of(work.astype(float), kernel_fft)
    for rank in range(ones, n):
        void = np.unravel_index(np.argmin(np.where(work, np.inf, energy)), work.shape)
        work[void] = True
        energy += shifted(*void)
        ranks[void] = rank

    return ranks


def main() -> None:
    channels = [void_and_cluster(np.random.default_rng(seed)) for seed in (11, 23, 37, 53)]
    rgba = np.stack(channels, axis=-1).astype(np.float64)
    rgba = np.floor(rgba * 256.0 / (SIZE * SIZE)).astype(np.uint8)
    out = pathlib.Path(__file__).resolve().parent.parent / "src" / "textures" / "blue_noise.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
