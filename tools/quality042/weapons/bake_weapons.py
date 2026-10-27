"""Root-only offline weapon bake using SolArt's shared lit 3D rasterizer.

Source only in the SolWeapons seat. Does not start Blender, Godot or a GPU job.
Root still schedules this through Test Bridge; each call has a bounded deadline.
Requires the already installed Python/NumPy/Pillow and merged Art sources.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

SHARED_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SHARED_DIR))
import bake as shared
from models import Model
from weapon_models import VARIANTS, build_weapon
from PIL import Image

CELL = (256, 192)
PIVOT = (128, 128)
DENSITY = 6
HEADINGS = 32
COLUMNS = 8
REVISION = "042-authored-weapons-r2"


def source_hash():
    digest = hashlib.sha256()
    paths = [Path(__file__), Path(__file__).with_name("weapon_models.py"),
             SHARED_DIR/"bake.py", SHARED_DIR/"models.py"]
    for path in paths:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def key(source, variant, layer, heading, aa):
    return hashlib.sha256(f"{source}:{variant}:{layer}:{heading}:{aa}".encode()).hexdigest()[:24]


def paths(args, source, layer, heading):
    folder = args.cache/args.variant/layer
    name = key(source, args.variant, layer, heading, args.aa)
    return folder/(name+".png"), folder/(name+".json")


def configure_projection():
    # Both hulls and weapons use precisely u=.82*(x-y), v=.41*(x+y)-z.
    shared.CELL, shared.PIVOT = CELL, PIVOT
    shared.DENSITY, shared.HEADINGS = DENSITY, HEADINGS


def render_layer(layers, layer, heading, aa, deadline):
    combined = Model("weapon_shadow_occluders", 1.0)
    combined.parts = [part for model in layers.values() for part in model.parts]
    vertices, _, faces, _ = shared.arrays(combined, heading*shared.math.tau/HEADINGS)
    original_shadow = shared.shadow_map
    # Shadows include the complete assembled gun even when recoil layers are
    # rendered separately; the barrel casts onto its own cradle and feed case.
    def assembled_shadow(_vertices, _faces, end, resolution=512):
        return original_shadow(vertices, faces, end, resolution)
    shared.shadow_map = assembled_shadow
    try:
        return shared.render(layers[layer], heading, DENSITY, aa, deadline)
    finally:
        shared.shadow_map = original_shadow


def save_frame(args, source, layers, layer, heading, deadline):
    image_path, receipt_path = paths(args, source, layer, heading)
    if image_path.is_file() and receipt_path.is_file():
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("png_sha256") == hashlib.sha256(image_path.read_bytes()).hexdigest():
            return image_path, receipt
        raise ValueError(f"cached frame changed: {image_path}")
    image_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    image, metadata = render_layer(layers, layer, heading, args.aa, deadline)
    bbox = image.getbbox()
    if not bbox:
        raise ValueError(f"empty weapon layer {args.variant}/{layer}/{heading}")
    metadata.update({"variant":args.variant, "layer":layer, "heading":heading,
                     "source_sha256":source, "revision":REVISION, "aa":args.aa,
                     "cell_px":list(CELL), "pivot_px":list(PIVOT),
                     "pixels_per_world_unit":DENSITY,
                     "bounds_px":[bbox[0], bbox[1], bbox[2]-bbox[0], bbox[3]-bbox[1]],
                     "seconds":round(time.perf_counter()-started, 3)})
    temporary = image_path.with_suffix(".partial.png")
    image.save(temporary, compress_level=3)
    temporary.replace(image_path)
    metadata["png_sha256"] = hashlib.sha256(image_path.read_bytes()).hexdigest()
    receipt_path.write_text(json.dumps(metadata, indent=2)+"\n", encoding="utf-8")
    return image_path, metadata


def pack(args, source, layers, deadline):
    args.out.mkdir(parents=True, exist_ok=True)
    reports = []
    for layer in layers:
        if time.perf_counter() > deadline:
            raise TimeoutError("weapon pack deadline before next layer")
        atlas = Image.new("RGBA", (CELL[0]*COLUMNS, CELL[1]*(HEADINGS//COLUMNS)))
        bounds = []
        frames = []
        for heading in range(HEADINGS):
            path, receipt_path = paths(args, source, layer, heading)
            if not path.is_file() or not receipt_path.is_file():
                raise FileNotFoundError(f"INCOMPLETE atlas: {args.variant}/{layer} heading{heading}")
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if receipt.get("source_sha256") != source or receipt.get("png_sha256") != actual:
                raise ValueError(f"source/frame receipt mismatch: {path}")
            if receipt.get("heading") != heading or receipt.get("layer") != layer:
                raise ValueError(f"wrong cached heading/layer: {path}")
            with Image.open(path) as image:
                if image.size != CELL or image.mode != "RGBA" or not image.getbbox():
                    raise ValueError(f"wrong image contract: {path}")
                atlas.paste(image, ((heading%COLUMNS)*CELL[0], (heading//COLUMNS)*CELL[1]))
            bounds.append(receipt["bounds_px"])
            frames.append(actual)
        path = args.out/f"{args.variant}-{layer}.png"
        temporary = path.with_suffix(".partial.png")
        atlas.save(temporary, compress_level=6)
        temporary.replace(path)
        reports.append({"layer":layer, "atlas":path.name,
                        "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                        "frame_sha256":frames, "frame_bounds_px":bounds,
                        "gpu_rgba8_bytes":atlas.width*atlas.height*4})
    report = {"variant":args.variant, "source_sha256":source, "revision":REVISION,
              "layers":reports, "headings":HEADINGS,
              "status":"baked; Root native and visual acceptance still required"}
    (args.out/f"{args.variant}-bake-receipt.json").write_text(
        json.dumps(report, indent=2)+"\n", encoding="utf-8")
    return report


def main():
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, required=True)
    parser.add_argument("--mode", choices=("preview", "frames", "pack"), default="preview")
    parser.add_argument("--layer", choices=("all", "base", "moving"), default="all")
    parser.add_argument("--heading", type=int, default=28)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--aa", type=int, choices=(1, 2), default=2)
    parser.add_argument("--seconds", type=float, default=90)
    parser.add_argument("--cache", type=Path, default=root/"tools/quality042/.bake-cache/weapons")
    parser.add_argument("--out", type=Path, default=root/"game/assets/boats042/weapons")
    args = parser.parse_args()
    if not 1 <= args.frames <= 8 or not 1 <= args.seconds <= 100:
        parser.error("frames1..8, seconds1..100; Root retains outer cleanup/setup time")
    if args.start < 0 or args.start >= HEADINGS:
        parser.error("start must be0..31")
    deadline = time.perf_counter()+args.seconds
    configure_projection()
    source = source_hash()
    layers = build_weapon(args.variant)
    if args.layer != "all":
        if args.layer not in layers:
            parser.error("this weapon has no "+args.layer+" layer")
        selected = {args.layer:layers[args.layer]}
    else:
        selected = layers
    try:
        if args.mode == "pack":
            if args.layer != "all":
                parser.error("pack requires all layers; never publish a partial weapon")
            print(json.dumps(pack(args, source, layers, deadline)), flush=True)
            return 0
        headings = range(args.start, min(HEADINGS, args.start+args.frames)) if args.mode == "frames" else (args.heading%HEADINGS,)
        for heading in headings:
            for layer in selected:
                if time.perf_counter() >= deadline:
                    raise TimeoutError("deadline before next weapon frame")
                path, report = save_frame(args, source, layers, layer, heading, deadline)
                if args.mode == "preview":
                    args.out.mkdir(parents=True, exist_ok=True)
                    destination = args.out/f"preview-{args.variant}-{layer}-{heading:02d}.png"
                    destination.write_bytes(path.read_bytes())
                print(json.dumps({"frame":str(path), **report}), flush=True)
    except TimeoutError as error:
        print(json.dumps({"status":"INCOMPLETE_BOUNDED", "reason":str(error)}), flush=True)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
