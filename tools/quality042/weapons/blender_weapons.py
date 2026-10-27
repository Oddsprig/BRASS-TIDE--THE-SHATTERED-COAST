"""Optional Root-only Cycles preview of the same authored weapon meshes.

One layer/frame per invocation. Uses SolArt's camera assertion and world light.
Example args after Blender's --: --variant cannon --layer moving --heading 28
 --samples 16 --out <NEW_OUTPUT_DIRECTORY>
"""
import argparse
import json
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from weapon_models import VARIANTS, build_weapon
from blender_hulls import author_model
from blender_scene import configure_scene, render_frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=VARIANTS, required=True)
    parser.add_argument("--layer", choices=("base", "moving"), required=True)
    parser.add_argument("--heading", type=int, default=28)
    parser.add_argument("--samples", type=int, choices=(8, 16, 32), default=16)
    parser.add_argument("--save-model", action="store_true")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    layers = build_weapon(args.variant)
    if args.layer not in layers:
        parser.error("this weapon has no "+args.layer+" layer")
    # Only objects in this factory-startup background process; no user .blend.
    for obj in tuple(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    parent = bpy.data.objects.new("042_assembled_"+args.variant, None)
    bpy.context.scene.collection.objects.link(parent)
    for name, model in layers.items():
        root = author_model(model)
        root.parent = parent
        if name != args.layer:
            # Keep off-camera components as real shadow casters/reflectors.
            for obj in root.children:
                obj.visible_camera = False
    configure_scene(bpy.context.scene, (256, 192), (128, 128), 6, args.samples, 6)
    args.out.mkdir(parents=True, exist_ok=True)
    if args.save_model:
        bpy.ops.wm.save_as_mainfile(filepath=str(args.out/(args.variant+".blend")))
    target = args.out/f"blender-{args.variant}-{args.layer}-{args.heading%32:02d}.png"
    render_frame(bpy.context.scene, parent, args.heading, target, (256, 192), (128, 128), 6)
    print(json.dumps({"status":"rendered; Root review required", "variant":args.variant,
                      "layer":args.layer, "path":str(target)}), flush=True)


if __name__ == "__main__":
    main()
