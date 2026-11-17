#!/usr/bin/env python3
"""Adds a caption and background to each raw App Store screenshot.
NN-name-phone.png, if present, is shown as an iPhone in front of NN-name.png.

Usage: python3 AppStore/frame_screenshots.py
Reads AppStore/screenshots/raw/NN-name.png (2752x2064), writes AppStore/screenshots/framed/.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "screenshots", "raw")
OUT = os.path.join(HERE, "screenshots", "framed")
W, H = 2752, 2064

CAPTIONS = {
    "01-home": ("Your kitchen, at a glance", "Recipes, timers and scenes on one screen"),
    "02-import": ("Import recipes from anywhere", "Paste a link, scan a cookbook or add screenshots"),
    "03-send": ("Send it from your phone", "Over Wi-Fi, from any browser. No app needed"),
    "04-recipe": ("Any recipe, beautifully tidy", "Just the ingredients and method. No life story"),
    "05-cook": ("Cook step by step", "Big text you can read from across the room"),
    "06-units": ("Cups or grams? °F or °C?", "Switch any recipe to the units you use"),
    "07-timers": ("Timers you won't miss", "Run several at once, with a loud alarm"),
    "08-shopping": ("Never forget the lemons", "Send what you're missing to the shopping list"),
}

TOP = (252, 236, 222)      # warm cream
BOTTOM = (240, 180, 140)   # soft orange, close to the app's accent
INK = (60, 32, 20)


def font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size, index=index)
    except OSError:
        return ImageFont.load_default()


TITLE = font("/System/Library/Fonts/NewYork.ttf", 120)
SUB = font("/System/Library/Fonts/SFNS.ttf", 60)
for f, weight in ((TITLE, b"Bold"), (SUB, b"Medium")):
    try:
        f.set_variation_by_name(weight)  # variable fonts default to their thinnest style
    except Exception:
        pass


def background():
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return bg


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def add_phone(canvas, phone, ipad_box):
    """Places an iPhone screenshot in front of the iPad's lower-right corner."""
    x0, y0, x1, y1 = ipad_box
    ph_h = 1500
    ph_w = int(phone.width * ph_h / phone.height)
    screen = rounded(phone.resize((ph_w, ph_h), Image.LANCZOS), 70)
    bez = 22
    px, py = x1 - ph_w + 60, y1 - ph_h + 40
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px - bez, py - bez + 30, px + ph_w + bez, py + ph_h + bez + 30], 92, fill=(60, 25, 5, 140))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(36)))
    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([px - bez, py - bez, px + ph_w + bez, py + ph_h + bez], 92, fill=(28, 28, 30, 255))
    canvas = Image.alpha_composite(canvas, body)
    canvas.alpha_composite(screen, (px, py))
    return canvas


def frame(name, shot, phone=None):
    title, sub = CAPTIONS.get(name, (name, ""))
    canvas = background().convert("RGBA")
    d = ImageDraw.Draw(canvas)

    d.text((W / 2, 150), title, font=TITLE, fill=INK, anchor="mm")
    d.text((W / 2, 285), sub, font=SUB, fill=INK + (190,), anchor="mm")

    shot_w = 2100  # 1575 tall: fits between the caption and the bottom edge
    shot_h = int(shot.height * shot_w / shot.width)
    s = rounded(shot.resize((shot_w, shot_h), Image.LANCZOS), 44)
    x, y = (W - shot_w) // 2, 400

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 24, x + shot_w, y + shot_h + 24], 44, fill=(90, 40, 10, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    # Thin dark bezel so the screen reads as a device.
    bezel = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle([x - 14, y - 14, x + shot_w + 14, y + shot_h + 14], 56, fill=(28, 28, 30, 255))
    canvas = Image.alpha_composite(canvas, bezel)
    canvas.alpha_composite(s, (x, y))
    if phone is not None:
        canvas = add_phone(canvas, phone, (x, y, x + shot_w, y + shot_h))
    return canvas.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in sorted(os.listdir(RAW)):
        if not f.endswith(".png") or f.endswith("-phone.png"):
            continue
        shot = Image.open(os.path.join(RAW, f)).convert("RGB")
        if shot.size != (W, H):
            print(f"warning: {f} is {shot.size}, expected {(W, H)}")
        name = os.path.splitext(f)[0]
        phone_path = os.path.join(RAW, name + "-phone.png")
        phone = Image.open(phone_path).convert("RGB") if os.path.exists(phone_path) else None
        out = frame(name, shot, phone)
        out.save(os.path.join(OUT, f), optimize=True)
        print("framed", f)


if __name__ == "__main__":
    main()
