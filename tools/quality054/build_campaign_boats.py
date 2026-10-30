"""Original Brass Tide chart boats, authored as reproducible top-down SVGs.

CPU-only, Python standard library. No engine/import/render/dependencies. Reads
the canonical catalogue, HullProfiles, MountLayout and the 049 material catalog
without executing them. Writes only game/assets/campaign054/boats. Root performs
native import/review. v0.073 detail uses the current 36 designs and 042 paint.
"""
from __future__ import annotations

import ast
import hashlib
import html
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/campaign054/boats"
CATALOG_PATH = ROOT / "tools/quality049/catalog.json"
REVISION = "073-chart-hull-detail-r1"

# sRGB copies of tools/quality042/models.py MATERIALS. Chart paint only.
MATERIALS = {
    "tin": (.52, .62, .63),
    "teal": (.09, .29, .29),
    "teal_light": (.22, .45, .43),
    "ivory": (.78, .76, .62),
    "armor": (.22, .27, .28),
    "armor_light": (.37, .42, .42),
    "oxide": (.52, .18, .095),
    "brass": (.64, .43, .17),
    "brass_light": (.83, .64, .31),
    "timber": (.43, .27, .13),
    "deck": (.56, .43, .27),
    "seam": (.13, .16, .15),
    "rubber": (.045, .058, .055),
    "machinery": (.16, .21, .20),
    "steel": (.52, .57, .56),
    "glass": (.10, .30, .34),
    "glass_edge": (.42, .66, .68),
    "canvas": (.42, .47, .31),
    "rope": (.59, .50, .32),
    "lamp": (.95, .77, .35),
    "red": (.58, .12, .08),
}

# House, plant and top-down cues for the current 36 designs. Hull, deck and
# trim for the 33 recipes come from catalog.json. The three 042 builders are
# not in that file, so their materials live here. Funnels are (y, material).
EXTRAS = {
    "tin_skiff": dict(hull="tin", deck="deck", trim="teal", house="teal", engine="ivory", funnels=(), courses=0, foil=None, split=False),
    "bilge_punt": dict(house="ivory", engine="tin", funnels=(), courses=0, foil=None, split=False),
    "lantern_skiff": dict(house="ivory", engine="machinery", funnels=(), courses=0, foil=None, split=False),
    "marsh_dart": dict(house="ivory", engine="machinery", funnels=(), courses=0, foil=.18, split=False),
    "scab_cutter": dict(house="armor_light", engine="machinery", funnels=((.20, "steel"),), courses=0, foil=None, split=False),
    "gale_cutter": dict(house="teal_light", engine="machinery", funnels=(), courses=0, foil=.14, split=True),
    "silt_lugger": dict(house="timber", engine="teal_light", funnels=(), courses=0, foil=None, split=True),
    "hook_raider": dict(house="oxide", engine="machinery", funnels=((0, "steel"),), courses=0, foil=None, split=False),
    "mercantile_clipper": dict(house="ivory", engine="machinery", funnels=(), courses=0, foil=None, split=True),
    "harbor_sloop": dict(house="ivory", engine="machinery", funnels=((0, "brass"),), courses=0, foil=None, split=False),
    "ash_corvette": dict(hull="armor", deck="deck", trim="oxide", house="armor", engine="machinery", funnels=((0, "machinery"),), courses=1, foil=None, split=False),
    "aegis_corvette": dict(house="tin", engine="machinery", funnels=((0, "steel"),), courses=0, foil=None, split=False),
    "reed_stinger": dict(house="ivory", engine="teal_light", funnels=(), courses=0, foil=.16, split=False),
    "krill_torpedo": dict(house="tin", engine="machinery", funnels=((-.20, "steel"),), courses=0, foil=None, split=False),
    "manta_strike": dict(house="teal_light", engine="machinery", funnels=(), courses=0, foil=.14, split=True),
    "slag_gunboat": dict(house="armor_light", engine="machinery", funnels=((-.17, "steel"), (.17, "steel")), courses=1, foil=None, split=False),
    "bellows_gunboat": dict(house="tin", engine="machinery", funnels=((-.20, "steel"), (.20, "steel")), courses=2, foil=None, split=True),
    "furnace_turret": dict(house="armor_light", engine="machinery", funnels=((-.20, "steel"), (.20, "steel")), courses=3, foil=None, split=False),
    "barbed_lance": dict(house="timber", engine="machinery", funnels=(), courses=0, foil=None, split=False),
    "cinder_monitor": dict(house="armor_light", engine="machinery", funnels=((0, "steel"),), courses=2, foil=None, split=False),
    "wraith_rocket": dict(house="tin", engine="machinery", funnels=(), courses=0, foil=None, split=True),
    "cobalt_frigate": dict(house="ivory", engine="machinery", funnels=((-.20, "brass"), (.20, "brass")), courses=0, foil=None, split=True),
    "iron_bastion": dict(house="tin", engine="machinery", funnels=((-.22, "steel"), (.22, "steel")), courses=2, foil=None, split=False),
    "maiden_dreadnought": dict(house="armor_light", engine="machinery", funnels=((-.23, "steel"), (0, "steel"), (.23, "steel")), courses=3, foil=None, split=False),
    "kelpnet_dory": dict(house="ivory", engine="tin", funnels=(), courses=0, foil=None, split=False),
    "brinehook_longliner": dict(house="ivory", engine="machinery", funnels=(), courses=0, foil=None, split=False),
    "mother_gull_trawler": dict(house="timber", engine="machinery", funnels=(), courses=0, foil=None, split=True),
    "fenhopper_lighter": dict(house="timber", engine="machinery", funnels=(), courses=0, foil=None, split=True),
    "tideledger_coaster": dict(house="ivory", engine="machinery", funnels=(), courses=0, foil=None, split=True),
    "fourport_packet": dict(house="ivory", engine="machinery", funnels=((-.23, "brass"), (.23, "brass")), courses=0, foil=None, split=True),
    "brasswind_motor_galleon": dict(hull="teal", deck="deck", trim="brass", house="ivory", engine="teal", funnels=((-.20, "brass"), (.20, "brass")), courses=0, foil=None, split=True),
    "seepoil_tanker": dict(house="tin", engine="machinery", funnels=(), courses=0, foil=None, split=False),
    "blackwater_fleet_tanker": dict(house="ivory", engine="machinery", funnels=((0, "steel"),), courses=0, foil=None, split=False),
    "gullwing_daysailer": dict(house="ivory", engine="ivory", funnels=(), courses=0, foil=.12, split=False),
    "osprey_cabin_cruiser": dict(house="ivory", engine="ivory", funnels=(), courses=0, foil=None, split=False),
    "aurelian_court_yacht": dict(house="ivory", engine="ivory", funnels=(), courses=0, foil=None, split=True),
}


