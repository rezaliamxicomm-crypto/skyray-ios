#!/usr/bin/env python3
"""The App Store icon: the same comet as the Android app (scripts/skyray_icon.py, the operator's drawing),
painted at 1024x1024 without an alpha channel (App Store Connect refuses transparency). Run from the repo
root; the file lands in the asset catalog. Pure Python, a few minutes.

    python3 scripts/icon.py
"""
import importlib.util, pathlib, struct, zlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("skyray_icon", ROOT / "scripts/skyray_icon.py"); I = importlib.util.module_from_spec(spec); spec.loader.exec_module(I)
OUT = ROOT / "SkyRay/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def png_rgb(path, w, h, rows_rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    rows = []
    for r in rows_rgba:                       # drop the alpha byte: the square icon is opaque everywhere
        rows.append(b"\x00" + bytes(v for i, v in enumerate(r) if i % 4 != 3))
    raw = b"".join(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    print(f"{path.relative_to(ROOT)}  {w}x{h} RGB")


if __name__ == "__main__":
    w, h, rows = I.paint(1024, "none", "icon", ss=2)
    png_rgb(OUT, w, h, rows)
