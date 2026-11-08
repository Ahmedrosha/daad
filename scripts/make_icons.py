#!/usr/bin/env python3
"""Draws app icon concepts (1024x1024) with Arabic Google Fonts. usage: make_icons.py FONTS_DIR OUT_DIR"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

fonts_dir, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
S = 1024


def font(name, size):
    path = os.path.join(fonts_dir, name)
    try:
        return ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)
    except Exception:
        return ImageFont.truetype(path, size)


def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def centered(d, text, f, fill, dy=0, box=(0, 0, S, S)):
    l, t, r, b = d.textbbox((0, 0), text, font=f, direction="rtl")
    w, h = r - l, b - t
    x = box[0] + (box[2] - box[0] - w) / 2 - l
    y = box[1] + (box[3] - box[1] - h) / 2 - t + dy
    d.text((x, y), text, font=f, fill=fill, direction="rtl")


def keys(d, y, color, n=5, w=120, h=96, gap=34):
    total = n * w + (n - 1) * gap
    x0 = (S - total) / 2
    for i in range(n):
        x = x0 + i * (w + gap)
        d.rounded_rectangle([x, y, x + w, y + h], radius=22, fill=color)


# A: teal gradient, Kufi letter, row of keys
img = gradient((13, 120, 110), (6, 64, 70)).convert("RGBA")
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
keys(d, 790, (255, 255, 255, 60))
centered(d, "ض", font("ReemKufi.ttf", 640), (255, 255, 255, 255), dy=-90)
Image.alpha_composite(img, layer).convert("RGB").save(f"{out}/concept-a.png")

# B: midnight navy, golden Ruqaa calligraphy
img = gradient((18, 28, 58), (8, 12, 30))
d = ImageDraw.Draw(img)
centered(d, "ض", font("ArefRuqaa.ttf", 760), (245, 192, 74), dy=-40)
img.save(f"{out}/concept-b.png")

# C: keycap on light background
img = Image.new("RGB", (S, S), (240, 242, 245))
d = ImageDraw.Draw(img)
d.rounded_rectangle([170, 200, 854, 884], radius=120, fill=(160, 166, 176))
d.rounded_rectangle([170, 170, 854, 850], radius=120, fill=(34, 38, 46))
centered(d, "ض", font("Lalezar.ttf", 560), (255, 255, 255), box=(170, 170, 854, 850), dy=-10)
img.save(f"{out}/concept-c.png")

# D: blue-purple gradient, the word ضاد with a typing cursor
img = gradient((59, 91, 219), (124, 58, 237))
d = ImageDraw.Draw(img)
centered(d, "ضاد", font("Cairo.ttf", 400), (255, 255, 255), dy=-30)
d.rounded_rectangle([170, 330, 196, 690], radius=13, fill=(255, 255, 255))
img.save(f"{out}/concept-d.png")

# Side-by-side sheet for choosing
sheet = Image.new("RGB", (2 * S + 60, 2 * S + 60), (255, 255, 255))
for i, name in enumerate("abcd"):
    tile = Image.open(f"{out}/concept-{name}.png")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S, S], radius=230, fill=255)
    sheet.paste(tile, (20 + (i % 2) * (S + 20), 20 + (i // 2) * (S + 20)), mask)
sheet.resize((1068, 1068)).save(f"{out}/concepts-sheet.png")
print("done")