def literal(path: Path, name: str):
    source = path.read_text(encoding="utf-8-sig")
    match = re.search(r"const " + re.escape(name) + r"\s*:\s*Dictionary\s*=\s*(\{.*?\n\})", source, re.S)
    if match is None:
        raise ValueError(f"Missing exact dictionary {name} in {path}")
    value = re.sub(r"Vector2\(([^()]+)\)", r"(\1)", match.group(1))
    return ast.literal_eval(re.sub(r"\b(false|true)\b", lambda m: m[1].title(), value))


def clamp(value, low, high):
    return max(low, min(high, value))


def godot_hash(text):
    value = 5381
    for char in text:
        value = (value * 33 + ord(char)) & 0xFFFFFFFF
    return value if value < 0x80000000 else value - 0x100000000


def chassis(spec, roles):
    """Exact XY variation from MountLayout, including its signed32 hash."""
    base = roles[spec["role"]]
    tier, size = spec["tier"], spec["size"]
    bias = {"forge": -.012, "reed": .014, "raiders": .008}.get(spec["faction"], 0)
    jitter = (abs(godot_hash(spec["id"])) % 5 - 2) * .004
    step = (tier - 2) * .010
    cat = base["arch"] == "catamaran"
    primary = 1 if size < 19 else 2 if size < 27 else 3
    secondary = max(1, primary - 1)
    sx = clamp(base["sideMountX"] + bias * .8 + jitter, .47, .53)
    sy = clamp(base["sideMountY"] + step * .4, .54 if cat else .42, .58 if cat else .445)
    sockets = [
        dict(id="mount0", x=clamp(base["bowMountX"] + step + bias + jitter, .96, 1.08), y=0, size=primary, angle=0),
        dict(id="mount1", x=clamp(base["aftMountX"] - step * .5 + jitter, -1.53, -1.46), y=0, size=secondary, angle=math.pi),
    ]
    if size >= 20:
        sockets.append(dict(id="mount2", x=sx, y=-sy, size=secondary, angle=-math.pi/2))
    if size >= 28:
        sockets.append(dict(id="mount3", x=sx, y=sy, size=secondary, angle=math.pi/2))
    for socket in sockets:
        socket["radius"] = (.14 if socket["size"] <= 1 else .15) if socket["id"] in ("mount2", "mount3") else (.16 if socket["size"] <= 1 else .18 if socket["size"] == 2 else .20)
    return dict(cat=cat, sockets=sockets,
                cabin=dict(x=clamp(base["cabinX"] + bias * .5 + jitter, -.32, -.28), y=0,
                           len=clamp(base["cabinLen"] + (tier-2)*.010, .68, .76),
                           wid=clamp(base["cabinWid"] + (tier-2)*.010, .48, .60)),
                engine=dict(x=clamp(base["engineX"] + jitter*.5, -1.03, -.98), y=0,
                            len=clamp(base["engineLen"] + (tier-2)*.008, .32, .38),
                            wid=clamp(base["engineWid"] + (tier-2)*.010, .38, .56)),
                stacks=base["stacks"] + (1 if tier >= 4 and base["stacks"] == 1 else 0),
                spread=base["stackSpread"], stack_r=base["stackR"])


