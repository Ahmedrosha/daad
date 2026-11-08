#!/usr/bin/env python3
"""App Store screenshots (1320x2868) from keyboard crops. usage: make_screenshots.py FONTS_DIR RAW_DIR OUT_DIR"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

fonts_dir, raw, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
W, H = 1320, 2868
TOP = tuple(int(os.environ.get("BG_TOP", "0d786e")[i:i + 2], 16) for i in (0, 2, 4))
BOTTOM = tuple(int(os.environ.get("BG_BOTTOM", "06343a")[i:i + 2], 16) for i in (0, 2, 4))


def font(size, weight=800):
    f = ImageFont.truetype(os.path.join(fonts_dir, "Cairo.ttf"), size, layout_engine=ImageFont.Layout.RAQM)
    try:
        f.set_variation_by_axes([weight if a.get("name") in (b"Weight", "Weight") else a["default"] for a in f.get_variation_axes()])
    except Exception:
        pass
    return f


def text_center(d, y, text, f, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=f, direction="rtl")
    d.text(((W - (r - l)) / 2 - l, y - t), text, font=f, fill=fill, direction="rtl")
    return b - t


def rounded(img, radius, top_only=False):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1] + (radius if top_only else 0)], radius=radius, fill=255)
    img.putalpha(mask)
    return img


slides = [
    ("suggest", "اقتراحات ذكية بالعربي", "بيتعلم كلامك وبيقترح الكلمة الجاية", "السلام عليكم"),
    ("franco", "اكتب فرانكو.. يطلع عربي", "تكتب 3aml يقترح عامل", "3aml  ←  عامل"),
    ("arabic", "صف أرقام وترتيب الآيفون", "عربي من اليمين للشمال زي ما اتعودت", None),
    ("tools", "كل الأدوات في مكان واحد", "ترجمة • حاسبة • GIF • جهات اتصال • حافظة", None),
    ("english", "عربي وEnglish في كيبورد واحد", "ضغطة مطوّلة على المسافة تبدّل اللغة", "Hello!  •  أهلاً"),
    ("settings", "ظبطه على مزاجك", "ثيمات • خطوط • أحجام • يد واحدة", None),
]

for i, (name, title, subtitle, bubble) in enumerate(slides, 1):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[k] + (BOTTOM[k] - TOP[k]) * t) for k in range(3)))
    y = 230
    y += text_center(d, y, title, font(96), (255, 255, 255)) + 60
    text_center(d, y, subtitle, font(52, 500), (215, 235, 232))

    shot = Image.open(os.path.join(raw, f"{name}.png")).convert("RGBA")
    if name == "settings":
        w = 1060
        shot = shot.resize((w, int(shot.size[1] * w / shot.size[0])))
        shot = rounded(shot, 60)
        img.paste(shot, ((W - w) // 2, H - shot.size[1] - 160), shot)
    else:
        shot = rounded(shot, 56, top_only=True)
        img.paste(shot, (0, H - shot.size[1]), shot)
        if bubble:
            bf = font(66, 600)
            l, t, r, b = d.textbbox((0, 0), bubble, font=bf, direction="rtl")
            bw, bh = r - l + 110, b - t + 80
            bx, by = W - bw - 90, H - shot.size[1] - bh - 120
            d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=48, fill=(255, 255, 255))
            d.text((bx + 55 - l, by + 40 - t), bubble, font=bf, fill=(20, 40, 45), direction="rtl")
    img.save(os.path.join(out, f"{i:02d}-{name}.png"))
print("done")
