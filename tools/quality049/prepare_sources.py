"""Write source JSON/matrix from frozen canonical data; never import/build a model.

This is source preparation only: no images, mesh files, bakes or engine calls.
Root must preserve the three existing runtime entries when merging the seed.
"""
import hashlib
import json
import math
import re
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
LEGACY={"tin_skiff":((384,320),(192,200)),"ash_corvette":((384,320),(192,200)),
        "brasswind_motor_galleon":((400,320),(200,200))}
# Hull|paint|trim|deck|max-height ceiling|functional silhouette and machinery identity
LAYOUTS="""bilge_punt|tin|oxide|deck|19|Open patched scout; offset exposed motor and salvage reel
lantern_skiff|teal_light|ivory|tin|23|Customs canopy; raised searchlight; twin transom motors
marsh_dart|teal_light|ivory|tin|19|Stepped open hydroplane; center jet and transverse foil
scab_cutter|tin|oxide|armor_light|22|Sawtooth bow cheeks; low slit house; split exhaust and twin screws
gale_cutter|teal_light|ivory|tin|20|Swept pursuit foil; narrow canopy; twin supercharged jet machinery
silt_lugger|timber|ivory|deck|20|Broad dry-cargo cat; low canopy; paired holds and side bales
hook_raider|tin|oxide|deck|24|Narrow contraband cat; offset davit; low bridge and paired jets
mercantile_clipper|teal_light|brass_light|deck|30|Fine treasury cat bows; stepped packet house and bonded safes
harbor_sloop|tin|brass|tin|27|Round patrol hull; brass wheelhouse; one stack and tow capstan
aegis_corvette|teal_light|ivory|tin|31|Fine escort prow; full rangefinder wing and damage-control chests
reed_stinger|teal_light|ivory|tin|20|Low open marsh launch; single jet and air-receiver manifold
krill_torpedo|tin|oxide|tin|22|Low wolfpack hood; empty reload skid; split motor and stack
manta_strike|teal_light|ivory|tin|28|Swept wide foil; tall narrow command fin and paired jets
slag_gunboat|armor_light|ivory|tin|24|Blunt ironclad; single armor course; low casemate and twin stacks
bellows_gunboat|tin|ivory|armor_light|26|Broad siege hull; double belt; external bilge manifolds and paired engines
furnace_turret|armor_light|ivory|tin|29|Bulged bastion; triple belt; raised conning cupola and three ejectors
barbed_lance|tin|ivory|deck|20|Wide ore scow; timber push cheeks; covered hold and igniter boxes
cinder_monitor|armor_light|ivory|tin|27|Full-bodied monitor; low bunker; one broad stack and insulated safes
wraith_rocket|tin|ivory|armor_light|33|Long salvo hull; narrow fire-control tower and paired jet plants
cobalt_frigate|teal_light|ivory|tin|34|Command frigate; stepped flag bridge and dual turbine exhaust
iron_bastion|tin|brass_light|armor_light|38|Heavy flagship; double belt; high signal house and pump dome
maiden_dreadnought|armor_light|ivory|tin|41|Long capital bow; triple belt; triple funnels and three transom drives
kelpnet_dory|timber|ivory|deck|17|Short open fishing dory; large hand reel; coiled net stack and broad catch well
brinehook_longliner|teal_light|ivory|deck|24|Long working stern; paired line reels and offset davit under canopy
mother_gull_trawler|timber|ivory|deck|25|Broad trawling cat; stern net reels and full-width working gantry
fenhopper_lighter|timber|ivory|deck|18|Flat twin-hull lighter; compressed bale stacks and loading ramp
tideledger_coaster|teal_light|ivory|deck|28|Long coastal cat; raised cargo davit; covered holds and bonded safes
fourport_packet|teal_light|brass_light|deck|32|High two-level packet house; long covered hatches and twin exhaust
seepoil_tanker|tin|ivory|armor_light|19|Round tank barge; broad horizontal tanks with saddles and connected transfer mains
blackwater_fleet_tanker|tin|ivory|armor_light|25|Long fleet tanker; four horizontal tanks with solid inspection caps; three transom drives
gullwing_daysailer|ivory|teal_light|deck|19|Fine pleasure hydrofoil; stepped cockpit and cushioned foredeck
osprey_cabin_cruiser|ivory|brass_light|deck|24|Long lacquered cabin launch; raised glazed day salon and twin motors
aurelian_court_yacht|ivory|brass_light|deck|34|Long court yacht; two-level household bridge; wide signal wing and settee"""


