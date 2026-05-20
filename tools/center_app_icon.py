"""Centra el logo MatchGol en canvas cuadrado y genera foreground adaptativo."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
# Fuente original (evitar reprocesar icon.png ya escalado)
SRC = ROOT / "assets" / "icon" / "icon.png.png"
if not SRC.exists():
    SRC = ROOT / "assets" / "icon" / "icon.png"
OUT = ROOT / "assets" / "icon" / "icon.png"
OUT_ADAPTIVE = ROOT / "assets" / "icon" / "icon_adaptive_foreground.png"
OUT_SIZE = 1024
BG = (13, 27, 42, 255)  # #0D1B2A

# Márgenes: ~10–14% deja el logo grande sin que el círculo Android lo recorte.
MARGIN_LAUNCHER = 0.10
MARGIN_ADAPTIVE = 0.14


def is_content(px: tuple[int, ...], bg: tuple[int, ...], tol: int = 28) -> bool:
    if len(px) == 3:
        px = (*px, 255)
    return any(abs(int(px[i]) - int(bg[i])) > tol for i in range(3))


def content_bbox(im: Image.Image, bg: tuple[int, ...]) -> tuple[int, int, int, int]:
    w, h = im.size
    pixels = im.convert("RGBA").load()
    min_x, min_y, max_x, max_y = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            if is_content(pixels[x, y], bg):
                found = True
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if not found:
        return 0, 0, w, h
    return min_x, min_y, max_x + 1, max_y + 1


def fit_centered(
    canvas: Image.Image,
    content: Image.Image,
    margin_ratio: float,
    y_bias: float = 0.0,
) -> None:
    cw, ch = canvas.size
    margin = int(min(cw, ch) * margin_ratio)
    avail_w, avail_h = cw - 2 * margin, ch - 2 * margin
    scale = min(avail_w / content.width, avail_h / content.height)
    tw, th = int(content.width * scale), int(content.height * scale)
    resized = content.resize((tw, th), Image.Resampling.LANCZOS)
    x = (cw - tw) // 2
    y = (ch - th) // 2 + int(ch * y_bias)
    canvas.paste(resized, (x, y), resized)


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    size = max(im.width, im.height)
    if im.width != im.height:
        sq = Image.new("RGBA", (size, size), BG)
        sq.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
        im = sq

    cropped = im.crop(content_bbox(im, BG))

    canvas_size = OUT_SIZE
    launcher = Image.new("RGBA", (canvas_size, canvas_size), BG)
    fit_centered(launcher, cropped, margin_ratio=MARGIN_LAUNCHER, y_bias=0.01)
    launcher.save(OUT, format="PNG", optimize=True)

    adaptive = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    fit_centered(adaptive, cropped, margin_ratio=MARGIN_ADAPTIVE, y_bias=0.01)
    adaptive.save(OUT_ADAPTIVE, format="PNG", optimize=True)
    print(
        f"OK {OUT_SIZE}px · launcher margin {MARGIN_LAUNCHER:.0%} · "
        f"adaptive margin {MARGIN_ADAPTIVE:.0%}"
    )


if __name__ == "__main__":
    main()
