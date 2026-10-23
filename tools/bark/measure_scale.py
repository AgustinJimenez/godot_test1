"""Measures the feature size of a photographed height map, to cap the SCALE parameters of a fit before it runs.

  python measure_scale.py <folder> <name> <tile metres>

Prints, for the detrended height, the lag (cm) where the autocorrelation falls to 1/e along x and along y, and
the spacing of the strongest repeat along y (rings, courses). A free fit that makes features much bigger than
these numbers is cheating the statistics: keep cell/leaf/plate sizes within about 0.5x to 2x.
"""
import sys

import cv2
import numpy as np


def correlation_length(image, axis):
    """Lag in pixels where the autocorrelation along an axis first falls below 1/e."""
    line = image - image.mean(axis=axis, keepdims=True)
    spectrum = np.fft.rfft(line, axis=axis)
    acf = np.fft.irfft(spectrum * np.conj(spectrum), n=image.shape[axis], axis=axis).mean(axis=1 - axis)
    acf = acf / acf[0]
    below = np.where(acf < 1.0 / np.e)[0]
    return int(below[0]) if below.size else image.shape[axis] // 2


def repeat_spacing(image, minimum_px=6):
    """Lag in pixels of the strongest autocorrelation peak along y (beyond the first decay)."""
    line = image - image.mean(axis=0, keepdims=True)
    spectrum = np.fft.rfft(line, axis=0)
    acf = np.fft.irfft(spectrum * np.conj(spectrum), n=image.shape[0], axis=0).mean(axis=1)
    acf = acf[: image.shape[0] // 2] / acf[0]
    first = np.where(acf < 0.0)[0]
    start = max(int(first[0]) if first.size else minimum_px, minimum_px)
    return int(start + np.argmax(acf[start:])), float(acf[start:].max())


def main():
    folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
    photo = cv2.imread(f"{folder}/{name}_disp.png", cv2.IMREAD_UNCHANGED).astype(np.float32)
    if photo.ndim == 3:
        photo = photo.mean(axis=2)
    cm_per_px = tile_m * 100.0 / photo.shape[1]
    detrended = photo - cv2.GaussianBlur(photo, (0, 0), 40)
    lx = correlation_length(detrended, 1) * cm_per_px
    ly = correlation_length(detrended, 0) * cm_per_px
    spacing, strength = repeat_spacing(detrended)
    print(f"{name}: {photo.shape[1]}x{photo.shape[0]} px, {cm_per_px:.3f} cm/px")
    print(f"  feature size (1/e): {lx:.1f} cm across, {ly:.1f} cm along the trunk/rows")
    print(f"  strongest repeat along y: {spacing * cm_per_px:.1f} cm (autocorrelation {strength:.2f})")


if __name__ == "__main__":
    main()
