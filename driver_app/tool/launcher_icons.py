#!/usr/bin/env python3
"""Regenerate the Android and web launcher icons from the driver brand master.

    cd driver_app && python3 tool/launcher_icons.py     # needs Pillow + numpy

Run this instead of dropping resized PNGs into `res/mipmap-*` by hand. The
icons are not generated at build time — there is no `flutter_launcher_icons`
in the pubspec — so without this file the sizing rules below live nowhere and
get re-broken by the next person with an image editor. This is the driver
counterpart of `customer_app/tool/launcher_icons.py`; the two apps ship the
same red and the same rounded tile, so they have to be built the same way.

THE SAFE-ZONE RULE, INHERITED FROM THE CUSTOMER APP
---------------------------------------------------
Android hands the launcher a 108dp layer and only ever shows the middle 72dp
of it, and only the circle inscribed in THAT is safe on every OEM mask. Art
drawn to the edge of the layer is art drawn to be cropped — the customer icon
lost the bag's handle to a circular mask exactly that way. So the rider is
scaled against the 72dp mask, at the proportion it has in the master artwork,
and `radial_reach` fails the run if any of it strays outside the safe circle.

WHY THIS SCRIPT IS DOING IMAGE FORENSICS
----------------------------------------
The master is a finished, flattened picture: a white rider composited over a
red gradient tile, with a soft drop shadow between them. An adaptive icon
needs those back as two independent layers, because the launcher moves and
scales them separately. So:

  * `gradient()` recovers the tile by least-squares fitting a linear ramp to
    the CLEAN BORDER of the master — the red that the rider and its shadow do
    not touch — and extrapolating that ramp across the whole layer. Averaging
    the tile in place instead (the obvious approach) bakes a blurred ghost of
    the scooter into the background layer, which then slides around under the
    foreground on any launcher that parallaxes the two.
  * `mark()` recovers the rider by unmixing each pixel against that fitted
    tile. The shadow is deliberately NOT carried into the foreground: it
    belongs to neither layer once they can move independently, and the
    customer icon's bag does not carry one either.

Both are derived from the master every run, including the rider's size and
placement, so re-exporting the artwork is all it takes to re-issue the icon.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

RES = 'android/app/src/main/res'
MASTER = '../assets/driver-app-icon.png'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Adaptive icons are 108dp layers with a 72dp mask viewport.
MASK_OF_LAYER = 72 / 108

# Browsers crop a `maskable` PWA icon to its inner 80%.
WEB_SAFE = 0.8

# Resolution the tile fit runs at. The gradient is a low-frequency ramp, so a
# quarter-megapixel is plenty and it keeps the least-squares solve instant.
FIT_PX = 256

# How far the rider's silhouette is grown before its surroundings are trusted
# as clean tile, as a fraction of the tile's width. Sized to clear the drop
# shadow: too small and the shadow pulls the fitted ramp dark near the middle.
SHADOW_MARGIN = 0.06


def master_tile():
    """The master with its transparent margin trimmed: the rounded red tile."""
    im = Image.open(MASTER).convert('RGBA')
    return im.crop(im.getbbox())


def gradient(tile):
    """Fit the tile's red ramp, as a function returning RGB for a grid of size n.

    Returns a callable rather than an image because the ramp is sampled at six
    different resolutions below, and resampling a rendered one would soften it.
    """
    small = np.asarray(tile.resize((FIT_PX, FIT_PX), Image.LANCZOS)).astype(np.float32)
    rgb, alpha = small[..., :3], small[..., 3]

    # Everything the rider plausibly touches, grown to swallow its shadow.
    rider = ((alpha > 250) & (rgb.min(axis=2) > 150)).astype(np.uint8) * 255
    grow = int(FIT_PX * SHADOW_MARGIN) | 1
    grown = np.asarray(Image.fromarray(rider, 'L').filter(ImageFilter.MaxFilter(grow)))
    clean = (alpha > 250) & (grown == 0)
    if clean.mean() < 0.15:
        sys.exit('FAIL: too little clean tile left to fit the gradient from.')

    ys, xs = np.nonzero(clean)

    def basis(u, v):
        return np.stack([np.ones_like(u), u, v], axis=1)

    span = FIT_PX - 1
    coef, *_ = np.linalg.lstsq(
        basis(xs / span * 2 - 1, ys / span * 2 - 1), rgb[clean], rcond=None)
    residual = rgb[clean] - basis(xs / span * 2 - 1, ys / span * 2 - 1) @ coef
    print('  tile ramp fitted on %.0f%% of the master, rms %s' % (
        clean.mean() * 100, np.abs(residual).std(axis=0).round(2)))

    def sample(n):
        gy, gx = np.mgrid[0:n, 0:n].astype(np.float32)
        u = (gx / (n - 1) * 2 - 1).ravel()
        v = (gy / (n - 1) * 2 - 1).ravel()
        # float32, not float64: these get handed to Pillow as 'F' buffers, and
        # Pillow reinterprets the bytes rather than converting them.
        return (basis(u, v) @ coef).reshape(n, n, 3).clip(0, 255).astype(np.float32)

    return sample


def mark(tile, ramp):
    """Cut the white rider out of the master, and measure how it sits on the tile.

    Alpha comes from the green channel: the tile's green sits near 30 and the
    rider's at 255, so it separates them with far more headroom than red does
    (the tile is already 246 red — there is nowhere for white to go).
    """
    a = np.asarray(tile).astype(np.float32)
    h, w, _ = a.shape
    field = np.stack([
        np.asarray(Image.fromarray(c, 'F').resize((w, h), Image.BICUBIC))
        for c in np.moveaxis(ramp(FIT_PX), 2, 0)
    ], axis=-1)

    tg = field[..., 1]
    alpha = np.clip((a[..., 1] - tg) / (255.0 - tg), 0, 1) * (a[..., 3] / 255.0)
    alpha[alpha < 0.02] = 0

    ys, xs = np.nonzero(alpha > 0.5)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    cut = Image.fromarray(np.dstack([
        np.full((h, w, 3), 255, np.uint8), (alpha * 255).astype(np.uint8)
    ]), 'RGBA').crop(box)

    # Proportions of the TILE, so the launcher shows the master's composition.
    place = (
        (box[2] - box[0]) / w,
        (box[3] - box[1]) / h,
        ((box[0] + box[2]) / 2 - w / 2) / w,
        ((box[1] + box[3]) / 2 - h / 2) / h,
    )
    print('  rider %dx%d, %.1f%% x %.1f%% of the tile, offset %+.2f%% %+.2f%%'
          % (cut.size[0], cut.size[1], place[0] * 100, place[1] * 100,
             place[2] * 100, place[3] * 100))
    return cut, place


def foreground(rider, place, layer_px):
    """The rider alone on a transparent 108dp layer, sized against the 72dp mask."""
    w_of, h_of, x_off, y_off = place
    canvas = Image.new('RGBA', (layer_px, layer_px), (0, 0, 0, 0))
    mask_px = layer_px * MASK_OF_LAYER
    w = round(mask_px * w_of)
    h = round(mask_px * h_of)
    canvas.alpha_composite(
        rider.resize((w, h), Image.LANCZOS),
        (round((layer_px - w) / 2 + mask_px * x_off),
         round((layer_px - h) / 2 + mask_px * y_off)),
    )
    return canvas


def radial_reach(fg):
    """Furthest opaque pixel from centre, as a fraction of the mask's radius."""
    alpha = np.asarray(fg)[..., 3]
    n = fg.size[0]
    ys, xs = np.nonzero(alpha > 32)
    c = (n - 1) / 2
    return float(np.hypot(xs - c, ys - c).max()) / (n * MASK_OF_LAYER / 2)