def mip_bytes(width,height):
    total=0
    while True:
        total+=width*height*4
        if width==height==1:return total
        width=max(1,width//2);height=max(1,height//2)


def main():
    world_path=ROOT/"game/data/world.json"
    profile_path=ROOT/"game/scripts/hull_profiles.gd"
    world=json.loads(world_path.read_text(encoding="utf-8"))
    text=profile_path.read_text(encoding="utf-8")
    profiles={}
    for match in re.finditer(r'"([a-z_]+)": \{"name": "([^"]+)"[^\n]+\n\s*"stations": \[([^\n]+)',text):
        points=[(float(x),float(y)) for x,y in re.findall(r'Vector2\(([-\d.]+), ([-\d.]+)\)',match[3])]
        profiles[match[1]]=(match[2],points)
    designs={row.split("|")[0]:row.split("|")[1:] for row in LAYOUTS.splitlines()}
    catalog={};seed={};matrix=[];footprints=[];atlas_base=atlas_mips=portrait_base=portrait_mips=0
    for hull in world["HULLS"]:
        hid=hull["id"];size=hull["size"];name,st=profiles[hid]
        if hid in LEGACY:
            cell,pivot=LEGACY[hid];status="PRESERVE_EXISTING_042"
            identity="Prior authored recipe and runtime asset entry unchanged"
        else:
            paint,trim,deck,ceiling,identity=designs[hid]
            cat=hull["role"]=="raider";offset=.62 if cat else 0
            # A source envelope, NOT a measured alpha or executed mesh bound.
            # Includes caprails, Hermite width overshoot and transom motor guards.
            radius=max(math.hypot(x*size,(w+offset)*size+.65) for x,w in st)
            radius=max(radius,math.hypot((st[0][0]-.37)*size-1,
                                        (.62 if cat else .36)*size+1.5))+1
            side=math.ceil(2*.82*math.sqrt(2)*radius)
            upper=math.ceil(2*(.41*math.sqrt(2)*radius+float(ceiling)))
            lower=math.ceil(2*.41*math.sqrt(2)*radius)
            cell=(math.ceil((side*2+12)/8)*8,math.ceil((upper+lower+12)/8)*8)
            pivot=(cell[0]//2,upper+6)
            d={"name":name,"size":size,"role":hull["role"],"tier":hull["tier"],
               "faction":hull["faction"],"civilian_role":hull.get("civilianRole",""),
               "stations":st,"hull_material":paint,"trim_material":trim,"deck_material":deck,
               "height_ceiling_world":float(ceiling),"source_radius_envelope_world":round(radius,6),
               "cell_px":cell,"pivot_px":pivot,"identity":identity}
            catalog[hid]=d;status="SOURCE_RECIPE_ONLY"
            seed[hid]={"name":name,"size":size,"asset_status":"source_recipe_only_UNBAKED",
               "atlas":f"res://assets/boats042/{hid}/hull-atlas.png","headings":32,"columns":8,"rows":4,
               "cell_px":cell,"pivot_px":pivot,"pixels_per_world_unit":2,
               "cell_status":"source ceiling; Root baker tightens to actual all32-heading model geometry",
               "portrait":f"res://assets/boats042/{hid}/portrait.png","portrait_heading":0,
               "portrait_cell_px":[n*2 for n in cell],"portrait_pivot_px":[n*2 for n in pivot],
               "portrait_pixels_per_world_unit":4,"frame_bounds_px":[],"portrait_bounds_px":[],
               "source_station_bounds_local":[st[0][0],-max(w for _,w in st)-offset,
                                              st[-1][0],max(w for _,w in st)+offset],
               "geometry_envelope_status":"source arithmetic only; actual mesh and alpha UNMEASURED",
               "source_radius_envelope_world":round(radius,6),"height_ceiling_world":float(ceiling),
               "sockets":[],"installed_guns_in_hull":False}
        w,h=cell
        ab=w*h*32*4;am=mip_bytes(w*8,h*4);pb=w*h*16;pm=mip_bytes(w*2,h*2)
        atlas_base+=ab;atlas_mips+=am;portrait_base+=pb;portrait_mips+=pm
        matrix.append([hid,str(size),hull["role"],hull.get("civilianRole","combat"),
                       f"{w}x{h}",f"{pivot[0]},{pivot[1]}",str(ab),status,identity])
        offset=.62 if hull["role"]=="raider" else 0
        radial=max(math.hypot(x,w+offset) for x,w in st)
        footprints.append([hid,round((st[-1][0]-st[0][0])*size,3),
            round(2*(max(w for _,w in st)+offset)*size,3),2*size,round(radial,6)])
    metadata={"schema":"brass-tide-boats042-v1","source_revision":"049-roster-detail-r2",
       "asset_status":"SOURCE_SEED_ONLY_NOT_A_RUNTIME_MANIFEST","preserve_existing_hulls":list(LEGACY),
       "merge_rule":"Add only these33 entries in Root staging; never overwrite existing3 receipts/bounds",
       "source_inputs_sha256":{str(p.relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in (world_path,profile_path,ROOT/"game/scripts/mount_layout.gd")},
       "hulls":seed}
    (HERE/"catalog.json").write_text(json.dumps(catalog,indent=2)+"\n",encoding="utf-8")
    (HERE/"manifest-seed.json").write_text(json.dumps(metadata,indent=2)+"\n",encoding="utf-8")
    (HERE/"ROSTER.tsv").write_text("\t".join(["id","size","role","civilian","cell_px","waterline_pivot_px","atlas_RGBA8_bytes","status","identity"])+"\n"+
                                   "\n".join("\t".join(row) for row in matrix)+"\n",encoding="utf-8")
    (HERE/"FOOTPRINTS.tsv").write_text("id\tstation_length_world\tstation_beam_world\tcollision_diameter_world\tstation_radius_div_collision_radius\n"+
        "\n".join("\t".join(map(str,row)) for row in footprints)+"\n",encoding="utf-8")
    budget={"status":"SOURCE_CONFIGURED_ALLOCATION; actual PNG sizes and bake durations UNMEASURED",
       "headings":32,"density":2,"atlas_layout":[8,4],"hulls":len(matrix),"missing_recipes":len(catalog),
       "atlas_rgba8_base_bytes":atlas_base,"atlas_rgba8_with_full_mip_chain_bytes":atlas_mips,
       "portrait_rgba8_base_bytes":portrait_base,"portrait_rgba8_with_full_mip_chain_bytes":portrait_mips,
       "all_hull_textures_with_mips_bytes":atlas_mips+portrait_mips,
       "all_hull_textures_with_mips_MiB":round((atlas_mips+portrait_mips)/1048576,6),
       "limits":"Uncompressed upper allocation for all36 resident; excludes weapons, driver alignment, import compression, staging/cache and other game textures"}
    (HERE/"budget.json").write_text(json.dumps(budget,indent=2)+"\n",encoding="utf-8")
    production=[ROOT/"tools/quality042/models.py",ROOT/"tools/quality042/bake.py",
                HERE/"recipes.py",HERE/"catalog.json"]
    source_hash=hashlib.sha256()
    for path in production:source_hash.update(path.read_bytes())
    source=source_hash.hexdigest()
    authorities=[world_path,profile_path,ROOT/"game/scripts/mount_layout.gd",ROOT/"game/scripts/weapon_geometry.gd"]
    inputs={path.as_posix():hashlib.sha256(path.read_bytes()).hexdigest() for path in production+authorities}
    binding={"base_commit":"a157241f6d817f08cf231299d35e6539c61e2359","bake_bundle_sha256":source,
        "concatenation":[path.relative_to(ROOT).as_posix() for path in production],
        "input_file_sha256":{path.relative_to(ROOT).as_posix():inputs[path.as_posix()] for path in production+authorities},
        "status":"SOURCE ONLY; model construction, bake, visual and native review UNRUN"}
    (HERE/"source-binding.json").write_text(json.dumps(binding,indent=2)+"\n",encoding="utf-8")
    out=ROOT.parent/("v049-preview-"+source[:12]);cache=ROOT.parent/("v049-cache-"+source[:12])
    key=hashlib.sha256(f"{source}:kelpnet_dory:0:2:2".encode()).hexdigest()[:20]
    plan={"requires_gpu":False,"source":"049-source-bundle-sha256:"+source,"cwd":ROOT.as_posix(),
        "command":[sys.executable,"-B","tools/quality042/bake.py","--hull","kelpnet_dory",
                   "--mode","preview","--heading","0","--aa","2","--seconds","75",
                   "--out",out.as_posix(),"--cache",cache.as_posix()],"inputs":inputs,
        "expected_outputs":[(out/"kelpnet_dory/preview-00.png").as_posix(),
                            (cache/"kelpnet_dory"/(key+".png")).as_posix(),
                            (cache/"kelpnet_dory"/(key+".json")).as_posix()]}
    (HERE/"preview-kelpnet.plan.json").write_text(json.dumps(plan,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(budget))


if __name__=="__main__":main()
