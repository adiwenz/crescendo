#!/usr/bin/env python3
"""
Export a PNG of white text using the local Manrope variable font.

Requirements:
- Place `Manrope-VariableFont_wght.ttf` in the SAME directory as this script.

Examples:
  python manrope_text_png.py "Crescendo" -o crescendo.png --size 96
  python manrope_text_png.py "Welcome to\nCrescendo" -o welcome.png --size 72 --padding 40
"""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


FONT_FILENAME = "Manrope-VariableFont_wght.ttf"


def render_text_png(
    text: str,
    out_path: Path,
    font_path: Path,
    font_size: int,
    padding: int,
    line_spacing: int,
    bg: tuple[int, int, int, int],
    fill: tuple[int, int, int, int],
    align: str,
) -> None:
    font = ImageFont.truetype(str(font_path), font_size)

    # Measure multiline text
    dummy_img = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(dummy_img)
    bbox = d.multiline_textbbox(
        (0, 0),
        text,
        font=font,
        spacing=line_spacing,
        align=align,
    )

    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    img_w = text_w + padding * 2
    img_h = text_h + padding * 2

    img = Image.new("RGBA", (max(1, img_w), max(1, img_h)), bg)
    draw = ImageDraw.Draw(img)

    # Account for font bbox offset
    x = padding - bbox[0]
    y = padding - bbox[1]

    draw.multiline_text(
        (x, y),
        text,
        font=font,
        fill=fill,
        spacing=line_spacing,
        align=align,
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, format="PNG")


def parse_rgba(s: str) -> tuple[int, int, int, int]:
    """
    Accepts:
      - "transparent"
      - "#RRGGBB" or "#RRGGBBAA"
      - "r,g,b" or "r,g,b,a"
    """
    s = s.strip().lower()

    if s == "transparent":
        return (0, 0, 0, 0)

    if s.startswith("#"):
        hx = s[1:]
        if len(hx) == 6:
            r, g, b = int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)
            return (r, g, b, 255)
        if len(hx) == 8:
            r, g, b, a = (
                int(hx[0:2], 16),
                int(hx[2:4], 16),
                int(hx[4:6], 16),
                int(hx[6:8], 16),
            )
            return (r, g, b, a)
        raise ValueError("Hex colors must be #RRGGBB or #RRGGBBAA")

    parts = [p.strip() for p in s.split(",")]
    if len(parts) in (3, 4):
        vals = [int(p) for p in parts]
        if len(vals) == 3:
            return (vals[0], vals[1], vals[2], 255)
        return (vals[0], vals[1], vals[2], vals[3])

    raise ValueError(
        "Color must be 'transparent', '#RRGGBB', '#RRGGBBAA', 'r,g,b', or 'r,g,b,a'"
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Render white Manrope (variable font) text to a PNG."
    )
    ap.add_argument("text", help="Text to render. Use \\n for new lines.")
    ap.add_argument("-o", "--out", default="text.png", help="Output PNG path")
    ap.add_argument("--size", type=int, default=96, help="Font size in px")
    ap.add_argument("--padding", type=int, default=32, help="Padding around text")
    ap.add_argument("--line-spacing", type=int, default=12, help="Extra line spacing")
    ap.add_argument(
        "--bg",
        default="transparent",
        help="Background color (default: transparent)",
    )
    ap.add_argument(
        "--fill",
        default="255,255,255,255",
        help="Text color RGBA (default: white)",
    )
    ap.add_argument(
        "--align",
        default="left",
        choices=["left", "center", "right"],
        help="Multiline text alignment",
    )

    args = ap.parse_args()

    script_dir = Path(__file__).resolve().parent
    font_path = script_dir / FONT_FILENAME

    if not font_path.exists():
        raise FileNotFoundError(
            f"Font not found: {font_path}\n"
            f"Make sure {FONT_FILENAME} is in the same directory as this script."
        )

    bg = parse_rgba(args.bg)
    fill = parse_rgba(args.fill)

    render_text_png(
        text=args.text,
        out_path=Path(args.out),
        font_path=font_path,
        font_size=args.size,
        padding=args.padding,
        line_spacing=args.line_spacing,
        bg=bg,
        fill=fill,
        align=args.align,
    )

    print(f"Saved: {args.out}")


if __name__ == "__main__":
    main()
