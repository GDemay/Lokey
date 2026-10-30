#!/usr/bin/env python3
"""Renders the 1024x1024 app icon (a check mark on a green squircle-free square; iOS masks the corners).
Pure Python (no Pillow) so it runs anywhere: python3 scripts/make_icon.py out.png"""
import math
import struct
import sys
import zlib

N = 1024
TOP, BOTTOM = (0x2F, 0xA3, 0x7A), (0x16, 0x6B, 0x52)
# Check mark polyline (fractions of the icon) and stroke half-width.
PTS = [(0.27, 0.53), (0.43, 0.68), (0.74, 0.35)]
HALF = 0.055


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def pixel(x, y):
    fx, fy = (x + 0.5) / N, (y + 0.5) / N
    bg = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * fy) for i in range(3))
    d = min(seg_dist(fx, fy, *PTS[i], *PTS[i + 1]) for i in range(len(PTS) - 1))
    a = max(0.0, min(1.0, (HALF - d) * N + 0.5))  # 1px anti-aliasing
    return bytes(int(bg[i] * (1 - a) + 255 * a) for i in range(3))


def main(path):
    rows = b"".join(b"\x00" + b"".join(pixel(x, y) for x in range(N)) for y in range(N))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


if __name__ == "__main__":
    main(sys.argv[1])
