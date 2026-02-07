#!/usr/bin/env python3
"""
Render Manrope text to PNG.

Supports:
- Prefer static font files (Manrope-Bold.ttf, Manrope-SemiBold.ttf, etc) if present.
- Otherwise uses Manrope-VariableFont_wght.ttf.
- If Pillow cannot apply variable 'wght', fallback to faux-bold via stroke.

Put these in the same folder as the script (any subset is fine):
  Manrope-VariableFont_wght.ttf
  Manrope-Regular.ttf
  Manrope-Medium.ttf
  Manrope-SemiBold.ttf
  Manrope-Bold.ttf
  Manrope-ExtraBold.ttf
  Manrope-Light.ttf
  Manrope-ExtraLight.ttf
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


VARIABLE_FONT = "Manrope-VariableFont_wght.ttf"

# Optional static fonts (recommended for reliable bold)
STATIC_FONTS = {
    200: "Manrope-ExtraLight.ttf",
    300: "Manrope-Light.ttf",
    400: "Manrope-Regular.ttf",
    500: "Manrope-Medium.ttf",
    600: "Manrope-SemiBold.ttf",
    700: "Manrope-Bold.ttf",
    800: "Manrope-ExtraBold.ttf",
}

def parse_rgba(s: str) -> tuple[int, int, int, int]:
    s = s.strip().lower()
    if s == "transparent":
        return (0, 0, 0, 0)
    if s.startswith("#"):
        hx = s[1:]
        if len(hx) == 6:
            return (int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16), 255)
        if len(hx) == 8:
            return (
                int(hx[0:2], 16),
                int(hx[2:4], 16),
                int(hx[4:6], 16),
                int(hx[6:8], 16),
            )
        raise ValueError("Hex colors must be #RRGGBB or #RRGGBBAA")

    parts = [p.strip() for p in s.split(",")]
    if len(parts) in (3, 4):
        vals = [int(p) for p in parts]
        if len(vals) == 3:
            return (vals[0], vals[1], vals[2], 255)
        return (vals[0], vals[1], vals[2], vals[3])

    raise ValueError("Color must be 'transparent', '#RRGGBB[AA]', or 'r,g,b[,a]'")


def nearest_static_weight(requested: int) -> int:
    # Snap to nearest available Manrope static weight key
    keys = sorted(STATIC_FONTS.keys())
    return min(keys, key=lambda k: abs(k - requested))


def load_font(
    font_dir: Path,
    size: int,
    weight: int,
) -> tuple[ImageFont.FreeTypeFont, bool, bool]:
    """
    Returns: (font, variable_axes_applied, using_static_font)
    """
    # Prefer static font if present for requested (nearest) weight
    snapped = nearest_static_weight(weight)
    static_path = font_dir / STATIC_FONTS[snapped]
    if static_path.exists():
        return ImageFont.truetype(str(static_path), size), True, True  # "applied" via file choice

    # Fallback: variable font
    var_path = font_dir / VARIABLE_FONT
    if not var_path.exists():
        raise FileNotFoundError(
            f"Missing font. Put {VARIABLE_FONT} (and optionally static Manrope TTFS) in:\n{font_dir}"
        )

    font = ImageFont.truetype(str(var_path), size)

    applied = False
    # Try multiple APIs Pillow sometimes supports depending on version/build
    try:
        # Pillow 10+ may support this in some builds
        font.set_variation_by_axes([("wght", int(weight))])
        applied = True
    except Exception:
        pass

    if not applied:
        try:
            # Some builds expose a dict-style API
            font.font_variation(wght=int(weight))  # type: ignore[attr-defined]
            applied = True
        except Exception:
            pass

    return font, applied, False


def faux_bold_stroke_width(font_size: int, weight: int) -> int:
    # Scale stroke based on how "bold" you want it.
    # At weight 700, stroke ~ 6-8% of font size looks reasonable.
    if weight <= 500:
        return 0
    strength = (weight - 500) / 300.0  # 0..~1 for 500->800
    return max(1, int(round(font_size * (0.05 + 0.03 * strength))))


def render_text_png(
    text: str,
    out_path: Path,
    font: ImageFont.FreeTypeFont,
    font_size: int,
    weight: int,
    variation_applied: bool,
    padding: int,
    line_spacing: int,
    bg: tuple[int, int, int, int],
    fill: tuple[int, int, int, int],
    align: str,
    italic: bool,
    underline: bool,
    strikethrough: bool,
) -> None:
    dummy = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(dummy)

    bbox = d.multiline_textbbox((0, 0), text, font=font, spacing=line_spacing, align=align)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    img_w = text_w + padding * 2
    img_h = text_h + padding * 2
    if italic:
        img_w += int(math.ceil(font_size * 0.25))

    img = Image.new("RGBA", (max(1, img_w), max(1, img_h)), bg)

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)

    x = padding - bbox[0]
    y = padding - bbox[1]

    # If variable weight could not be applied, fake heavier weights via stroke
    stroke_w = 0
    if not variation_applied:
        stroke_w = faux_bold_stroke_width(font_size, weight)

    ld.multiline_text(
        (x, y),
        text,
        font=font,
        fill=fill,
        spacing=line_spacing,
        align=align,
        stroke_width=stroke_w,
        stroke_fill=fill,
    )

    if italic:
        shear = 0.28
        layer = layer.transform(
            layer.size,
            Image.AFFINE,
            (1, shear, 0, 0, 1, 0),
            resample=Image.BICUBIC,
        )

    img.alpha_composite(layer)

    if underline or strikethrough:
        draw = ImageDraw.Draw(img)
        ascent, descent = font.getmetrics()
        line_height = ascent + descent + line_spacing
        line_thickness = max(1, int(round(font_size * 0.06)))

        lines = text.splitlines() or [text]
        for i, line in enumerate(lines):
            if line == "":
                continue

            lb = d.textbbox((0, 0), line, font=font)
            lw = lb[2] - lb[0]

            if align == "left":
                lx = x
            elif align == "center":
                lx = x + (text_w - lw) / 2
            else:
                lx = x + (text_w - lw)

            baseline_y = y + i * line_height + ascent

            if underline:
                uy = baseline_y + max(1, int(font_size * 0.10))
                draw.line((lx, uy, lx + lw, uy), fill=fill, width=line_thickness)

            if strikethrough:
                sy = baseline_y - int(ascent * 0.35)
                draw.line((lx, sy, lx + lw, sy), fill=fill, width=line_thickness)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, format="PNG")


def main() -> None:
    ap = argparse.ArgumentParser(description="Render Manrope text to PNG with robust bold handling.")
    ap.add_argument("text", help="Text to render. Use \\n for new lines.")
    ap.add_argument("-o", "--out", default="text.png", help="Output PNG path")
    ap.add_argument("--size", type=int, default=96, help="Font size in px")
    ap.add_argument("--weight", type=int, default=500, help="Desired weight (e.g. 400, 600, 700, 800)")
    ap.add_argument("--padding", type=int, default=32, help="Padding around text")
    ap.add_argument("--line-spacing", type=int, default=12, help="Extra line spacing in px")
    ap.add_argument("--bg", default="transparent", help="Background: transparent, #RRGGBB[AA], or r,g,b[,a]")
    ap.add_argument("--fill", default="255,255,255,255", help="Text color: #RRGGBB[AA] or r,g,b[,a]")
    ap.add_argument("--align", default="left", choices=["left", "center", "right"], help="Multiline alignment")

    ap.add_argument("--italic", action="store_true", help="Apply synthetic italic (shear)")
    ap.add_argument("--underline", action="store_true", help="Underline text")
    ap.add_argument("--strikethrough", action="store_true", help="Strikethrough text")

    args = ap.parse_args()

    script_dir = Path(__file__).resolve().parent
    font, variation_applied, using_static = load_font(script_dir, args.size, args.weight)

    bg = parse_rgba(args.bg)
    fill = parse_rgba(args.fill)

    render_text_png(
        text=args.text,
        out_path=Path(args.out),
        font=font,
        font_size=args.size,
        weight=args.weight,
        variation_applied=variation_applied,
        padding=args.padding,
        line_spacing=args.line_spacing,
        bg=bg,
        fill=fill,
        align=args.align,
        italic=args.italic,
        underline=args.underline,
        strikethrough=args.strikethrough,
    )

    mode = "static-ttf" if using_static else ("variable-wght" if variation_applied else "variable-default+fauxbold")
    print(f"Saved: {args.out} (font mode: {mode})")


if __name__ == "__main__":
    main()
