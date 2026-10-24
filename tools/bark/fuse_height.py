"""A sharper height map from the displacement map plus the normal map of the same material.

The displacement map is smooth; the normal map holds the crisp rims. The gradient of the surface is -n.xy / n.z, integrated over the
(periodic) tile with the Frankot-Chellappa FFT method gives a height whose fine detail is the normal map's. The two are combined:
the displacement for wavelengths above the crossover, the integrated normal map (scaled to match the displacement's gradients in the
band where both are reliable) below it.

  python fuse_height.py <folder> <name> <out 16-bit png> [crossover sigma px]"""
import sys

import limits  # (first)

import cv2
import numpy as np


def integrate(gx, gy):
    """Frankot-Chellappa: the height whose gradient is closest to (gx, gy), for a periodic tile."""
    h, w = gx.shape
    fx = np.fft.fftfreq(w)[None, :] * 2 * np.pi
    fy = np.fft.fftfreq(h)[:, None] * 2 * np.pi
    gxf, gyf = np.fft.fft2(gx), np.fft.fft2(gy)
    denom = fx ** 2 + fy ** 2
    denom[0, 0] = 1.0
    z = (-1j * fx * gxf - 1j * fy * gyf) / denom
    z[0, 0] = 0.0
    return np.real(np.fft.ifft2(z))


def main():
    folder, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
    sigma_c = float(sys.argv[4]) if len(sys.argv) > 4 else 6.0
    disp = cv2.imread(f"{folder}/{name}_disp.png", cv2.IMREAD_UNCHANGED).astype(np.float32)
    if disp.ndim == 3:
        disp = disp.mean(axis=2)
    disp = cv2.resize(disp, (1024, 1024), interpolation=cv2.INTER_AREA)
    disp = (disp - disp.min()) / (disp.max() - disp.min())
    nor = cv2.imread(f"{folder}/{name}_nor_gl.jpg").astype(np.float32)[..., ::-1] / 255.0 * 2.0 - 1.0
    nor = cv2.resize(nor, (1024, 1024), interpolation=cv2.INTER_AREA)
    nz = np.maximum(nor[..., 2], 0.2)
    gx = -nor[..., 0] / nz
    gy = nor[..., 1] / nz  # OpenGL normal maps have green up; image rows go down
    hn = integrate(gx, gy)  # units: the normal map's pixel units
    # scale hn so that its gradients match the displacement's in the band 12..40 px (both reliable there)
    def band(x):
        return cv2.GaussianBlur(x, (0, 0), 3.0) - cv2.GaussianBlur(x, (0, 0), 10.0)
    bn, bd = band(hn), band(disp)
    k = float((bn * bd).sum() / (bn * bn).sum())
    corr = float((bn * bd).sum() / np.sqrt((bn * bn).sum() * (bd * bd).sum()))
    print(f"scale of the integrated normal map to the displacement: {k:.4f}; they agree (band 3..10 px) with correlation {corr:.2f}")
    low = cv2.GaussianBlur(disp, (0, 0), sigma_c)
    high = k * (hn - cv2.GaussianBlur(hn, (0, 0), sigma_c))
    fused = (low + high).astype(np.float32)
    fused = (fused - fused.min()) / (fused.max() - fused.min())
    cv2.imwrite(out, (fused * 65535.0).astype(np.uint16))
    for label, h in (("displacement", disp), ("fused", fused)):
        sm = cv2.GaussianBlur(h, (0, 0), 1.0)
        slope = np.hypot(cv2.Sobel(sm, cv2.CV_32F, 1, 0), cv2.Sobel(sm, cv2.CV_32F, 0, 1)) / 8.0
        print(f"{label:13s} slope percentiles 50/90/99/99.9: {np.percentile(slope, [50, 90, 99, 99.9]).round(4)}")
    sh = lambda h: np.clip(0.5 - 8.0 * (cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 0.7), cv2.CV_32F, 1, 0) + cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 0.7), cv2.CV_32F, 0, 1)) / 8.0, 0, 1)
    cv2.imwrite(out.replace(".png", "_vs.png"), (np.hstack([sh(disp), sh(fused)]) * 255).astype(np.uint8))


if __name__ == "__main__":
    main()
