#!/usr/bin/env python3
"""Generates frickoss's brand assets: the app icon, the README header and badges.

    python3 scripts/make_brand.py [--version 1.0.0]

Outputs
    AppIcon.icns                   app icon (all macOS sizes)
    docs/AppIcon-1024.png          app icon source
    docs/readme-header.png         2560x760 README header
    docs/badge-release.svg         RELEASE  | V1.0.0
    docs/badge-download.svg        DOWNLOAD | MACOS APP
    docs/badge-platform.svg        PLATFORM | MACOS 13+ · APPLE SILICON

Layout and badge format follow the other dustalexw apps (Cover Flow, Data Curator, Banana Split Redux,
Plexamp Download Copier); colours are this app's own: graphite, a "record light" coral and a sky-blue waveform.
Needs Pillow and the Inter / Inter Display fonts.
"""
import argparse
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIRS = ["/usr/share/fonts/opentype/inter", os.path.expanduser("~/Library/Fonts"), "/Library/Fonts"]

INK_TOP = (32, 36, 46)       # #20242E
INK_BOT = (11, 13, 18)       # #0B0D12
CORAL = (255, 90, 78)        # #FF5A4E  the app's accent: a recording light
CORAL_DEEP = (214, 58, 64)   # #D63A40
SKY = (92, 200, 255)         # #5CC8FF  the waveform
CREAM = (245, 241, 234)      # #F5F1EA
SLATE = (150, 160, 176)      # #96A0B0
LABEL = "#20222c"            # badge label background, shared with the other apps


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    raise SystemExit(f"Font not found: {name}")


def vgrad(w, h, top, bot):
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)))
    return g.resize((w, h))


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def disc(img, cx, cy, r):
    """A compact disc: silver with a soft rainbow sheen, a clear hub and a dark spindle hole."""
    W, H = img.size
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = lambda rr: [cx - rr, cy - rr, cx + rr, cy + rr]
    d.ellipse(box(r), fill=(196, 204, 216, 255))
    # rainbow sheen sweeping round the disc
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    hues = [(255, 120, 150), (255, 200, 110), (140, 240, 170), (110, 190, 255), (190, 140, 255)]
    for k, start in enumerate(range(-40, 320, 12)):
        col = hues[k % len(hues)]
        sd.pieslice(box(r), start, start + 12, fill=col + (70 if (k // 5) % 2 == 0 else 30,))
    sheen = sheen.filter(ImageFilter.GaussianBlur(max(1, r * 0.06)))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse(box(r), fill=255)
    layer.alpha_composite(Image.composite(sheen, Image.new("RGBA", (W, H), (0, 0, 0, 0)), mask))
    # bright highlight band
    hl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(hl).pieslice(box(r * 0.98), 200, 235, fill=(255, 255, 255, 120))
    hl = hl.filter(ImageFilter.GaussianBlur(max(1, r * 0.05)))
    layer.alpha_composite(Image.composite(hl, Image.new("RGBA", (W, H), (0, 0, 0, 0)), mask))
    d = ImageDraw.Draw(layer)
    for i in range(6):
        rr = r * (0.92 - i * 0.07)
        d.ellipse(box(rr), outline=(255, 255, 255, 26), width=max(1, int(r * 0.006)))
    d.ellipse(box(r), outline=(255, 255, 255, 90), width=max(1, int(r * 0.014)))
    d.ellipse(box(r * 0.30), fill=(228, 233, 240, 255))
    d.ellipse(box(r * 0.30), outline=(150, 160, 176, 255), width=max(1, int(r * 0.012)))
    d.ellipse(box(r * 0.12), fill=INK_BOT + (255,))
    img.alpha_composite(layer)


def waveform(img, x0, x1, cy, amp, n, gap_color=INK_BOT, outline=0.0):
    """Rounded bars, coral → sky from left to right, with a sine envelope."""
    d = ImageDraw.Draw(img)
    step = (x1 - x0) / n
    bw = step * 0.62
    heights = []
    for i in range(n):
        t = i / (n - 1)
        env = 0.35 + 0.65 * math.sin(math.pi * (0.15 + 0.85 * t)) ** 0.8
        wob = 0.55 + 0.45 * abs(math.sin(i * 1.7 + 0.6))
        heights.append(max(0.12, env * wob))
    for i, hgt in enumerate(heights):
        x = x0 + i * step + (step - bw) / 2
        h = amp * hgt
        col = mix(CORAL, SKY, i / (n - 1))
        if outline:
            o = outline
            d.rounded_rectangle([x - o, cy - h - o, x + bw + o, cy + h + o], radius=(bw + 2 * o) / 2, fill=gap_color)
        d.rounded_rectangle([x, cy - h, x + bw, cy + h], radius=bw / 2, fill=col)


def tile_art(W, edge=True):
    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=int(W * 0.225), fill=255)
    tile.paste(vgrad(W, W, INK_TOP, INK_BOT).convert("RGBA"), (0, 0), mask)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.02, W * 0.10, W * 0.62, W * 0.80], fill=CORAL + (40,))
    gd.ellipse([W * 0.45, W * 0.20, W * 1.05, W * 0.85], fill=SKY + (34,))
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.09))
    tile.alpha_composite(Image.composite(glow, Image.new("RGBA", (W, W), (0, 0, 0, 0)), mask))
    disc(tile, W * 0.38, W * 0.50, W * 0.27)
    # the waveform leaves the disc and carries on to the right
    waveform(tile, W * 0.44, W * 0.87, W * 0.50, W * 0.21, 9, gap_color=(16, 18, 24), outline=W * 0.012)
    if edge:
        ImageDraw.Draw(tile).rounded_rectangle([0, 0, W - 1, W - 1], radius=int(W * 0.225),
                                               outline=(255, 255, 255, 34), width=max(2, W // 200))
    return tile


def icon_tile(size, ss=4):
    return tile_art(size * ss).resize((size, size), Image.LANCZOS)


def app_icon(S=1024, ss=4):
    W = S * ss
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    m = 100 * ss
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([m, m + 14 * ss, W - m, W - m + 14 * ss], radius=185 * ss, fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18 * ss)))
    img.alpha_composite(tile_art(W - 2 * m, edge=False), (m, m))
    return img.resize((S, S), Image.LANCZOS)


