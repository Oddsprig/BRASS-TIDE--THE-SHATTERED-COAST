"""CPU replay of test_art042.gd's actual BoatArt/BoatPortrait drawing calls.

Uses the imported PNG source atlases and recorded source/destination transforms.
This is evidence for art review, not a GPU capture or a frame-rate measurement.
"""
import argparse
import json
from pathlib import Path
from time import monotonic

from PIL import Image, ImageDraw, ImageFont


def rgba(values):
    return tuple(round(max(0.0, min(1.0, float(v))) * 255) for v in values)


def source_image(resource, game, cache):
    if not resource.startswith("res://"):
        raise ValueError(f"Expected an actual project texture: {resource}")
    path = (game / resource[6:]).resolve()
    if not path.is_relative_to(game):
        raise ValueError(f"Texture escapes game folder: {resource}")
    if path not in cache:
        with Image.open(path) as image:
            cache[path] = image.convert("RGBA")
    return cache[path]


def texture_layer(size, primitive, game, cache):
    atlas = source_image(primitive["path"], game, cache)
    sx, sy, sw, sh = primitive["src"]
    # Atlas entries use integer texel regions; do not invent a replacement hull.
    region = atlas.crop((round(sx), round(sy), round(sx + sw), round(sy + sh)))
    if primitive.get("transpose", False):
        region = region.transpose(Image.Transpose.TRANSPOSE)
    tint = rgba(primitive["c"])
    if tint != (255, 255, 255, 255):
        region = Image.merge("RGBA", tuple(channel.point(lambda value, factor=factor: round(value * factor / 255))
                             for channel, factor in zip(region.split(), tint)))
    p0, p1, _, p3 = primitive["pts"]
    # Invert the recorded destination basis to map output pixels to atlas texels.
    ax, ay = p1[0] - p0[0], p1[1] - p0[1]
    bx, by = p3[0] - p0[0], p3[1] - p0[1]
    determinant = ax * by - ay * bx
    if abs(determinant) < 1e-9:
        raise ValueError("Degenerate recorded texture transform")
    rw, rh = region.size
    coefficients = (rw * by / determinant, -rw * bx / determinant,
                    rw * (-by * p0[0] + bx * p0[1]) / determinant,
                    -rh * ay / determinant, rh * ax / determinant,
                    rh * (ay * p0[0] - ax * p0[1]) / determinant)
    return region.transform(size, Image.Transform.AFFINE, coefficients,
                            resample=Image.Resampling.BICUBIC)


def check_deadline(deadline):
    if monotonic() >= deadline:
        raise TimeoutError("Art042 CPU replay deadline exceeded; output is incomplete")


def replay(panel, game, cache, deadline):
    size = (int(panel["width"]), int(panel["height"]))
    image = Image.new("RGBA", size, panel["background"])
    for primitive in panel["primitives"]:
        check_deadline(deadline)
        if primitive["t"] == "texture":
            image.alpha_composite(texture_layer(size, primitive, game, cache))
            continue
        layer = Image.new("RGBA", size)
        draw = ImageDraw.Draw(layer)
        color, points = rgba(primitive["c"]), [tuple(p) for p in primitive["pts"]]
        kind = primitive["t"]
        if kind == "poly":
            draw.polygon(points, fill=color)
        elif kind in ("line", "seg"):
            draw.line(points, fill=color, width=max(1, round(primitive.get("w", 1))), joint="curve")
        elif kind == "circle":
            (x, y), radius = points[0], primitive["r"]
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        elif kind == "text":
            font_path = Path("C:/Windows/Fonts/segoeui.ttf")
            font = (ImageFont.truetype(str(font_path), max(1, primitive["font_size"]))
                    if font_path.exists() else ImageFont.load_default())
            # Only labels use a host font; boat textures/geometry are exact calls.
            draw.text(points[0], primitive["text"], fill=color, font=font, anchor="ls")
        else:
            raise ValueError(f"Unrecognised recorded drawing call: {kind}")
        image.alpha_composite(layer)
    return image.convert("RGB")


def main():
    started = monotonic()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--game", type=Path, default=Path(__file__).resolve().parents[1] / "game")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=30.0)
    args = parser.parse_args()
    if not 0 < args.seconds <= 90:
        parser.error("--seconds must be greater than zero and at most90")
    deadline = started + args.seconds
    data = json.loads(args.capture.read_text(encoding="utf-8"))
    if data.get("schema") != "brass-tide-art042-trace-v1":
        raise ValueError("Use a capture from the focused test_art042.gd fixture")
    args.game = args.game.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    cache = {}
    panels = data["panels"]
    rendered = []
    for panel in panels:
        check_deadline(deadline)
        image = replay(panel, args.game, cache, deadline)
        image.save(args.out / f'{panel["id"]}.png')
        rendered.append(image)
    # Stack the normal-scale panels without magnifying the small battle boats.
    width = max(panel["width"] for panel in panels)
    height = sum(panel["height"] + 28 for panel in panels) + 42
    sheet = Image.new("RGB", (width, height), "#0b242f")
    draw = ImageDraw.Draw(sheet)
    failed = int(data.get("failures", 0))
    complete = bool(data.get("complete", True))
    draw.text((10, 10), f"Actual drawing-call replay | fixture failures: {failed} | complete: {complete} | CPU preview", fill="#dfbd7d")
    y = 42
    for panel, image in zip(panels, rendered):
        check_deadline(deadline)
        draw.text((10, y), panel["title"], fill="#d5dfce")
        sheet.paste(image, (0, y + 22))
        y += panel["height"] + 28
    sheet.save(args.out / "art042-review.png")
    check_deadline(deadline)
    print(f"Replayed {len(panels)} native panels from {len(cache)} real textures; fixture failures={failed}")
    return 1 if failed or not complete else 0


if __name__ == "__main__":
    raise SystemExit(main())