def as_image(arr):
    return Image.fromarray(arr.astype(np.uint8), 'RGB')


def main():
    tile = master_tile()
    print(f'master {MASTER} -> tile {tile.size[0]}x{tile.size[1]}')
    ramp = gradient(tile)
    rider, place = mark(tile, ramp)

    reach = radial_reach(foreground(rider, place, 432))
    print(f'  radial reach {reach:.3f} of mask')
    if reach >= 1.0:
        sys.exit('FAIL: the art reaches past the mask and will be clipped.')

    for name, scale in DENSITIES.items():
        d = f'{RES}/mipmap-{name}'
        layer = round(108 * scale)
        foreground(rider, place, layer).save(f'{d}/ic_launcher_foreground.png')
        # The background is full-bleed and opaque on purpose: the mask does the
        # rounding, so a layer with the master's own rounded corners would show
        # the corners twice on a squircle and let daylight through on a circle.
        as_image(ramp(layer)).save(f'{d}/ic_launcher_background.png')
        # Legacy square icon (API 23-25, and the odd launcher that still asks
        # for it): the master tile as drawn, shadow and all, nothing masked.
        legacy = round(48 * scale)
        tile.resize((legacy, legacy), Image.LANCZOS).save(f'{d}/ic_launcher.png')
        print(f'  {name}: layers {layer}px, legacy {legacy}px')

    for px in (192, 512):
        # Kept RGBA. Flattening to RGB drops the alpha on the tile's rounded
        # corners and PNG leaves what is underneath — black — so the icon ends
        # up a red squircle in a black box.
        tile.resize((px, px), Image.LANCZOS).save(f'web/icons/Icon-{px}.png')
        m = as_image(ramp(px)).convert('RGBA')
        w = round(px * WEB_SAFE * place[0])
        h = round(px * WEB_SAFE * place[1])
        m.alpha_composite(rider.resize((w, h), Image.LANCZOS),
                          (round((px - w) / 2), round((px - h) / 2)))
        m.convert('RGB').save(f'web/icons/Icon-maskable-{px}.png')
    tile.resize((64, 64), Image.LANCZOS).save('web/favicon.png')
    print('  web: Icon-192/512, Icon-maskable-192/512, favicon 64px')

    # The in-app copy of the mark, used by nothing today but kept in step with
    # the launcher so the two can never disagree.
    tile.resize((512, 512), Image.LANCZOS).convert('RGB').save(
        'assets/app_icon_master.png')
    print('  assets/app_icon_master.png: 512px')


if __name__ == '__main__':
    if not os.path.isdir(RES):
        sys.exit('run me from driver_app/')
    main()
