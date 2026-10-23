#!/usr/bin/env python3
"""Build Vision Pro's app icon from the Icon Composer document.

visionOS cannot read `Nine.icon`: actool, handed the document with
`--platform xros`, succeeds and emits no icon at all. The platform wants a
`.solidimagestack` instead — three 1024x1024 layers the system parallaxes and
lights itself (Back opaque, Middle and Front transparent).

The layers are *derived*, never drawn: `Nine.icon` stays the one source of
truth, and this script maps its three groups onto the three visionOS layers —

    Field (dots) + document fill  ->  Back
    Board (ring)                  ->  Middle
    Spark (center)                ->  Front

The Middle and Front layers take the document's **watchOS** position
specialisations, not its default ones. visionOS masks the icon to a circle, as
the watch does, and the default scales were set for a squircle: at those, the
ring's corner cells fall outside the circle and are cut off.

Each Icon Composer image is a white mask tinted by its layer's fill, so a
layer here is that mask's alpha times the fill colour. Re-run after editing
`Nine.icon`:

    python3 nine/scripts/vision-icon.py
"""
import json
import pathlib

from PIL import Image

NINE = pathlib.Path(__file__).resolve().parent.parent
ICON = NINE / "Nine.icon"
STACK = NINE / "VisionAssets.xcassets" / "Nine.solidimagestack"
SIDE = 1024


def srgb(spec):
    """`srgb:r,g,b,a` -> an 8-bit RGBA tuple."""
    channels = [float(v) for v in spec.split(":", 1)[1].split(",")]
    return tuple(round(c * 255) for c in channels)


def default(specialisations):
    """The un-specialised (light, any-idiom) value of a specialisation list."""
    return next(s["value"] for s in specialisations
                if "appearance" not in s and "idiom" not in s)


def tinted(layer, scale=1.0):
    """A layer's mask, coloured with its fill and scaled about the centre."""
    fill = layer.get("fill") or default(layer["fill-specializations"])
    colour = srgb(fill["solid"])
    mask = Image.open(ICON / "Assets" / layer["image-name"]).convert("RGBA")
    alpha = mask.getchannel("A")
    opacity = layer.get("opacity", 1.0)
    alpha = alpha.point(lambda a: round(a * opacity * colour[3] / 255))
    out = Image.new("RGBA", mask.size, colour[:3] + (0,))
    out.putalpha(alpha)
    if scale != 1.0:
        side = round(SIDE * scale)
        scaled = out.resize((side, side), Image.LANCZOS)
        margin = (side - SIDE) // 2
        if margin >= 0:
            out = scaled.crop((margin, margin, margin + SIDE, margin + SIDE))
        else:
            out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
            out.alpha_composite(scaled, (-margin, -margin))
    return out


def gradient(fill):
    """The document's top-to-bottom linear fill, opaque."""
    top, bottom = (srgb(c) for c in fill["linear-gradient"])
    column = Image.new("RGBA", (1, SIDE))
    for y in range(SIDE):
        t = y / (SIDE - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((SIDE, SIDE))


def round_mask_scale(group):
    """The scale a group takes under a circular mask — its watchOS one."""
    for spec in group.get("position-specializations", []):
        if spec.get("idiom") == "watchOS":
            return spec["value"].get("scale", 1.0)
    return default(group["position-specializations"]).get("scale", 1.0) \
        if "position-specializations" in group else 1.0


def group(doc, name):
    return next(g for g in doc["groups"] if g["name"] == name)


def write_layer(name, image):
    layer = STACK / f"{name}.solidimagestacklayer"
    content = layer / "Content.imageset"
    content.mkdir(parents=True, exist_ok=True)
    image.save(content / f"{name.lower()}.png")
    (content / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name.lower()}.png", "idiom": "vision", "scale": "2x"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    (layer / "Contents.json").write_text(json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def main():
    doc = json.loads((ICON / "icon.json").read_text())

    back = gradient(default(doc["fill-specializations"]))
    back.alpha_composite(tinted(group(doc, "Field")["layers"][0]))
    write_layer("Back", back.convert("RGB").convert("RGBA"))

    board = group(doc, "Board")
    write_layer("Middle", tinted(board["layers"][0], scale=round_mask_scale(board)))

    spark = group(doc, "Spark")
    write_layer("Front", tinted(spark["layers"][0], scale=round_mask_scale(spark)))

    (STACK / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "layers": [{"filename": f"{n}.solidimagestacklayer"} for n in ("Front", "Middle", "Back")],
    }, indent=2) + "\n")
    (STACK.parent / "Contents.json").write_text(json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


if __name__ == "__main__":
    main()
