"""Deterministic offline CPU hull bake. Root runs this through Test Bridge only.

Real 3D z-buffer, smooth normals, linear-light materials, world-space soft shadow
map, material highlights and directional grain. No game/Blender process is spawned.
Requires existing Python + Pillow + NumPy; never installs or downloads anything.
Each call is bounded by --seconds and --frames; completed PNGs are reusable.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import time

import numpy as np
from PIL import Image

from models import BUILDERS, MATERIALS, REVISION, build

DEFAULT_CELL = (384, 320)
DEFAULT_PIVOT = (192, 200)
CELL = DEFAULT_CELL
PIVOT = DEFAULT_PIVOT
DENSITY = 2
HEADINGS = 32
KEY = np.array((-.55, -.65, 1.0), dtype=np.float32)
KEY /= np.linalg.norm(KEY)
VIEW = np.array((1, 1, .82), dtype=np.float32)
VIEW /= np.linalg.norm(VIEW)


def configure_canvas(hull_id):
    """Select each hull's canvas before construction; never rescale geometry."""
    global CELL, PIVOT
    if hull_id == "brasswind_motor_galleon":
        CELL, PIVOT = (400, 320), (200, 200)
    else:
        CELL, PIVOT = DEFAULT_CELL, DEFAULT_PIVOT


def canvas_metadata():
    """The active base and double-density portrait configuration."""
    return {"cell_px": list(CELL), "pivot_px": list(PIVOT),
            "pixels_per_world_unit": DENSITY,
            "portrait_cell_px": [v*2 for v in CELL],
            "portrait_pivot_px": [v*2 for v in PIVOT],
            "portrait_pixels_per_world_unit": DENSITY*2}


def normalize(v):
    return v / np.maximum(1e-10, np.linalg.norm(v, axis=-1, keepdims=True))


def srgb_to_linear(c):
    return np.where(c <= .04045, c/12.92, ((c+.055)/1.055)**2.4)


def linear_to_srgb(c):
    return np.where(c <= .0031308, c*12.92, 1.055*np.maximum(c, 0)**(1/2.4)-.055)


def source_hash():
    h = hashlib.sha256()
    for name in ("models.py", "bake.py"):
        h.update(Path(__file__).with_name(name).read_bytes())
    return h.hexdigest()


def arrays(model, angle):
    vertices, normals, faces, mids = [], [], [], []
    names = list(MATERIALS)
    for part in model.parts:
        base = len(vertices)
        vertices.extend(part.vertices)
        normals.extend(part.normals)
        faces.extend(tuple(base+i for i in f) for f in part.faces)
        mids.extend([names.index(part.material)]*len(part.faces))
    v, n = np.asarray(vertices, np.float32), np.asarray(normals, np.float32)
    c, s = math.cos(angle), math.sin(angle)
    rotation = np.array(((c, -s, 0), (s, c, 0), (0, 0, 1)), np.float32)
    return v @ rotation.T, normalize(n @ rotation.T), np.asarray(faces, np.int32), np.asarray(mids, np.int16)


