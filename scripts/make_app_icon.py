#!/usr/bin/env python3
"""Generates Snappy's 1024x1024 app icon.

Pure stdlib (zlib + struct) so the icon can be regenerated on any machine, and
in CI, without Pillow or a design tool. Run from the repo root:

    python3 scripts/make_app_icon.py
"""
import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Snappy/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
)


def lerp(a, b, t):
    return a + (b - a) * t


def pixel(x, y):
    # Diagonal gradient: warm yellow into magenta.
    t = (x / SIZE * 0.6) + (y / SIZE * 0.4)
    r = lerp(255, 236, t)
    g = lerp(214, 61, t)
    b = lerp(52, 148, t)

    cx = cy = SIZE / 2
    dx, dy = x - cx, y - cy
    dist = math.hypot(dx, dy)

    # Aperture ring.
    ring_outer, ring_inner = SIZE * 0.33, SIZE * 0.27
    if ring_inner <= dist <= ring_outer:
        return (255, 255, 255)

    # Shutter blades: six spokes cut from the inner disc.
    if dist < ring_inner:
        angle = math.atan2(dy, dx)
        blade = (angle + math.pi) % (math.pi / 3)
        if blade < 0.10 and dist > SIZE * 0.06:
            return (255, 255, 255)
        return (int(r * 0.35), int(g * 0.35), int(b * 0.35))

    return (int(r), int(g), int(b))


def main():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG filter type 0
        for x in range(SIZE):
            rows.extend(pixel(x, y))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(png)
    print(f"wrote {OUT} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
