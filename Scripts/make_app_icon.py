#!/usr/bin/env python3
"""
Turn a piece of icon artwork into the app icon asset.

Why this is not just a copy
---------------------------
iOS applies its own rounded-corner mask to every app icon, so the artwork must
be a **full square with opaque corners**. Art exported with rounded corners
arrives one of two ways, and both are wrong:

* transparent corners  -> the App Store rejects icons with an alpha channel
* black corners        -> dark wedges can peek out around the system mask

This script squares the artwork off by extending each row's background colour
outward into the corners. Because it samples per row it follows a gradient
background instead of flattening it to one flat colour, then resizes to the
1024x1024 Xcode wants.

Usage
-----
    python Scripts/make_app_icon.py ~/Downloads/app_icon.png

Writes Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.
Re-run it any time the artwork changes.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required.  python -m pip install Pillow")
    sys.exit(1)

REPO_ROOT = Path(__file__).resolve().parent.parent
ICON_SET = REPO_ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
OUTPUT_NAME = "AppIcon-1024.png"
FINAL_SIZE = 1024

# A pixel darker than this on every channel is treated as masked-out corner
# rather than real artwork.
DARK_THRESHOLD = 60
# Step this far past the first light pixel before sampling, to skip the
# antialiased blend between the corner and the background.
ANTIALIAS_SKIP = 4


def is_dark(pixel: tuple[int, int, int]) -> bool:
    return all(channel < DARK_THRESHOLD for channel in pixel[:3])


def square_off_corners(image: Image.Image) -> tuple[Image.Image, int]:
    """Extend each row's edge colour outward, filling rounded-off corners."""
    width, height = image.size
    pixels = image.load()
    filled = 0

    for y in range(height):
        left = 0
        while left < width and is_dark(pixels[left, y]):
            left += 1
        if left >= width:
            continue  # entirely dark row; nothing to sample

        right = width - 1
        while right >= 0 and is_dark(pixels[right, y]):
            right -= 1

        if left > 0:
            source = pixels[min(left + ANTIALIAS_SKIP, width - 1), y]
            for x in range(left + ANTIALIAS_SKIP):
                pixels[x, y] = source
            filled += left

        if right < width - 1:
            source = pixels[max(right - ANTIALIAS_SKIP, 0), y]
            for x in range(max(right - ANTIALIAS_SKIP, 0), width):
                pixels[x, y] = source
            filled += width - 1 - right

    return image, filled


def write_contents_json() -> None:
    """Single-size app icon (Xcode 14+). One 1024 image, Xcode derives the rest."""
    contents = {
        "images": [
            {
                "filename": OUTPUT_NAME,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    path = ICON_SET / "Contents.json"
    path.write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(REPO_ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the app icon asset from artwork.")
    parser.add_argument("source", help="path to the source artwork (square PNG)")
    args = parser.parse_args()

    source = Path(args.source).expanduser()
    if not source.exists():
        print(f"ERROR: {source} not found.")
        return 1

    image = Image.open(source)
    print(f"source: {image.size[0]}x{image.size[1]}, mode {image.mode}")

    if image.size[0] != image.size[1]:
        print(f"ERROR: artwork must be square, got {image.size[0]}x{image.size[1]}.")
        return 1

    # Flatten any alpha onto white first; an app icon must have no alpha channel.
    if image.mode in ("RGBA", "LA", "P"):
        image = image.convert("RGBA")
        backdrop = Image.new("RGBA", image.size, (255, 255, 255, 255))
        image = Image.alpha_composite(backdrop, image)
    image = image.convert("RGB")

    image, filled = square_off_corners(image)
    print(f"squared off corners: {filled} pixels repainted")

    if image.size[0] != FINAL_SIZE:
        image = image.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)
        print(f"resized to {FINAL_SIZE}x{FINAL_SIZE}")

    ICON_SET.mkdir(parents=True, exist_ok=True)
    destination = ICON_SET / OUTPUT_NAME
    image.save(destination, "PNG", optimize=True)

    verify = Image.open(destination)
    corners = [
        verify.getpixel((0, 0)),
        verify.getpixel((FINAL_SIZE - 1, 0)),
        verify.getpixel((0, FINAL_SIZE - 1)),
        verify.getpixel((FINAL_SIZE - 1, FINAL_SIZE - 1)),
    ]
    print(f"wrote {destination.relative_to(REPO_ROOT)} "
          f"({destination.stat().st_size // 1024} KB, mode {verify.mode})")
    print(f"corner pixels now: {corners}")

    if verify.mode != "RGB":
        print("ERROR: output still has an alpha channel.")
        return 1
    if any(all(c < DARK_THRESHOLD for c in corner) for corner in corners):
        print("ERROR: corners are still dark.")
        return 1

    write_contents_json()
    print("\nOK - app icon asset is ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