def raster(screen, depth, faces, width, height, deadline, attributes=None, face_materials=None):
    """Tiled triangle AABBs keep allocation proportional to a single face."""
    zbuffer = np.full((height, width), -np.inf, np.float32)
    attr = None if attributes is None else np.zeros((height, width, attributes.shape[1]), np.float32)
    mat = None if face_materials is None else np.full((height, width), -1, np.int16)
    for fi, f in enumerate(faces):
        if fi % 256 == 0 and time.perf_counter() > deadline:
            raise TimeoutError("bounded bake deadline; completed cached frames remain valid")
        a, b, c = screen[f]
        x0 = max(0, math.floor(min(a[0], b[0], c[0])))
        x1 = min(width-1, math.ceil(max(a[0], b[0], c[0])))
        y0 = max(0, math.floor(min(a[1], b[1], c[1])))
        y1 = min(height-1, math.ceil(max(a[1], b[1], c[1])))
        if x1 < x0 or y1 < y0:
            continue
        den = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den) < 1e-8:
            continue
        # A tall hull face may span the whole sprite; still well below 1MB/tile.
        xx, yy = np.meshgrid(np.arange(x0,x1+1,dtype=np.float32)+.5,
                             np.arange(y0,y1+1,dtype=np.float32)+.5)
        wa = ((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
        wb = ((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
        wc = 1-wa-wb
        zz = wa*depth[f[0]]+wb*depth[f[1]]+wc*depth[f[2]]
        region = zbuffer[y0:y1+1,x0:x1+1]
        mask = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6) & (zz > region)
        if not np.any(mask):
            continue
        region[mask] = zz[mask]
        if attr is not None:
            out = attr[y0:y1+1,x0:x1+1]
            values = wa[mask,None]*attributes[f[0]]+wb[mask,None]*attributes[f[1]]+wc[mask,None]*attributes[f[2]]
            out[mask] = values
        if mat is not None:
            mat[y0:y1+1,x0:x1+1][mask] = face_materials[fi]
    return zbuffer, attr, mat


def shadow_map(v, faces, deadline, resolution=512):
    side = normalize(np.cross(KEY, np.array((0,0,1),np.float32)))
    up = normalize(np.cross(side, KEY))
    plane = np.column_stack((v @ side, v @ up))
    low = plane.min(axis=0)-3
    span = float(max((plane.max(axis=0)+3-low)))
    factor = (resolution-1)/span
    screen = (plane-low)*factor
    z, _, _ = raster(screen, v @ KEY, faces, resolution, resolution, deadline)
    return z, side, up, low, factor


def shade(pos, normal, materials, shadow, texture_pos=None):
    n = normalize(normal)
    diffuse = np.maximum(0, n @ KEY)
    zmap, side, up, low, factor = shadow
    ss = (np.column_stack((pos @ side, pos @ up))-low)*factor
    ix, iy = np.rint(ss[:,0]).astype(int), np.rint(ss[:,1]).astype(int)
    d = pos @ KEY
    visibility = np.zeros(len(pos),np.float32)
    # Small PCF kernel gives softly cast rigging/cabin/rail shadows.
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            sx, sy = np.clip(ix+dx,0,zmap.shape[1]-1), np.clip(iy+dy,0,zmap.shape[0]-1)
            visibility += (d+.27+.32*(1-diffuse) >= zmap[sy,sx])/9
    half_vector = normalize(KEY+VIEW)
    ndh = np.maximum(0,n @ half_vector)
    ndv = np.maximum(0,n @ VIEW)
    result = np.zeros_like(pos)
    for i, mat in enumerate(MATERIALS.values()):
        hit = materials == i
        if not np.any(hit):
            continue
        # Grain belongs to the object; illumination belongs to the world.
        p = (pos if texture_pos is None else texture_pos)[hit]
        base = srgb_to_linear(np.asarray(mat.color,dtype=np.float32))
        grain = np.ones(len(p),np.float32)
        if mat.texture == "wood":
            grain = .94+.06*np.sin(p[:,1]*8+np.sin(p[:,0]*.35)*.7)
            grain *= np.where(np.mod(p[:,1]+.35,1.25)<.055,.61,1)
            grain *= .98+.02*np.sin(p[:,0]*4+p[:,1]*13)
        elif mat.texture == "metal":
            grain = .97+.03*np.sin(p[:,0]*2.7+p[:,2]*9)
        elif mat.texture in ("fabric","rope"):
            grain = .94+.06*np.sin(p[:,0]*13)*np.sin(p[:,1]*12+p[:,2]*8)
        # Cool sky fill and warm low-saturation dockyard sun, in linear space.
        sky = .24+.20*np.maximum(0,n[hit,2])
        light = sky[:,None]*np.array((.75,.87,1.0))
        light += (diffuse[hit]*visibility[hit]*1.7)[:,None]*np.array((1.0,.91,.73))
        power = 12+180*(1-mat.roughness)**3
        fresnel = .04*(1-mat.metallic)+base*mat.metallic
        spec = (ndh[hit]**power*visibility[hit]*(1.4+mat.metallic*2.2))[:,None]*fresnel
        rgb = base*grain[:,None]*light*(1-mat.metallic*.25)+spec
        if mat.texture == "glass":
            # Opaque stylized reflected sky: no transparent holes through cabins.
            rgb += ((1-ndv[hit])**3)[:,None]*np.array((.10,.24,.29))
            rgb += np.maximum(0,n[hit,2])[:,None]*np.array((.035,.08,.1))
        result[hit] = rgb
    # Gentle film shoulder, preserve broad local value differences.
    return np.clip(linear_to_srgb(result/(1+result*.35)),0,1)


def render(model, heading, density, supersample, deadline):
    scale = density/DENSITY
    cell = tuple(round(v*scale) for v in CELL)
    pivot = np.asarray(PIVOT,np.float32)*scale
    angle=heading*math.tau/HEADINGS
    v,n,faces,mids = arrays(model,angle)
    c,s=math.cos(angle),math.sin(angle)
    texture_pos=np.column_stack((v[:,0]*c+v[:,1]*s,-v[:,0]*s+v[:,1]*c,v[:,2]))
    screen = np.column_stack(((v[:,0]-v[:,1])*.82,(v[:,0]+v[:,1])*.41-v[:,2]))
    screen = (screen*density+pivot)*supersample
    # Catch clipping before producing a falsely complete atlas.
    lo, hi = screen.min(axis=0)/supersample, screen.max(axis=0)/supersample
    if np.any(lo < 1) or np.any(hi > np.asarray(cell)-2):
        raise ValueError(f"{model.hull_id} heading {heading} exceeds declared cell: {lo} .. {hi}")
    sh = shadow_map(v,faces,deadline)
    z, attr, mat = raster(screen,v @ VIEW,faces,cell[0]*supersample,cell[1]*supersample,
                          deadline,np.column_stack((v,n,texture_pos)),mids)
    hit = mat >= 0
    rgb = shade(attr[hit,:3],attr[hit,3:6],mat[hit],sh,attr[hit,6:9])
    rgba = np.zeros((cell[1]*supersample,cell[0]*supersample,4),np.uint8)
    rgba[hit,:3] = np.rint(rgb*255).astype(np.uint8)
    rgba[hit,3] = 255
    img = Image.fromarray(rgba,"RGBA")
    if supersample > 1:
        # Pillow's premultiplied mode prevents dark transparent fringes.
        img = img.convert("RGBa").resize(cell,Image.Resampling.LANCZOS).convert("RGBA")
    return img, {"bounds_px":img.getbbox(),"vertices":len(v),"triangles":len(faces),"parts":len(model.parts)}


def cache_key(source, hull_id, heading, density, aa):
    return hashlib.sha256(f"{source}:{hull_id}:{heading}:{density}:{aa}".encode()).hexdigest()[:20]


def asset_metadata(args,hull_id,**changes):
    """Fill actual alpha bounds only when baking into a real manifest directory."""
    manifest=args.out/"asset-manifest.json"
    if manifest.is_file():
        data=json.loads(manifest.read_text(encoding="utf-8"))
        entry=data.get("hulls",{}).get(hull_id)
        if isinstance(entry,dict):
            entry.update(canvas_metadata())
            entry.update(changes)
            manifest.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")


def xywh(bbox):
    if bbox is None:
        raise ValueError("empty alpha is not a finished hull asset")
    return [bbox[0],bbox[1],bbox[2]-bbox[0],bbox[3]-bbox[1]]


def save_frame(model, heading, density, args, deadline, source):
    key = cache_key(source,model.hull_id,heading,density,args.aa)
    folder = args.cache/model.hull_id
    folder.mkdir(parents=True,exist_ok=True)
    path, receipt = folder/(key+".png"), folder/(key+".json")
    if path.exists() and receipt.exists():
        metadata=json.loads(receipt.read_text(encoding="utf-8"))
        if metadata.get("png_sha256") != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError(f"cached PNG changed: {path}")
        return path,metadata
    started = time.perf_counter()
    img, metadata = render(model,heading,density,args.aa,deadline)
    metadata.update({"source_sha256":source,"revision":REVISION,"hull_id":model.hull_id,
                     "heading":heading,"density":density,"aa":args.aa,"cell_px":list(img.size),
                     "pivot_px":[round(v*density/DENSITY) for v in PIVOT],
                     "canvas_config":canvas_metadata(),
                     "seconds":round(time.perf_counter()-started,3),"png_sha256":"",
                     "sockets":model.sockets})
    temp = path.with_suffix(".partial.png")
    img.save(temp,compress_level=3)
    temp.replace(path)
    metadata["png_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    receipt.write_text(json.dumps(metadata,indent=2)+"\n",encoding="utf-8")
    return path,metadata


def pack(model,args,source,deadline):
    paths=[]
    bounds=[]
    for h in range(HEADINGS):
        if time.perf_counter() >= deadline:
            raise TimeoutError("bounded deadline during pack")
        path=args.cache/model.hull_id/(cache_key(source,model.hull_id,h,DENSITY,args.aa)+".png")
        receipt=path.with_suffix(".json")
        if not path.is_file() or not receipt.is_file():
            raise FileNotFoundError(f"atlas incomplete: bake heading {h} first ({path})")
        metadata=json.loads(receipt.read_text(encoding="utf-8"))
        if metadata.get("source_sha256") != source or metadata.get("png_sha256") != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError(f"frame/source receipt mismatch: {path}")
        paths.append(path)
    atlas=Image.new("RGBA",(CELL[0]*8,CELL[1]*4))
    for h,path in enumerate(paths):
        with Image.open(path) as frame:
            if frame.size != CELL or frame.mode != "RGBA":
                raise ValueError(f"cached frame contract mismatch: {path}")
            bounds.append(xywh(frame.getbbox()))
            atlas.paste(frame,((h%8)*CELL[0],(h//8)*CELL[1]))
    folder=args.out/model.hull_id
    folder.mkdir(parents=True,exist_ok=True)
    target=folder/"hull-atlas.png"
    temporary=target.with_suffix(".partial.png")
    atlas.save(temporary,compress_level=6)
    temporary.replace(target)
    report={"source_sha256":source,"hull_id":model.hull_id,"headings":HEADINGS,
            "atlas_sha256":hashlib.sha256(target.read_bytes()).hexdigest(),
            "canvas_config":canvas_metadata(),
            "atlas_size_px":list(atlas.size),"gpu_rgba8_bytes":atlas.width*atlas.height*4,
            "status":"baked; visual and native integration review still required"}
    (folder/"bake-receipt.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    asset_metadata(args,model.hull_id,frame_bounds_px=bounds,asset_status="baked_pending_visual_review",
                   source_sha256=source,atlas_source_sha256=source,
                   atlas_sha256=report["atlas_sha256"],sockets=model.sockets)
    print(json.dumps(report),flush=True)


def main():
    root=Path(__file__).resolve().parents[2]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--hull",choices=[*BUILDERS,"all"],default="tin_skiff")
    p.add_argument("--mode",choices=("preview","frames","pack","portrait"),default="preview")
    p.add_argument("--start",type=int,default=0)
    p.add_argument("--frames",type=int,default=1)
    p.add_argument("--heading",type=int,default=28)
    p.add_argument("--aa",type=int,choices=(1,2),default=2)
    p.add_argument("--seconds",type=float,default=95)
    p.add_argument("--cache",type=Path,default=root/"tools/quality042/.bake-cache")
    p.add_argument("--out",type=Path,default=root/"game/assets/boats042")
    args=p.parse_args()
    if not 1 <= args.frames <= 32 or not 1 <= args.seconds <= 105:
        p.error("frames must be1..32; seconds1..105; Root retains outer job cleanup time")
    if not 0 <= args.start < HEADINGS:
        p.error("start must be0..31")
    source=source_hash()
    deadline=time.perf_counter()+args.seconds
    hulls=BUILDERS if args.hull == "all" else (args.hull,)
    try:
        for hull_id in hulls:
            configure_canvas(hull_id)
            model=build(hull_id)
            if args.mode == "pack":
                pack(model,args,source,deadline)
                continue
            headings=range(args.start,min(HEADINGS,args.start+args.frames)) if args.mode == "frames" else (args.heading%HEADINGS,)
            for h in headings:
                if time.perf_counter() >= deadline:
                    raise TimeoutError("bounded job deadline before next frame")
                density=4 if args.mode == "portrait" else DENSITY
                path,report=save_frame(model,h,density,args,deadline,source)
                folder=args.out/hull_id
                folder.mkdir(parents=True,exist_ok=True)
                if args.mode in ("preview","portrait"):
                    name="portrait.png" if args.mode == "portrait" else f"preview-{h:02d}.png"
                    (folder/name).write_bytes(path.read_bytes())
                    if args.mode == "portrait":
                        asset_metadata(args,hull_id,portrait_bounds_px=xywh(report["bounds_px"]),
                                       portrait_heading=h,portrait_sha256=report["png_sha256"],
                                       portrait_source_sha256=source)
                print(json.dumps({"frame":str(path),**report}),flush=True)
    except TimeoutError as ex:
        print(json.dumps({"status":"INCOMPLETE_BOUNDED","reason":str(ex)}),flush=True)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