def pill(draw, x, y, text, fnt, h, fill, outline, color, dot=None, pad=None):
    pad = pad or h * 0.55
    tw = draw.textlength(text, font=fnt)
    dot_w = h * 0.55 if dot else 0
    w = pad * 2 + tw + dot_w
    draw.rounded_rectangle([x, y, x + w, y + h], radius=h / 2, fill=fill, outline=outline, width=2)
    tx = x + pad
    if dot:
        r = h * 0.14
        cy = y + h / 2
        draw.ellipse([tx, cy - r, tx + 2 * r, cy + r], fill=dot)
        tx += dot_w
    asc, desc = fnt.getmetrics()
    draw.text((tx, y + (h - asc - desc) / 2 + desc * 0.15), text, font=fnt, fill=color)
    return w


def header(path, version, W=2560, H=760):
    img = vgrad(W, H, INK_TOP, INK_BOT).convert("RGBA")
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.15, -H * 0.5, W * 0.62, H * 0.9], fill=CORAL + (16,))
    gd.ellipse([W * 0.55, -H * 0.2, W * 1.05, H * 1.2], fill=SKY + (18,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(160)))
    # right edge: a long waveform fading in from the left
    ss = 2
    deco = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    waveform(deco, 1960 * ss, 2520 * ss, 400 * ss, 250 * ss, 22)
    fade = Image.new("L", (W * ss, 1))
    for x in range(W * ss):
        fade.putpixel((x, 0), int(150 * min(1, max(0, (x - 1940 * ss) / (360 * ss)))))
    deco.putalpha(Image.composite(deco.getchannel("A"), Image.new("L", deco.size, 0), fade.resize(deco.size)))
    img = Image.alpha_composite(img, deco.resize((W, H), Image.LANCZOS))
    # app icon tile
    tile = icon_tile(400)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([110, 200, 510, 600], radius=90, fill=(0, 0, 0, 150))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(28)))
    img.alpha_composite(tile, (110, 180))
    d = ImageDraw.Draw(img)
    x = 620
    d.text((x, 196), "THE FREE AUDIO CONVERTER · A DUSTALEXW APP", font=font("Inter-Bold.otf", 30), fill=SKY)
    title = font("InterDisplay-Bold.otf", 150)
    d.text((x - 6, 240), "frick", font=title, fill=CREAM)
    d.text((x - 6 + d.textlength("frick", font=title), 240), "oss", font=title, fill=CORAL)
    d.text((x, 432), "Every format fre:ac speaks, in a native Mac window.", font=font("Inter-Medium.otf", 46), fill=CREAM)
    d.text((x, 496), "MP3, AAC, FLAC, Opus and more — plus CD ripping, cue sheets and SuperFast.", font=font("Inter-Regular.otf", 34), fill=SLATE)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    chip = font("Inter-Medium.otf", 30)
    cx = x
    for label, dot in (("Powered by fre:ac", CORAL), ("Audio CD ripping", CREAM), ("Live command preview", SKY)):
        cx += pill(ld, cx, 578, label, chip, 62, (255, 255, 255, 10), (255, 255, 255, 38), CREAM, dot=dot) + 22
    small = font("Inter-SemiBold.otf", 28)
    vx = W - 120 - (d.textlength(f"v{version}", font=small) + 56)
    pill(ld, vx, 70, f"v{version}", small, 58, CORAL + (40,), CORAL + (120,), CORAL)
    mw = d.textlength("Only on macOS", font=small) + 56 + 32
    pill(ld, vx - 24 - mw, 70, "Only on macOS", small, 58, (11, 13, 18, 200), (255, 255, 255, 40), CREAM, dot=CREAM)
    img = Image.alpha_composite(img, layer)
    img.convert("RGB").save(path, optimize=True)


