"""Convert a plain-text PPM (P3) to PNG using only the standard library.

Usage: python3 tools/pixelart/ppm2png.py <in.ppm> <out.png>
"""

import struct
import sys
import zlib


def read_ppm(path):
    with open(path, "r", encoding="ascii") as handle:
        tokens = []
        for line in handle:
            tokens.extend(line.split("#", 1)[0].split())
    if not tokens or tokens[0] != "P3":
        raise SystemExit(f"{path}: not a P3 PPM")
    width, height, maxval = int(tokens[1]), int(tokens[2]), int(tokens[3])
    if maxval != 255:
        raise SystemExit(f"{path}: only maxval 255 is supported")
    data = bytes(map(int, tokens[4:]))
    if len(data) != width * height * 3:
        raise SystemExit(f"{path}: expected {width * height * 3} samples, got {len(data)}")
    return width, height, data


def chunk(kind, payload):
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path, width, height, data):
    stride = width * 3
    # Each scanline is prefixed with filter type 0 (none).
    raw = b"".join(b"\x00" + data[y * stride:(y + 1) * stride] for y in range(height))
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        handle.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    width, height, data = read_ppm(sys.argv[1])
    write_png(sys.argv[2], width, height, data)
    print(f"{sys.argv[2]}: {width}x{height}")


if __name__ == "__main__":
    main()