def shade(color, amount):
    rgb = [int(color[i:i+2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(v + (255-v)*amount) if amount >= 0 else round(v*(1+amount)):02x}" for v in rgb)


def mat_hex(name):
    red, green, blue = MATERIALS[name]
    return "#" + "".join(f"{round(channel * 255):02x}" for channel in (red, green, blue))


def design_for(spec, catalog):
    extra = EXTRAS.get(spec["id"])
    if extra is None:
        raise ValueError(f"Missing chart design cues for {spec['id']}")
    entry = catalog.get(spec["id"], {})
    hull = entry.get("hull_material") or extra.get("hull")
    deck = entry.get("deck_material") or extra.get("deck")
    trim = entry.get("trim_material") or extra.get("trim")
    if not hull or not deck or not trim:
        raise ValueError(f"Missing hull material for {spec['id']}")
    return dict(hull=hull, deck=deck, trim=trim, house=extra["house"], engine=extra["engine"],
                funnels=extra["funnels"], courses=extra["courses"], foil=extra["foil"], split=extra["split"])


def palette(design):
    """Same keys the chart consumer reads. Values follow the battle materials."""
    return dict(hull=mat_hex(design["hull"]), deck=mat_hex(design["deck"]), cabin=mat_hex(design["house"]),
                brass=mat_hex("brass"), dark=mat_hex("seam"), steel=mat_hex("steel"), glass=mat_hex("glass"))


def n(value):
    return f"{value:.5f}".rstrip("0").rstrip(".") or "0"


class SVG:
    def __init__(self, bounds, title, density=144):
        self.bounds, self.title, self.parts, self.density = bounds, title, [], density

    def path(self, path, fill="none", stroke=None, width=.012, extra=""):
        attrs = f' stroke="{stroke}" stroke-width="{n(width)}"' if stroke else ""
        self.parts.append(f'<path d="{path}" fill="{fill}"{attrs} stroke-linejoin="round" stroke-linecap="round" {extra}/>')

    def poly(self, points, fill, stroke=None, width=.012):
        self.path("M" + " L".join(f"{n(x)},{n(y)}" for x, y in points) + " Z", fill, stroke, width)

    def line(self, a, b, color, width=.012):
        self.path(f"M{n(a[0])},{n(a[1])} L{n(b[0])},{n(b[1])}", stroke=color, width=width)

    def rect(self, x, y, length, width, fill, stroke=None, radius=.02, pen=.012):
        attrs = f' stroke="{stroke}" stroke-width="{n(pen)}"' if stroke else ""
        self.parts.append(f'<rect x="{n(x-length/2)}" y="{n(y-width/2)}" width="{n(length)}" height="{n(width)}" rx="{n(radius)}" fill="{fill}"{attrs}/>' )

    def circle(self, x, y, radius, fill, stroke=None, pen=.012):
        attrs = f' stroke="{stroke}" stroke-width="{n(pen)}"' if stroke else ""
        self.parts.append(f'<circle cx="{n(x)}" cy="{n(y)}" r="{n(radius)}" fill="{fill}"{attrs}/>' )

    def gradient(self, name, a, b, axis="y"):
        x2, y2 = ("0", "1") if axis == "y" else ("1", "0")
        self.parts.append(f'<defs><linearGradient id="{name}" x1="0" y1="0" x2="{x2}" y2="{y2}" gradientUnits="objectBoundingBox"><stop stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs>')
        return f"url(#{name})"

    def save(self, path):
        x, y, width, height = self.bounds
        pixels = [math.ceil(width*self.density), math.ceil(height*self.density)]
        source = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{pixels[0]}" height="{pixels[1]}" viewBox="{n(x)} {n(y)} {n(width)} {n(height)}">\n'
                  f'<title>{html.escape(self.title)}</title>\n' + "\n".join(self.parts) + "\n</svg>\n")
        ET.fromstring(source)  # Finite serialization guard in the generation pass.
        path.write_text(source, encoding="utf-8", newline="\n")
        return pixels, hashlib.sha256(source.encode()).hexdigest()


def width_at(stations, x):
    if x <= stations[0][0]:
        return stations[0][1]
    for a, b in zip(stations, stations[1:]):
        if a[0] <= x <= b[0]:
            return a[1] + (b[1]-a[1])*(x-a[0])/(b[0]-a[0])
    return stations[-1][1]


def hull_path(stations, offset=0, xs=1, ys=1):
    # Exact stations, smooth tangent at each station; no isometric projection.
    points = [(x*xs, offset-y*ys) for x, y in stations]
    points += [(x*xs, offset+y*ys) for x, y in reversed(stations[:-1])]
    # Quadratic fillets preserve the pointed stem and square transom ends.
    path = f"M{n(points[0][0])},{n(points[0][1])}"
    for i in range(1, len(points)):
        point = points[i]
        previous = points[i-1]
        following = points[min(i+1, len(points)-1)]
        if i in (len(stations)-1, len(points)-1):
            path += f" L{n(point[0])},{n(point[1])}"
        else:
            before = tuple(point[j]*.84 + previous[j]*.16 for j in (0, 1))
            after = tuple(point[j]*.84 + following[j]*.16 for j in (0, 1))
            path += f" L{n(before[0])},{n(before[1])} Q{n(point[0])},{n(point[1])} {n(after[0])},{n(after[1])}"
    return path + " Z"


def overlaps(a, b, gap=.025):
    return abs(a["x"]-b["x"]) < (a["len"]+b["len"])/2+gap and abs(a["y"]-b["y"]) < (a["wid"]+b["wid"])/2+gap


def clear(item, sockets):
    for socket in sockets:
        dx = max(0, abs(socket["x"]-item["x"])-item["len"]/2)
        dy = max(0, abs(socket["y"]-item["y"])-item["wid"]/2)
        if math.hypot(dx, dy)-socket["radius"] < .025:
            return False
    return True


def supported(item, stations, cat):
    for dx in (-.5, .5):
        for dy in (-.5, .5):
            x, y = item["x"] + dx*item["len"], item["y"] + dy*item["wid"]
            if cat and -1.8 <= x <= 1.45 and abs(y) <= .62:
                continue
            if cat:
                y = abs(y)-.62
            if x/.94 < stations[0][0] or x/.94 > stations[-1][0] or abs(y) > width_at(stations, x/.94)*.84:
                return False
    return True


def item_art(svg, item, colors):
    x, y, length, width = (item[key] for key in ("x", "y", "len", "wid"))
    kind = item["kind"]
    dark, brass = colors["dark"], colors["brass"]
    if ("mast" in kind or "davit" in kind or "post" in kind) and "searchlight" not in kind:
        svg.rect(x, y, length, width, colors["hull"], dark)
        svg.line((x-length*.3, y), (x+length*.28, y), brass, .023)
        svg.circle(x, y, min(length, width)*.22, colors["steel"])
    elif "tank" in kind or kind.startswith("cargo_drum") or ("oil" in kind and "cask" in kind):
        # Horizontal storage reads as a tank, not a weapon-well ring.
        svg.rect(x, y, length, width, shade(colors["steel"], .22), dark, min(length, width)*.46)
        for band in (-.22, .22):
            svg.line((x+length*band, y-width*.48), (x+length*band, y+width*.48), brass, .012)
        svg.circle(x, y, min(length, width)*.16, colors["cabin"], dark, .008)
    elif "coil" in kind or "reel" in kind or "drum" in kind or "cask" in kind:
        radius = min(length, width)*.45
        svg.rect(x, y, length, width, shade(colors["deck"], -.3), dark, .025)
        svg.circle(x, y, radius, colors["steel"] if "drum" in kind or "cask" in kind else brass, dark)
        svg.circle(x, y, radius*.62, "none", dark, .009)
        svg.circle(x+.015, y, radius*.18, dark)
        if "reel" in kind:
            svg.line((x-length*.43, y), (x+length*.43, y), colors["steel"], .022)
    elif "tarp" in kind or "bale" in kind or "pannier" in kind:
        svg.rect(x+.025, y+.025, length, width, shade(dark, .15), radius=.025)
        svg.rect(x, y, length, width, "#899a7c", dark)
        svg.line((x-length*.46, y), (x+length*.46, y), "#b9bea0", .014)
        for side in (-.27, .27):
            svg.line((x+length*side, y-width*.47), (x+length*side, y+width*.47), brass, .014)
    elif "manifold" in kind:
        svg.rect(x, y, length, width, shade(colors["hull"], -.12), dark)
        for offset in (-.22, 0, .22):
            svg.circle(x+length*offset, y, width*.22, "#b78c5f", dark, .008)
        svg.line((x-length*.45, y), (x+length*.45, y), colors["steel"], .018)
    elif "sun_deck" in kind:
        svg.rect(x, y, length, width, brass, dark)
        for offset in (-.28, 0, .28):
            svg.rect(x, y+width*offset, length*.8, width*.23, "#eee5c9", pen=.006)
    elif any(word in kind for word in ("fender", "cheek", "strake", "belt", "glacis", "breakwater", "sponson")):
        svg.rect(x, y, length, max(width, .08), shade(colors["hull"], -.18), dark, .02)
        svg.line((x-length*.42, y), (x+length*.42, y), brass, .011)
    elif any(word in kind for word in ("step", "vane", "foil", "skeg")):
        svg.poly([(x-length*.42, y), (x+length*.46, y-width*.42), (x+length*.46, y+width*.42)],
                 shade(colors["steel"], -.1), dark, .01)
    elif "searchlight" in kind or kind.endswith("lamp"):
        svg.circle(x, y, min(length, width)*.40, brass, dark, .01)
        svg.circle(x+length*.18, y, min(length, width)*.20, colors["glass"])
    else:
        paint = colors["hull"] if any(word in kind for word in ("hatch", "locker", "chest", "box", "safe", "hoppers")) else shade(colors["deck"], -.17)
        svg.rect(x+.022, y+.022, length, width, dark)
        svg.rect(x, y, length, width, shade(paint, .18), dark, .016)
        svg.rect(x, y, length*.72, width*.64, paint, shade(paint, .48), .009, .007)
        svg.line((x-length*.18, y), (x+length*.18, y), brass, .014)


def drive_plan(spec, stations, cat):
    """Stock stern count from campaign_fleet_art054. The fitted sprite still composites."""
    size, role, hull_id, tier = spec["size"], spec["role"], spec["id"], spec["tier"]
    small = size <= 18.5
    nozzle_ids = {"hook_raider", "aegis_corvette", "krill_torpedo", "manta_strike", "cinder_monitor", "wraith_rocket"}
    nozzle = role in ("torpedo", "rocket") or hull_id in nozzle_ids
    family = "outboard" if small else "nozzle" if nozzle else "stern_drive"
    transom, beam = stations[0][0], max(.14, stations[0][1])
    if cat:
        ys = [-.62, .62]
    elif small and hull_id in ("bilge_punt", "marsh_dart"):
        ys = [0.0]
    elif (not small) and (size >= 28.5 or (tier >= 4 and size >= 24.0)):
        spread = clamp(beam * .55, .24, .35)
        ys = [-spread, 0.0, spread]
    else:
        spread = clamp(beam * .52, .17 if small else .22, .24 if small else .31)
        ys = [-spread, spread]
    return family, transom - (.16 if small else .19), ys


def stern_mark(svg, family, x, y, colors):
    # Cowling and a short guard inside the existing aft margin. No cast water shadow.
    svg.rect(x + .02, y, .20, .11, colors["dark"], radius=.018)
    body = colors["hull"] if family == "outboard" else colors["steel"]
    svg.rect(x, y, .18, .10, body, colors["dark"], .02, .008)
    for step in range(3):
        sx = x - .04 + step * .028
        svg.line((sx, y - .03), (sx, y + .03), colors["dark"], .005)
    svg.rect(x + .05, y, .028, .055, colors["brass"], radius=.006)
    if family == "nozzle":
        svg.circle(x - .11, y, .038, "none", colors["steel"], .01)
    elif family == "stern_drive":
        svg.line((x - .12, y - .035), (x - .12, y + .035), colors["brass"], .01)
        svg.circle(x - .145, y, .016, colors["brass"])
    else:
        svg.line((x - .115, y - .028), (x - .115, y + .028), colors["steel"], .012)
        svg.circle(x - .14, y, .014, colors["brass"])


def foil_marks(svg, stations, foil_x, cat, halfbeam, colors):
    beam = width_at(stations, foil_x)
    for offset in ([-.62, .62] if cat else [0]):
        for side in (-1, 1):
            inner = offset + side * beam * .70
            outer = offset + side * (beam + .05)
            limit = halfbeam + .07
            if abs(outer) > limit:
                outer = math.copysign(limit, outer)
            svg.poly([(foil_x - .12, inner), (foil_x + .08, inner), (foil_x + .04, outer), (foil_x - .16, outer)],
                     shade(colors["steel"], -.08), colors["dark"], .01)


def wheelhouse(svg, profile, cabin, colors, sockets):
    x, y, length, width = (cabin[key] for key in ("x", "y", "len", "wid"))
    style = profile["bridgeStyle"]
    svg.rect(x + .045, y + .045, length + .04, width + .04, shade(colors["dark"], .08), radius=.035)
    open_styles = ("open_windscreen", "scout_cowl", "stepped_cockpit", "low_stinger_hood")
    armor_styles = ("ironclad_casemate", "siege_citadel", "bastion_cupola", "pyre_bunker", "turtleback_conning", "sawtooth_cowl")
    if style in open_styles:
        svg.rect(x, y, length, width, colors["dark"], colors["brass"], .03)
        for side in (-.22, .22):
            svg.rect(x - length * .08, y + width * side, length * .28, width * .28, shade(colors["cabin"], -.08), colors["dark"], .02)
        if style == "stepped_cockpit":
            svg.rect(x - length * .28, y, length * .16, width * .70, shade(colors["cabin"], .1), colors["dark"], .02)
        front = .18 if style == "low_stinger_hood" else .42
        svg.poly([(x + length * front, -width * .46), (x + length * .48, -width * .50),
                  (x + length * .48, width * .50), (x + length * front, width * .46)],
                 colors["glass"], colors["brass"], .012)
        svg.circle(x + length * .05, width * .16, .05, "none", colors["brass"], .014)
        if style == "scout_cowl":
            svg.rect(x + length * .22, y, length * .16, width * .55, shade(colors["hull"], -.2), colors["brass"], .02)
        return
    roof_fill = svg.gradient("roof", shade(colors["cabin"], .18), shade(colors["cabin"], -.16))
    front = .28 if any(word in style for word in ("canopy", "hood", "interceptor")) else .43
    roof = [(x - length * .48, -width * .48), (x + length * front, -width * .43), (x + length * .50, -width * .26),
            (x + length * .50, width * .26), (x + length * front, width * .43), (x - length * .48, width * .48)]
    svg.poly(roof, roof_fill, colors["dark"], .022)
    if style in armor_styles:
        svg.rect(x, y, length * .72, width * .55, shade(colors["cabin"], -.12), colors["dark"], .02)
        svg.line((x + length * .40, -width * .12), (x + length * .40, width * .12), colors["glass"], .02)
        if style == "bastion_cupola":
            svg.circle(x - length * .08, y, min(length, width) * .22, shade(colors["steel"], .1), colors["dark"], .012)
        if style in ("siege_citadel", "turtleback_conning"):
            for side in (-1, 1):
                svg.line((x - length * .2, side * width * .30), (x + length * .15, side * width * .30), colors["dark"], .016)
    else:
        for side in (-1, 1):
            svg.poly([(x - length * .34, side * width * .38), (x + length * .28, side * width * .35),
                      (x + length * .36, side * width * .24), (x - length * .34, side * width * .27)],
                     colors["glass"], colors["dark"], .010)
            for offset in (-.18, 0, .18):
                svg.line((x + length * offset, side * width * .24), (x + length * offset, side * width * .38), colors["brass"], .008)
        svg.line((x + length * .44, -width * .23), (x + length * .44, width * .23), shade(colors["glass"], .45), .022)
        svg.rect(x - length * .08, y, length * .22, width * .28, shade(colors["cabin"], .12), colors["brass"], .01)
        if style in ("packet_house", "commodore_tower", "flagship_citadel", "throne_pagoda", "hellbore_fire_tower"):
            svg.rect(x - length * .06, y, length * .48, width * .62, shade(colors["cabin"], .22), colors["dark"], .016)
            svg.rect(x - length * .02, y, length * .28, width * .36, shade(colors["steel"], .15), colors["brass"], .01)
        if style == "rangefinder_bridge":
            # Stay inside the cabin footprint so the bar cannot cover a side well.
            svg.rect(x, y, length * .62, width * .18, colors["steel"], colors["dark"], .02)
            svg.circle(x, -width * .08, .028, colors["glass"])
            svg.circle(x, width * .08, .028, colors["glass"])
        if style == "manta_command_fin":
            fin = dict(x=x - length * .15, y=0, len=length * .40, wid=.06)
            if clear(fin, sockets):
                svg.rect(fin["x"], 0, fin["len"], fin["wid"], colors["hull"], colors["brass"], .01)
        if profile.get("bridge", {}).get("visor") == "searchlight_brow":
            lamp = dict(x=x + length * .36, y=0, len=.12, wid=.12)
            if clear(lamp, sockets):
                svg.circle(lamp["x"], 0, .05, colors["brass"], colors["dark"], .01)
                svg.circle(lamp["x"] + .03, 0, .025, colors["glass"])
    svg.line((x - length * .38, -width * .38), (x - length * .38, width * .38), shade(colors["cabin"], .36), .014)


def boat_art(spec, profile, roles, catalog):
    stations, design = profile["stations"], design_for(spec, catalog)
    colors = palette(design)
    ch = chassis(spec, roles)
    halfbeam = max(point[1] for point in stations) + (.62 if ch["cat"] else 0)
    # Includes physical drives and a narrow transparent antialiasing margin.
    bounds = [stations[0][0]-.49, -halfbeam-.085, stations[-1][0]-stations[0][0]+.57, halfbeam*2+.17]
    svg = SVG(bounds, spec["name"] + " — original top-down chart hull; weapons fitted separately")
    hull_fill = svg.gradient("paint", shade(colors["hull"], .30), shade(colors["hull"], -.18))
    deck_fill = svg.gradient("deck", shade(colors["deck"], .15), shade(colors["deck"], -.12))
    trim = mat_hex(design["trim"])
    offsets = [-.62, .62] if ch["cat"] else [0]
    steel_deck = design["deck"] in ("tin", "armor", "armor_light", "machinery")
    for offset in offsets:
        svg.path(hull_path(stations, offset), hull_fill, colors["dark"], .045)
        svg.path(hull_path(stations, offset, .966, .89), deck_fill, colors["brass"], .022)
        # Each plank/plate seam stops at the real sheer. No SVG clipping/filter.
        start, end = stations[0][0]*.94, stations[-1][0]*.94
        for row in range(-5, 6):
            y = row*.095
            samples = [start+(end-start)*i/80 for i in range(81)]
            inside = [x for x in samples if abs(y) < width_at(stations, x/.94)*.82-.018]
            if inside:
                svg.line((inside[0], offset+y), (inside[-1], offset+y), shade(colors["deck"], -.30), .007 if not steel_deck else .009)
                if not steel_deck:
                    svg.line((inside[0], offset+y+.014), (inside[-1], offset+y+.014), shade(colors["deck"], .18), .005)
        for i in range(1, 12):
            x = start+(end-start)*i/13
            w = width_at(stations, x/.94)*.80
            if steel_deck:
                svg.line((x, offset-w), (x, offset+w), shade(colors["deck"], -.32), .010)
            else:
                # Staggered butt ends read as laid timber when viewed close.
                y = ((i % 5)-2)*.095
                if abs(y)+.095 < w:
                    svg.line((x, offset+y), (x, offset+y+.085), shade(colors["deck"], -.38), .009)
        for side in (-1, 1):
            rail = [(x*.94, offset+side*w*.92) for x, w in stations]
            svg.path("M"+" L".join(f"{n(x)},{n(y)}" for x, y in rail), stroke=trim, width=.016)
            for x, w in stations[:-1]:
                svg.circle(x*.94, offset+side*w*.92, .016, colors["brass"], colors["dark"], .006)
            for course in range(design["courses"]):
                inset = .84 - course * .035
                belt = [(x*.94, offset+side*w*inset) for x, w in stations]
                svg.path("M"+" L".join(f"{n(px)},{n(py)}" for px, py in belt), stroke=shade(colors["hull"], .42 - course * .12), width=.012)
        # Light and dark sheer lines define an actual hull against chart water.
        svg.path("M"+" L".join(f"{n(x)},{n(offset-w)}" for x, w in stations), stroke=shade(colors["hull"], .52), width=.020)
        svg.line((stations[0][0]+.025, offset-stations[0][1]*.85), (stations[0][0]+.025, offset+stations[0][1]*.85), colors["brass"], .024)
    if ch["cat"]:
        svg.rect(-.175, 0, 3.25, 1.24, hull_fill, colors["dark"], .025, .023)
        svg.rect(-.175, 0, 3.14, 1.10, deck_fill, colors["brass"], .02)
        for y in (-.42, -.21, 0, .21, .42):
            svg.line((-1.69, y), (1.31, y), shade(colors["deck"], -.30), .010)
        for x in (-1.70, -.78, .15, 1.31):
            svg.rect(x, 0, .07, 1.34, hull_fill, colors["dark"], .005)
    if design["foil"] is not None:
        foil_marks(svg, stations, design["foil"], ch["cat"], halfbeam, colors)
    items = []
    for item in profile["accents"] + profile["cargo"]:
        if item["kind"] == "outboard_pair" or not clear(item, ch["sockets"]):
            continue
        if spec.get("civilianRole") and (not supported(item, stations, ch["cat"]) or overlaps(item, ch["cabin"]) or overlaps(item, ch["engine"])):
            continue
        item_art(svg, item, colors)
        items.append(item)
    hatch = dict(kind="access_hatch", x=.25, y=0, len=.26, wid=.30)
    if clear(hatch, ch["sockets"]) and supported(hatch, stations, ch["cat"]) and not any(overlaps(hatch, solid) for solid in items+[ch["cabin"], ch["engine"]]):
        item_art(svg, hatch, colors)
    # Machinery housing stays at the real chassis engine footprint.
    engine = ch["engine"]
    ex, ey, el, ew = (engine[key] for key in ("x", "y", "len", "wid"))
    engine_paint = mat_hex(design["engine"])
    svg.rect(ex+.03, ey+.03, el+.04, ew+.03, colors["dark"])
    svg.rect(ex, ey, el, ew, engine_paint, colors["dark"])
    if design["split"]:
        svg.line((ex-el*.46, ey), (ex+el*.46, ey), colors["dark"], .012)
    for i in range(5):
        x = ex-el*.34+el*.17*i
        svg.line((x, ey-ew*.37), (x, ey+ew*.37), colors["steel"], .015)
    for side in (-1, 1):
        svg.line((ex-el*.40, ey+side*ew*.42), (ex+el*.32, ey+side*ew*.42), colors["brass"], .01)
    if spec["id"] == "gale_cutter":
        svg.line((ex-el*.15, ey-ew*.4), (ex-el*.15, ey+ew*.4), colors["brass"], .016)
    for sy, mat_name in design["funnels"]:
        stack = dict(x=ex-.02, y=sy, len=ch["stack_r"]*2.4, wid=ch["stack_r"]*2.4)
        if clear(stack, ch["sockets"]) and not overlaps(stack, ch["cabin"]):
            svg.circle(stack["x"], sy, ch["stack_r"], mat_hex(mat_name), colors["dark"], .015)
            svg.circle(stack["x"], sy, ch["stack_r"]*.60, colors["dark"])
    family, drive_x, drive_ys = drive_plan(spec, stations, ch["cat"])
    for drive_y in drive_ys:
        stern_mark(svg, family, drive_x, drive_y, colors)
    # Socket wells are empty infrastructure; only runtime fittings add weapons.
    for socket in ch["sockets"]:
        x, y, r = socket["x"], socket["y"], socket["radius"]
        svg.circle(x, y, r, shade(colors["hull"], .28), colors["dark"], .012)
        svg.circle(x, y, r*.72, shade(colors["deck"], -.25), colors["steel"], .008)
        for i in range(6):
            a = i*math.tau/6
            svg.circle(x+math.cos(a)*r*.87, y+math.sin(a)*r*.87, .009, colors["brass"])
    wheelhouse(svg, profile, ch["cabin"], colors, ch["sockets"])
    # Foredeck capstan and inset mooring cleats: no flags/people/extra guns.
    for side in (-1, 1):
        cleat = dict(x=stations[0][0]*.94+.14, y=side*(.62 if ch["cat"] else stations[0][1]*.58), len=.13, wid=.10)
        if clear(cleat, ch["sockets"]):
            svg.line((cleat["x"]-.05, cleat["y"]), (cleat["x"]+.05, cleat["y"]), colors["steel"], .024)
            svg.circle(cleat["x"], cleat["y"], .022, colors["brass"])
    bow_x = stations[-1][0]*.79
    capstan = dict(x=bow_x, y=0, len=.11, wid=.11)
    if not ch["cat"] and clear(capstan, ch["sockets"]) and supported(capstan, stations, False):
        svg.circle(bow_x, 0, .046, colors["dark"], colors["steel"], .012)
        svg.line((bow_x-.07, 0), (bow_x+.07, 0), colors["brass"], .020)
    pixels, digest = svg.save(OUT/(spec["id"]+".svg"))
    return dict(path="res://assets/campaign054/boats/"+spec["id"]+".svg", role=spec["role"],
                civilian_role=spec.get("civilianRole", ""), size=spec["size"], tier=spec["tier"],
                local_bounds=bounds, source_size=pixels, source_pivot=[-bounds[0]/bounds[2]*pixels[0], -bounds[1]/bounds[3]*pixels[1]],
                stations=stations, catamaran=ch["cat"], cabin=ch["cabin"], engine=ch["engine"],
                sockets=ch["sockets"], deck_items=items, palette=colors, sha256=digest)


def equipment_art():
    weapons = {}
    for variant in ("gun_single", "gun_twin", "cannon", "rocket_three", "rocket_six", "torpedo_single", "torpedo_twin"):
        kind = variant.split("_")[0]
        muzzle = dict(gun=8.8, cannon=14.2, rocket=5.9, torpedo=7.9)[kind]
        bounds = [-4.2, -4.8, muzzle+4.6, 9.6]
        svg = SVG(bounds, "Original top-down interchangeable " + variant.replace("_", " "), density=24)
        steel = svg.gradient("metal", "#c5d3ca", "#486168")
        paint = svg.gradient("paint", "#697f7d", "#344d52")
        svg.circle(0, 0, 3.2 if kind != "torpedo" else 2.5, "#22373b", "#ad9a6d", .25)
        if kind in ("gun", "cannon"):
            offsets = [-.75, .75] if variant == "gun_twin" else [0]
            for y in offsets:
                svg.rect((muzzle+1.2)/2, y, muzzle-1.2, .70 if kind == "gun" else 1.15, steel, "#183036", .15, .19)
                svg.line((muzzle, y-.48), (muzzle, y+.48), "#182b30", .38)
            svg.poly([(-3,-2.8),(1.8,-2.8),(3,-1.8),(3,1.8),(1.8,2.8),(-3,2.8)], paint, "#172e34", .25)
            svg.rect(-.2, 0, 3.2, 3.2, "#7d918a", "#bdc9bc", .25, .16)
            svg.circle(-.8, 0, .65, "#354f54", "#b8a26a", .18)
        else:
            count = 6 if variant == "rocket_six" else 3 if kind == "rocket" else 2 if variant == "torpedo_twin" else 1
            for i in range(count):
                y = (i-(count-1)/2)*(1.1 if kind == "rocket" else 2.1)
                svg.rect((muzzle-2.7)/2, y, muzzle+2.7, .8 if kind == "rocket" else 1.65, paint, "#1d3439", .28, .16)
                svg.line((-2.0, y-.22), (muzzle-.7, y-.22), "#b6c7b7", .16)
                svg.line((muzzle, y-.30), (muzzle, y+.30), "#162c30", .35)
            svg.rect(-.8, 0, .6, min(7, count*1.3), "#a88c55", "#233c40", .1, .13)
        pixels, digest = svg.save(OUT/(variant+".svg"))
        weapons[variant] = dict(path="res://assets/campaign054/boats/"+variant+".svg", local_bounds=bounds, source_size=pixels, sha256=digest)
    motors = {}
    for kind in ("outboard", "stern_drive", "nozzle"):
        bounds = [-.23, -.12, .46, .24]
        svg = SVG(bounds, "Original top-down " + kind.replace("_", " "))
        svg.rect(0, 0, .34, .16, "#1c3034", "#13282e", .02, .008)
        if kind == "outboard":
            svg.rect(.01, 0, .28, .14, mat_hex("teal_light"), "#142b30", .03, .01)
            for x in (-.05, -.01, .03):
                svg.line((x, -.04), (x, .04), "#1c3034", .007)
            svg.rect(.07, 0, .045, .07, mat_hex("brass"), radius=.006)
            svg.line((-.15, -.03), (-.15, .03), mat_hex("steel"), .012)
            svg.circle(-.185, 0, .016, mat_hex("brass"))
        elif kind == "nozzle":
            svg.rect(.02, 0, .26, .13, mat_hex("armor_light"), "#142b30", .02, .01)
            svg.circle(-.12, 0, .05, "none", mat_hex("steel"), .012)
            svg.circle(-.12, 0, .026, mat_hex("seam"))
            svg.rect(.08, 0, .04, .06, mat_hex("brass"), radius=.006)
        else:
            metal = svg.gradient("metal", "#c5d0c8", "#3a5558")
            svg.rect(0, 0, .28, .14, metal, "#142b30", .025, .01)
            svg.rect(-.02, 0, .14, .09, mat_hex("machinery"), "#142b30", .015, .008)
            svg.line((-.15, -.045), (-.15, .045), mat_hex("brass"), .014)
            svg.circle(-.175, 0, .018, mat_hex("brass"), mat_hex("seam"), .006)
            svg.rect(.08, 0, .04, .07, mat_hex("steel"), radius=.006)
        pixels, digest = svg.save(OUT/("motor_"+kind+".svg"))
        motors[kind] = dict(path="res://assets/campaign054/boats/motor_"+kind+".svg", local_bounds=bounds, source_size=pixels, sha256=digest)
    return weapons, motors


def main():
    profiles_path = ROOT/"game/scripts/hull_profiles.gd"
    layout_path = ROOT/"game/scripts/mount_layout.gd"
    world_path = ROOT/"game/data/world.json"
    profiles, roles = literal(profiles_path, "_PROFILES"), literal(layout_path, "_ROLE_TABLE")
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8-sig"))
    specs = json.loads(world_path.read_text(encoding="utf-8-sig"))["HULLS"]
    if len(specs) != 36 or {spec["id"] for spec in specs} != set(profiles) or set(EXTRAS) != set(profiles):
        raise ValueError("Catalogue/profile identities must match all 36 canonical hulls")
    target = OUT.resolve()
    expected = (ROOT/"game/assets/campaign054/boats").resolve()
    if target != expected or ROOT.resolve() not in target.parents:
        raise ValueError("Output must remain in this checkout's campaign boats allowlist")
    OUT.mkdir(parents=True, exist_ok=True)
    hulls = {spec["id"]: boat_art(spec, profiles[spec["id"]], roles, catalog) for spec in specs}
    weapons, motors = equipment_art()
    inputs = [profiles_path, layout_path, world_path, CATALOG_PATH, ROOT/"game/scripts/boat_deck_detail.gd", ROOT/"game/scripts/motor_art.gd", Path(__file__)]
    manifest = dict(schema="brass-tide-campaign-boats054-v1", revision=REVISION,
                    projection="original-top-down-bow-positive-x", installed_weapons_baked=False,
                    input_sha256={str(path.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
                    hulls=hulls, weapons=weapons, motors=motors)
    (OUT/"asset-manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8", newline="\n")
    print(json.dumps(dict(status="SVG source generated; native import and Root visual review not run", hulls=len(hulls), weapons=len(weapons), motors=len(motors), output=str(OUT))))


if __name__ == "__main__":
    main()
