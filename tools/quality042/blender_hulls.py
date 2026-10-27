"""Optional native quality path for original models; Root runs Blender, never helpers.

Example: blender.exe -b --factory-startup -t 6 --python tools/quality042/blender_hulls.py
 -- --hull ash_corvette --heading 28 --samples 16 --out <NEW_OUTPUT_DIRECTORY>
No atlas loops: a single invocation constructs one hull and renders one frame.
"""
import argparse
import json
from pathlib import Path
import sys

import bpy

sys.path.insert(0,str(Path(__file__).resolve().parent))
from models import MATERIALS,REVISION,build
from blender_scene import configure_scene,render_frame


def materials():
    result={}
    for name,definition in MATERIALS.items():
        mat=bpy.data.materials.new("042_"+name)
        mat.use_nodes=True
        shader=mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value=(*definition.color,1)
        shader.inputs["Metallic"].default_value=definition.metallic
        shader.inputs["Roughness"].default_value=definition.roughness
        if definition.texture in ("wood","metal","fabric"):
            nodes,links=mat.node_tree.nodes,mat.node_tree.links
            tex=nodes.new("ShaderNodeTexNoise")
            tex.inputs["Scale"].default_value=8 if definition.texture == "wood" else 28
            tex.inputs["Detail"].default_value=2
            coord=nodes.new("ShaderNodeTexCoord")
            mapping=nodes.new("ShaderNodeVectorMath")
            mapping.operation="MULTIPLY"
            mapping.inputs[1].default_value=(.15,3,5) if definition.texture == "wood" else (1,1,1)
            links.new(coord.outputs["Object"],mapping.inputs[0])
            links.new(mapping.outputs["Vector"],tex.inputs["Vector"])
            bump=nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value=.15
            bump.inputs["Distance"].default_value=.035
            links.new(tex.outputs["Fac"],bump.inputs["Height"])
            links.new(bump.outputs["Normal"],shader.inputs["Normal"])
        if definition.texture == "glass":
            shader.inputs["Coat Weight"].default_value=.65
            shader.inputs["Coat Roughness"].default_value=.10
        result[name]=mat
    return result


def author_model(model):
    root=bpy.data.objects.new(model.hull_id,None)
    bpy.context.scene.collection.objects.link(root)
    mats=materials()
    for part in model.parts:
        mesh=bpy.data.meshes.new(part.name)
        mesh.from_pydata(part.vertices,[],part.faces)
        mesh.update()
        mesh.materials.append(mats[part.material])
        for poly in mesh.polygons:
            poly.use_smooth=True
        # Authored fillets carry explicit normals; do not resmooth flat roof planes.
        mesh.normals_split_custom_set_from_vertices(part.normals)
        obj=bpy.data.objects.new(part.name,mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent=root
        obj["original_042_component"]=part.name
    for socket in model.sockets:
        obj=bpy.data.objects.new(socket["id"],None)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent=root
        obj.location=(*socket["world_xy"],socket["elevation"])
        obj.empty_display_type="CIRCLE"
        obj.empty_display_size=socket["radius"]
        obj["weapon_socket_only"]=True
    return root


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hull",required=True,choices=("tin_skiff","ash_corvette","brasswind_motor_galleon"))
    parser.add_argument("--heading",type=int,default=28)
    parser.add_argument("--samples",type=int,default=16)
    parser.add_argument("--portrait",action="store_true")
    parser.add_argument("--save-model",action="store_true")
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    # Factory-startup's own default scene objects only; no user session is opened.
    for obj in tuple(bpy.context.scene.objects):
        bpy.data.objects.remove(obj,do_unlink=True)
    model=build(args.hull)
    root=author_model(model)
    factor=2 if args.portrait else 1
    cell,pivot=(384*factor,320*factor),(192*factor,200*factor)
    configure_scene(bpy.context.scene,cell,pivot,2*factor,args.samples,6)
    folder=args.out/args.hull
    folder.mkdir(parents=True,exist_ok=True)
    if args.save_model:
        bpy.ops.wm.save_as_mainfile(filepath=str(folder/(args.hull+".blend")))
    path=folder/("portrait.png" if args.portrait else f"blender-{args.heading%32:02d}.png")
    render_frame(bpy.context.scene,root,args.heading,path,cell,pivot,2*factor)
    print(json.dumps({"status":"rendered; review required","revision":REVISION,"path":str(path),
                      "parts":len(model.parts),"triangles":sum(len(p.faces) for p in model.parts)}),flush=True)


if __name__ == "__main__":
    main()
