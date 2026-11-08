#!/usr/bin/env python3
"""App Store screenshots (1320x2868) from keyboard crops. usage: make_screenshots.py FONTS_DIR RAW_DIR OUT_DIR"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

fonts_dir, raw, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
W, H = 1320, 2868
TOP = tuple(int(os.environ.get("BG_TOP", "383d48")[i:i + 2], 16) for i in (0, 2, 4))
ACCENT = tuple(int(os.environ.get("ACCENT", "20b296")[i:i + 2], 16) for i in (0, 2, 4))
BOTTOM = tuple(int(os.environ.get("BG_BOTTOM", "181b21")[i:i + 2], 16) for i in (0, 2, 4))


def font(size, weight=800):
    f = ImageFont.truetype(os.path.join(fonts_dir, "Cairo.ttf"), size, layout_engine=ImageFont.Layout.RAQM)
    try:
        f.set_variation_by_axes([weight if a.get("name") in (b"Weight", "Weight") else a["default"] for a in f.get_variation_axes()])
    except Exception:
        pass
    return f


def fitted(d, text, size, max_width, weight=800):
    """Largest font up to `size` that fits in max_width."""
    while size > 40:
        f = font(size, weight)
        l, t, r, b = d.textbbox((0, 0), text, font=f, direction="rtl")
        if r - l <= max_width:
            return f
        size -= 4
    return font(size, weight)


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
    ("franco", "اكتب فرانكو.. يطلع عربي", "تكتب 3aml يقترح عامل", "FRANCO"),
    ("arabic", "صف أرقام وترتيب الآيفون", "عربي من اليمين للشمال زي ما اتعودت", None),
    ("tools", "كل الأدوات في مكان واحد", "ترجمة • حاسبة • GIF • جهات اتصال • حافظة", None),
    ("english", "عربي و English في كيبورد واحد", "ضغطة مطوّلة على المسافة تبدّل اللغة", "Hello!  •  أهلاً"),
    ("settings", "ظبطه على مزاجك", "ثيمات • خطوط • أحجام • يد واحدة", None),
]

for i, (name, title, subtitle, bubble) in enumerate(slides, 1):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[k] + (BOTTOM[k] - TOP[k]) * t) for k in range(3)))
    # Large faint ض watermark fills the middle.
    mark = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    md = ImageDraw.Draw(mark)
    text_center(md, 760, "ض", font(900, 700), (255, 255, 255, 22))
    img = Image.alpha_composite(img.convert("RGBA"), mark).convert("RGB")
    d = ImageDraw.Draw(img)
    y = 300
    y += text_center(d, y, title, fitted(d, title, 112, 1180), (255, 255, 255)) + 34
    d.rounded_rectangle([W / 2 - 70, y, W / 2 + 70, y + 14], radius=7, fill=ACCENT)
    y += 14 + 44
    text_center(d, y, subtitle, fitted(d, subtitle, 60, 1200, 500), (205, 210, 218))

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
            bf = font(92, 700)
            ink = (20, 40, 45)
            if bubble == "FRANCO":
                # "3aml  →  عامل" drawn in parts so the arrow always shows.
                left = d.textbbox((0, 0), "3aml", font=bf)
                right = d.textbbox((0, 0), "عامل", font=bf, direction="rtl")
                arrow = 130
                bw = (left[2] - left[0]) + (right[2] - right[0]) + arrow + 160
                bh = max(left[3] - left[1], right[3] - right[1]) + 100
                bx, by = (W - bw) // 2, H - shot.size[1] - bh - 300
                d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=56, fill=(255, 255, 255))
                x = bx + 80
                d.text((x - left[0], by + 50 - left[1]), "3aml", font=bf, fill=(120, 130, 135))
                x += left[2] - left[0] + 25
                cy = by + bh // 2
                d.line([(x, cy), (x + arrow - 50, cy)], fill=ACCENT, width=12)
                d.polygon([(x + arrow - 50, cy - 26), (x + arrow - 10, cy), (x + arrow - 50, cy + 26)], fill=ACCENT)
                x += arrow + 25
                d.text((x - right[0], by + 50 - right[1]), "عامل", font=bf, fill=ink, direction="rtl")
            else:
                l, t, r, b = d.textbbox((0, 0), bubble, font=bf, direction="rtl")
                bw, bh = r - l + 160, b - t + 100
                bx, by = (W - bw) // 2, H - shot.size[1] - bh - 300
                d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=56, fill=(255, 255, 255))
                d.text((bx + 80 - l, by + 50 - t), bubble, font=bf, fill=ink, direction="rtl")
    img.save(os.path.join(out, f"{i:02d}-{name}.png"))
print("done")
