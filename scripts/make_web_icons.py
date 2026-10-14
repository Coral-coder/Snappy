#!/usr/bin/env python3
"""Generates the PWA icons from the same aperture mark as the native app icon.

Pure stdlib (zlib + struct), so icons can be regenerated anywhere, including CI,
without Pillow or a design tool.

    python3 scripts/make_web_icons.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "web/icons")

# (filename, size, padding) — maskable icons need the mark inside the safe area.
TARGETS = [
    ("icon-180.png", 180, 0.0),
    ("icon-192.png", 192, 0.0),
    ("icon-512.png", 512, 0.0),
    ("icon-maskable-512.png", 512, 0.18),
]


def lerp(a, b, t):
    return a + (b - a) * t


def pixel(x, y, size, pad):
    t = (x / size * 0.6) + (y / size * 0.4)
    r = lerp(255, 236, t)
    g = lerp(214, 61, t)
    b = lerp(52, 148, t)

    centre = size / 2
    dx, dy = x - centre, y - centre
    dist = math.hypot(dx, dy)
    unit = size * (1.0 - pad * 2)

    ring_outer, ring_inner = unit * 0.33, unit * 0.27
    if ring_inner <= dist <= ring_outer:
        return (255, 255, 255)

    if dist < ring_inner:
        angle = math.atan2(dy, dx)
        blade = (angle + math.pi) % (math.pi / 3)
        if blade < 0.10 and dist > unit * 0.06:
            return (255, 255, 255)
        return (int(r * 0.35), int(g * 0.35), int(b * 0.35))

    return (int(r), int(g), int(b))


def write_png(path, size, pad):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            rows.extend(pixel(x, y, size, pad))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as handle:
        handle.write(png)
    return len(png)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, size, pad in TARGETS:
        written = write_png(os.path.join(OUT_DIR, name), size, pad)
        print(f"wrote web/icons/{name} ({written} bytes)")


if __name__ == "__main__":
    main()
