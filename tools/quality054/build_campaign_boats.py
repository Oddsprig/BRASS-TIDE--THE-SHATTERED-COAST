"""Original Brass Tide chart boats, authored as reproducible top-down SVGs.

CPU-only, Python standard library. No engine/import/render/dependencies. Reads
the canonical catalogue, HullProfiles and MountLayout without executing them.
Writes only game/assets/campaign054/boats. Root performs native import/review.
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
REVISION = "054-original-chart-boats-r1"


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


def palette(spec):
    hull, deck, cabin = {
        "compact": ("#315a60", "#aa8d61", "#d6c9a4"),
        "forge": ("#684d40", "#777e77", "#abb4ad"),
        "reed": ("#456b57", "#b19463", "#cfc7a5"),
        "raiders": ("#704c49", "#947758", "#c5a58a"),
    }[spec["faction"]]
    civilian = spec.get("civilianRole", "")
    if civilian == "fishing":
        hull, deck, cabin = "#416d62", "#b29465", "#e0d2a9"
    elif civilian == "transport":
        hull, deck, cabin = "#476a70", "#a38661", "#e1d4b3"
    elif civilian == "tanker":
        hull, deck, cabin = "#94614e", "#8d8373", "#e2d7bd"
    elif civilian == "yacht":
        hull, deck, cabin = "#dfdfcf", "#bd9a63", "#f3ebd8"
    elif spec.get("armor", 0) >= 10:
        deck = shade(hull, .23)
        cabin = shade(hull, .53)
    return dict(hull=hull, deck=deck, cabin=cabin, brass="#c9ae6f", dark="#182c30", steel="#a5b5af", glass="#4c929e")


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
    if "mast" in kind or "davit" in kind or "post" in kind:
        svg.rect(x, y, length, width, colors["hull"], dark)
        svg.line((x-length*.3, y), (x+length*.28, y), brass, .023)
        svg.circle(x, y, min(length, width)*.22, colors["steel"])
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
    else:
        paint = colors["hull"] if any(word in kind for word in ("hatch", "locker", "chest", "box", "safe", "hoppers")) else shade(colors["deck"], -.17)
        svg.rect(x+.022, y+.022, length, width, dark)
        svg.rect(x, y, length, width, shade(paint, .18), dark, .016)
        svg.rect(x, y, length*.72, width*.64, paint, shade(paint, .48), .009, .007)
        svg.line((x-length*.18, y), (x+length*.18, y), brass, .014)


def boat_art(spec, profile, roles):
    stations, colors = profile["stations"], palette(spec)
    ch = chassis(spec, roles)
    halfbeam = max(point[1] for point in stations) + (.62 if ch["cat"] else 0)
    # Includes physical drives and a narrow transparent antialiasing margin.
    bounds = [stations[0][0]-.49, -halfbeam-.085, stations[-1][0]-stations[0][0]+.57, halfbeam*2+.17]
    svg = SVG(bounds, spec["name"] + " — original top-down chart hull; weapons fitted separately")
    hull_fill = svg.gradient("paint", shade(colors["hull"], .30), shade(colors["hull"], -.18))
    deck_fill = svg.gradient("deck", shade(colors["deck"], .15), shade(colors["deck"], -.12))
    roof_fill = svg.gradient("roof", shade(colors["cabin"], .18), shade(colors["cabin"], -.16))
    offsets = [-.62, .62] if ch["cat"] else [0]
    steel_deck = not spec.get("civilianRole") and spec.get("armor", 0) >= 10
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
            svg.path("M"+" L".join(f"{n(x)},{n(y)}" for x, y in rail), stroke=shade(colors["cabin"], .15), width=.016)
            for x, w in stations[:-1]:
                svg.circle(x*.94, offset+side*w*.92, .016, colors["brass"], colors["dark"], .006)
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
    svg.rect(ex+.03, ey+.03, el+.04, ew+.03, colors["dark"])
    svg.rect(ex, ey, el, ew, hull_fill, colors["dark"])
    for i in range(5):
        x = ex-el*.34+el*.17*i
        svg.line((x, -ew*.37), (x, ew*.37), colors["steel"], .015)
    for i in range(ch["stacks"]):
        sy = ch["spread"] if ch["stacks"] == 1 and spec["role"] in ("cutter", "torpedo") else 0 if ch["stacks"] == 1 else (-ch["spread"] if i == 0 else ch["spread"])
        svg.circle(ex-.02, sy, ch["stack_r"], colors["steel"], colors["dark"], .015)
        svg.circle(ex-.02, sy, ch["stack_r"]*.60, colors["dark"])
    # Socket wells are empty infrastructure; only runtime fittings add weapons.
    for socket in ch["sockets"]:
        x, y, r = socket["x"], socket["y"], socket["radius"]
        svg.circle(x, y, r, shade(colors["hull"], .28), colors["dark"], .012)
        svg.circle(x, y, r*.72, shade(colors["deck"], -.25), colors["steel"], .008)
        for i in range(6):
            a = i*math.tau/6
            svg.circle(x+math.cos(a)*r*.87, y+math.sin(a)*r*.87, .009, colors["brass"])
    cabin = ch["cabin"]
    x, y, length, width = (cabin[key] for key in ("x", "y", "len", "wid"))
    style = profile["bridgeStyle"]
    svg.rect(x+.045, y+.045, length+.04, width+.04, shade(colors["dark"], .08), radius=.035)
    if spec["role"] == "skiff" and not profile["bridge"].get("glass", False):
        svg.rect(x, y, length, width, colors["cabin"], colors["dark"], .035)
        svg.rect(x, y, length*.80, width*.74, colors["dark"], colors["brass"], .02)
        svg.rect(x-length*.18, y, length*.18, width*.64, "#8b5e44", "#d1ad73", .016)
        svg.poly([(x+length*.30,-width*.42),(x+length*.47,-width*.48),(x+length*.47,width*.48),(x+length*.30,width*.42)], colors["glass"], "#afcec0", .012)
        svg.circle(x+length*.18, width*.18, .055, "none", colors["brass"], .016)
        svg.line((x+length*.14, width*.18), (x+length*.22, width*.18), colors["brass"], .009)
    else:
        front = .30 if any(word in style for word in ("canopy", "hood", "interceptor")) else .43
        roof = [(x-length*.48,-width*.48),(x+length*front,-width*.43),(x+length*.50,-width*.26),(x+length*.50,width*.26),(x+length*front,width*.43),(x-length*.48,width*.48)]
        svg.poly(roof, roof_fill, colors["dark"], .022)
        for side in (-1, 1):
            svg.poly([(x-length*.34,side*width*.38),(x+length*.28,side*width*.35),(x+length*.36,side*width*.24),(x-length*.34,side*width*.27)], colors["glass"], colors["dark"], .010)
        svg.line((x+length*.44,-width*.23), (x+length*.44,width*.23), "#b9e0da", .027)
        svg.rect(x-length*.10, 0, length*.46, width*.40, shade(colors["cabin"], .12), colors["brass"], .014)
        if any(word in style for word in ("citadel", "cupola", "bunker", "pagoda", "conning")):
            svg.rect(x-length*.10, 0, length*.25, width*.26, hull_fill, colors["dark"], .01)
            for side in (-1, 1):
                svg.line((x-length*.20,side*width*.28), (x+length*.12,side*width*.28), colors["dark"], .017)
        elif "yacht" in spec.get("civilianRole", ""):
            for i in range(4):
                svg.line((x-length*.22+i*length*.07,-width*.13), (x-length*.22+i*length*.07,width*.13), colors["brass"], .009)
        else:
            svg.circle(x-length*.13, 0, .055, colors["hull"], colors["brass"], .009)
        svg.line((x-length*.38,-width*.38), (x-length*.38,width*.38), shade(colors["cabin"], .36), .014)
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
        metal = svg.gradient("metal", "#a2b1a9", "#3f595c")
        svg.rect(0, 0, .41, .18, "#1c3034", "#13282e", .025, .012)
        svg.rect(.012, 0, .32, .16, metal, "#142b30", .035, .012)
        for x in (-.095, -.055, -.015, .025):
            svg.line((x,-.052), (x,.052), "#263f43", .012)
        svg.rect(.10, 0, .05, .11, "#bb995f", radius=.008)
        if kind == "nozzle":
            svg.rect(-.172, 0, .055, .12, "#13282f", "#a4b8ad", .014, .012)
        elif kind == "stern_drive":
            svg.line((-.21,-.08), (-.21,.08), "#bfbc98", .019)
        else:
            svg.line((-.21,-.055), (-.21,.055), "#bbad7a", .016)
        pixels, digest = svg.save(OUT/("motor_"+kind+".svg"))
        motors[kind] = dict(path="res://assets/campaign054/boats/motor_"+kind+".svg", local_bounds=bounds, source_size=pixels, sha256=digest)
    return weapons, motors


def main():
    profiles_path = ROOT/"game/scripts/hull_profiles.gd"
    layout_path = ROOT/"game/scripts/mount_layout.gd"
    world_path = ROOT/"game/data/world.json"
    profiles, roles = literal(profiles_path, "_PROFILES"), literal(layout_path, "_ROLE_TABLE")
    specs = json.loads(world_path.read_text(encoding="utf-8-sig"))["HULLS"]
    if len(specs) != 36 or {spec["id"] for spec in specs} != set(profiles):
        raise ValueError("Catalogue/profile identities must match all 36 canonical hulls")
    target = OUT.resolve()
    expected = (ROOT/"game/assets/campaign054/boats").resolve()
    if target != expected or ROOT.resolve() not in target.parents:
        raise ValueError("Output must remain in this checkout's campaign boats allowlist")
    OUT.mkdir(parents=True, exist_ok=True)
    hulls = {spec["id"]: boat_art(spec, profiles[spec["id"]], roles) for spec in specs}
    weapons, motors = equipment_art()
    inputs = [profiles_path, layout_path, world_path, ROOT/"game/scripts/boat_deck_detail.gd", ROOT/"game/scripts/motor_art.gd", Path(__file__)]
    manifest = dict(schema="brass-tide-campaign-boats054-v1", revision=REVISION,
                    projection="original-top-down-bow-positive-x", installed_weapons_baked=False,
                    input_sha256={str(path.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
                    hulls=hulls, weapons=weapons, motors=motors)
    (OUT/"asset-manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8", newline="\n")
    print(json.dumps(dict(status="SVG source generated; native import and Root visual review not run", hulls=len(hulls), weapons=len(weapons), motors=len(motors), output=str(OUT))))


if __name__ == "__main__":
    main()