def badge(path, label, value, fill, text):
    """Same construction as the other apps' badges: 34px, Arial bold 11, tracked uppercase."""
    label, value = label.upper(), value.upper()
    lw = round(len(label) * 8.2 + 24)
    vw = round(len(value) * 8.2 + 26)
    w = lw + vw
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="34" viewBox="0 0 {w} 34" role="img" aria-label="{label}: {value}">
  <title>{label}: {value}</title>
  <rect width="{lw}" height="34" fill="{LABEL}"/>
  <rect x="{lw}" width="{vw}" height="34" fill="{fill}"/>
  <g font-family="Arial" font-size="11" font-weight="bold" letter-spacing="1.2" text-anchor="middle">
    <text x="{lw / 2:.1f}" y="21" fill="#faf4e4">{label}</text>
    <text x="{lw + vw / 2:.1f}" y="21" fill="{text}">{value}</text>
  </g>
</svg>
'''
    with open(path, "w") as f:
        f.write(svg)


def main():
    ap = argparse.ArgumentParser()
    vf = os.path.join(ROOT, "VERSION")
    ap.add_argument("--version", default=open(vf).read().strip() if os.path.exists(vf) else "1.0.0")
    v = ap.parse_args().version
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    icon = app_icon()
    icon.save(os.path.join(ROOT, "docs/AppIcon-1024.png"))
    icon.save(os.path.join(ROOT, "AppIcon.icns"), sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    header(os.path.join(ROOT, "docs/readme-header.png"), v)
    badge(os.path.join(ROOT, "docs/badge-release.svg"), "Release", f"v{v}", "#ff5a4e", "#20222c")
    badge(os.path.join(ROOT, "docs/badge-download.svg"), "Download", "macOS app", "#f5f1ea", "#20242e")
    badge(os.path.join(ROOT, "docs/badge-platform.svg"), "Platform", "macOS 13+ · Apple silicon", "#5cc8ff", "#20222c")
    print(f"Wrote icon, header and badges for {v}")


if __name__ == "__main__":
    main()
