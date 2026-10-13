#!/usr/bin/env python3
"""Game Center artwork for Nine: five achievements and the points leaderboard.

    python3 scripts/gamecenter_art.py            # → fastlane/gamecenter/*.png
    python3 scripts/gamecenter_art.py --preview  # also writes a contact sheet

App Store Connect wants 1024x1024 RGB (PNG or JPEG, >= 72 ppi) for both kinds.
Game Center shows achievements cropped to a circle, so every motif stays inside
the centred safe circle and the corners are plain background — no alpha.

Dark-first, like the app: Nine's void, given digits in cream, one accent per
image from `AccentChoice` in Sources/App/Theme.swift. Where an image names a
band it wears that band's colour (Steady teal, Sharp glacier).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = 1024
C = W // 2
SAFE = 360  # half-width of the square the motif may occupy inside the circle

VOID, LIFT = (14, 15, 18), (34, 36, 42)
CELL, LINE, LINE_HI = (22, 23, 27), (58, 60, 68), (88, 91, 102)
CREAM = (236, 228, 212)


def rgb(r, g, b):
    return (round(r * 255), round(g * 255), round(b * 255))


# AccentChoice.color, Sources/App/Theme.swift
GLACIER = rgb(0.33, 0.68, 0.98)
EMBER = rgb(1.00, 0.56, 0.20)
MEADOW = rgb(0.36, 0.84, 0.48)
LILAC = rgb(0.66, 0.50, 0.98)
GOLD = rgb(0.98, 0.75, 0.18)
TEAL = rgb(0.15, 0.80, 0.76)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "fastlane", "gamecenter")


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def font(px):
    for path in ("/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            pass
    return ImageFont.load_default()


def base():
    im = Image.new("RGB", (W, W), VOID)
    glow = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow).ellipse((112, 112, 912, 912), fill=255)
    im.paste(Image.new("RGB", (W, W), LIFT), mask=glow.filter(ImageFilter.GaussianBlur(160)))
    return im


def halo(im, box, color, radius, blur=40, strength=200, pad=30):
    m = Image.new("L", (W, W), 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(m).rounded_rectangle((x0 - pad, y0 - pad, x1 + pad, y1 + pad),
                                        radius + pad, fill=strength)
    im.paste(Image.new("RGB", (W, W), color), mask=m.filter(ImageFilter.GaussianBlur(blur)))


def lit_cell(im, box, color, radius, width=8, digit=None, digit_px=None):
    halo(im, box, color, radius)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(box, radius, fill=mix(CELL, color, 0.22), outline=color, width=width)
    if digit:
        x0, y0, x1, y1 = box
        d.text(((x0 + x1) / 2, (y0 + y1) / 2 + 4), digit, font=font(digit_px), fill=CREAM, anchor="mm")


def grid_boxes(n, span, gap, cx=C, cy=C):
    side = (span - gap * (n - 1)) / n
    x0, y0 = cx - span / 2, cy - span / 2
    return [[(x0 + c * (side + gap), y0 + r * (side + gap),
              x0 + c * (side + gap) + side, y0 + r * (side + gap) + side)
             for c in range(n)] for r in range(n)]


def sudoku_boxes(span, cell_gap=5, box_gap=16):
    """9x9 cell rects with wider gutters between the 3x3 boxes."""
    side = (span - cell_gap * 6 - box_gap * 2) / 9
    pos = []
    p = C - span / 2
    for i in range(9):
        pos.append(p)
        p += side + (box_gap if i in (2, 5) else cell_gap)
    return [[(pos[c], pos[r], pos[c] + side, pos[r] + side) for c in range(9)] for r in range(9)], side


# ------------------------------------------------------------------ images

def first_light():
    """First Light — solve your first board: one box, its first digit lit."""
    im = base()
    d = ImageDraw.Draw(im)
    boxes = grid_boxes(3, 532, 14)
    for row in boxes:
        for b in row:
            d.rounded_rectangle(b, 28, fill=CELL, outline=LINE, width=3)
    lit_cell(im, boxes[1][1], GOLD, 28, digit="1", digit_px=120)
    return im


def ten_deep():
    """Ten Deep — ten boards solved: ten finished boxes stacked 4-3-2-1."""
    im = base()
    rows, size, gap = [4, 3, 2, 1], 150, 26
    top = C - (len(rows) * size + (len(rows) - 1) * gap) / 2 + 30
    for i, count in enumerate(reversed(rows)):  # 1 on top, 4 at the base
        y = top + i * (size + gap)
        width = count * size + (count - 1) * gap
        for k in range(count):
            x = C - width / 2 + k * (size + gap)
            box = (x, y, x + size, y + size)
            halo(im, box, TEAL, 22, blur=26, strength=110, pad=10)
            d = ImageDraw.Draw(im)
            d.rounded_rectangle(box, 22, fill=mix(CELL, TEAL, 0.16), outline=TEAL, width=5)
            for row in grid_boxes(3, size - 44, 7, cx=x + size / 2, cy=y + size / 2):
                for b in row:
                    d.rounded_rectangle(b, 6, fill=mix(CELL, TEAL, 0.55))
    return im


def fifty_deep():
    """Fifty Deep — fifty boards solved: a whole board lighting up in a sweep."""
    im = base()
    cells, side = sudoku_boxes(600)
    d = ImageDraw.Draw(im)
    halo(im, (C - 300, C - 300, C + 300, C + 300), MEADOW, 40, blur=90, strength=70, pad=20)
    d = ImageDraw.Draw(im)
    for r in range(9):
        for c in range(9):
            t = (r + c) / 16  # the sweep runs corner to corner
            d.rounded_rectangle(cells[r][c], 9, fill=mix(mix(CELL, MEADOW, 0.18), MEADOW, 1 - t * 0.8),
                                outline=mix(LINE, MEADOW, 0.6), width=2)
    return im


def sharpened():
    """Sharpened — solve a Sharp board: the X-wing, Sharp's signature pattern."""
    im = base()
    cells, side = sudoku_boxes(600)
    d = ImageDraw.Draw(im)
    for row in cells:
        for b in row:
            d.rounded_rectangle(b, 9, fill=CELL, outline=LINE, width=2)
    corners = [(1, 1), (1, 7), (6, 1), (6, 7)]
    centre = lambda rc: ((cells[rc[0]][rc[1]][0] + cells[rc[0]][rc[1]][2]) / 2,
                         (cells[rc[0]][rc[1]][1] + cells[rc[0]][rc[1]][3]) / 2)
    beams = Image.new("L", (W, W), 0)
    bd = ImageDraw.Draw(beams)
    for a, b in [(0, 3), (1, 2)]:  # the X
        bd.line([centre(corners[a]), centre(corners[b])], fill=255, width=14)
    im.paste(Image.new("RGB", (W, W), GLACIER), mask=beams.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(im)
    for a, b in [(0, 3), (1, 2)]:
        d.line([centre(corners[a]), centre(corners[b])], fill=mix(GLACIER, CREAM, 0.3), width=5)
    for rc in corners:
        lit_cell(im, cells[rc[0]][rc[1]], GLACIER, 12, width=5, digit="7", digit_px=40)
    return im


def swift_nine():
    """Swift Nine — under five minutes: a lit cell leaving a trail."""
    im = base()
    size = 210
    x1 = C + 200
    box = (x1 - size, C - size / 2, x1, C + size / 2)
    trail = Image.new("L", (W, W), 0)
    td = ImageDraw.Draw(trail)
    for i, (dy, length, alpha) in enumerate([(-64, 250, 150), (0, 320, 210), (64, 220, 150)]):
        y = C + dy
        x_end = box[0] - 18
        td.rounded_rectangle((x_end - length, y - 13, x_end, y + 13), 13, fill=alpha)
    # fade toward the left: full strength at the cell, gone by the circle's edge
    fade = Image.new("L", (W, W), 0)
    fd = ImageDraw.Draw(fade)
    for x in range(W):
        fd.line([(x, 0), (x, W)], fill=max(0, min(255, round(255 * (x - 170) / (box[0] - 170)))))
    trail = Image.composite(trail, Image.new("L", (W, W), 0), fade)
    im.paste(Image.new("RGB", (W, W), EMBER), mask=trail.filter(ImageFilter.GaussianBlur(3)))
    lit_cell(im, box, EMBER, 40, width=10, digit="9", digit_px=150)
    return im


def total_points():
    """Total Points — the leaderboard: columns of cells climbing left to right."""
    im = base()
    heights, size, gap = [1, 2, 3, 4, 5], 80, 16
    width = len(heights) * size + (len(heights) - 1) * gap
    floor = C + (5 * size + 4 * gap) / 2
    for i, h in enumerate(heights):
        x = C - width / 2 + i * (size + gap)
        for k in range(h):
            y1 = floor - k * (size + gap)
            box = (x, y1 - size, x + size, y1)
            top = k == h - 1
            if top:
                lit_cell(im, box, LILAC, 18, width=6)
            else:
                ImageDraw.Draw(im).rounded_rectangle(box, 18, fill=mix(CELL, LILAC, 0.30),
                                                     outline=mix(LINE, LILAC, 0.5), width=3)
    return im


ART = {
    "achievement-solve-first": first_light,
    "achievement-solve-ten": ten_deep,
    "achievement-solve-fifty": fifty_deep,
    "achievement-sharp-first": sharpened,
    "achievement-swift": swift_nine,
    "leaderboard-points": total_points,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name, draw in ART.items():
        im = draw()
        path = os.path.join(OUT, name + ".png")
        im.save(path, dpi=(72, 72))
        made.append((name, im))
        print(path)
    if "--preview" in sys.argv:
        tile = 400
        sheet = Image.new("RGB", (len(made) * (tile + 20) - 20, tile * 2 + 20), (255, 255, 255))
        mask = Image.new("L", (tile, tile), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, tile, tile), fill=255)
        for i, (_, im) in enumerate(made):
            small = im.resize((tile, tile), Image.LANCZOS)
            sheet.paste(small, (i * (tile + 20), 0))
            sheet.paste(small, (i * (tile + 20), tile + 20), mask)
        path = os.path.join(OUT, "preview-sheet.png")
        sheet.save(path)
        print(path)


if __name__ == "__main__":
    main()
