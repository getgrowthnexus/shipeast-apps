#!/usr/bin/env python3
"""Regenerate the Android and web launcher icons from the brand master.

    cd customer_app && python3 tool/launcher_icons.py

Run this instead of dropping resized PNGs into `res/mipmap-*` by hand. The
icons are not generated at build time — there is no `flutter_launcher_icons`
in the pubspec — so without this file the sizing rules below live nowhere and
get re-broken by the next person with an image editor.

WHAT WENT WRONG THE FIRST TIME
------------------------------
The adaptive-icon FOREGROUND was drawn at ~96% of the launcher's mask, so
every launcher shape sliced the bag's sides and bottom off; on a circular
mask (Pixel's default) it lost the handle too. Android hands the launcher a
108dp layer and only ever shows the middle 72dp of it, and only the circle
inscribed in THAT is safe on every OEM mask. Art drawn to the edge of the
layer is art drawn to be cropped.

WHAT THIS DOES
--------------
Scales the bag to the proportion it has in the master artwork — 61.9% of the
tile's width, 73.2% of its height, centred — measured against the 72dp mask
rather than the 108dp layer. What the launcher shows is then the same
composition as `assets/customer-app-icon.png`, which is the whole point.

`radial_reach` reports the check that matters: the furthest opaque pixel from
the centre as a fraction of the mask's radius. Keep it under 1.0 and no mask
shape in existence can clip the mark.
"""

import os
import sys
from PIL import Image

RES = 'android/app/src/main/res'
MASTER = '../assets/customer-app-icon.png'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Measured off the master: the white bag against the red tile it sits on.
BAG_W_OF_TILE = 0.619
BAG_H_OF_TILE = 0.732
# The bag sits a hair above the tile's optical centre in the master.
BAG_Y_NUDGE = -0.012

# Adaptive icons are 108dp layers with a 72dp mask viewport.
MASK_OF_LAYER = 72 / 108

# Browsers crop a `maskable` PWA icon to its inner 80%.
WEB_SAFE = 0.8


def bag_source():
    """The bag alone, cut out of the existing foreground at the largest size.

    The foreground PNG already carries the right alpha — including the hole
    under the handle's arch, which no colour-keying scheme gets right because
    that hole is enclosed by white exactly the way the location pin is. So the
    cutout is reused rather than re-derived from the master.
    """
    fg = Image.open(
        f'{RES}/mipmap-xxxhdpi/ic_launcher_foreground.png').convert('RGBA')
    return fg.crop(fg.getbbox())


def foreground(bag, layer_px):
    canvas = Image.new('RGBA', (layer_px, layer_px), (0, 0, 0, 0))
    mask_px = layer_px * MASK_OF_LAYER
    w = round(mask_px * BAG_W_OF_TILE)
    h = round(mask_px * BAG_H_OF_TILE)
    canvas.alpha_composite(
        bag.resize((w, h), Image.LANCZOS),
        (round((layer_px - w) / 2),
         round((layer_px - h) / 2 + mask_px * BAG_Y_NUDGE)),
    )
    return canvas


def radial_reach(fg):
    """Furthest opaque pixel from centre, as a fraction of the mask's radius."""
    px = fg.load()
    n = fg.size[0]
    c = (n - 1) / 2
    r = n * MASK_OF_LAYER / 2
    worst = 0.0
    for y in range(n):
        for x in range(n):
            if px[x, y][3] > 32:
                worst = max(worst, ((x - c) ** 2 + (y - c) ** 2) ** 0.5)
    return worst / r


def main():
    bag = bag_source()
    reach = radial_reach(foreground(bag, 432))
    print(f'bag {bag.size[0]}x{bag.size[1]}, radial reach {reach:.3f} of mask')
    if reach >= 1.0:
        sys.exit('FAIL: the art reaches past the mask and will be clipped.')

    tile = Image.open(MASTER).convert('RGBA')
    tile = tile.crop(tile.getbbox())

    for name, scale in DENSITIES.items():
        d = f'{RES}/mipmap-{name}'
        layer = round(108 * scale)
        foreground(bag, layer).save(f'{d}/ic_launcher_foreground.png')
        # Legacy square icon (API 23-25, and the odd launcher that still asks
        # for it): the master tile as drawn, nothing masked, nothing scaled up.
        legacy = round(48 * scale)
        tile.resize((legacy, legacy), Image.LANCZOS).save(f'{d}/ic_launcher.png')
        print(f'  {name}: foreground {layer}px, legacy {legacy}px')

    bg = Image.open(
        f'{RES}/mipmap-xxxhdpi/ic_launcher_background.png').convert('RGBA')
    for px in (192, 512):
        tile.resize((px, px), Image.LANCZOS).convert('RGB').save(
            f'web/icons/Icon-{px}.png')
        m = bg.resize((px, px), Image.LANCZOS).convert('RGBA')
        w = round(px * WEB_SAFE * BAG_W_OF_TILE)
        h = round(px * WEB_SAFE * BAG_H_OF_TILE)
        m.alpha_composite(bag.resize((w, h), Image.LANCZOS),
                          (round((px - w) / 2), round((px - h) / 2)))
        m.convert('RGB').save(f'web/icons/Icon-maskable-{px}.png')
    print('  web: Icon-192/512 and Icon-maskable-192/512')


if __name__ == '__main__':
    if not os.path.isdir(RES):
        sys.exit('run me from customer_app/')
    main()
