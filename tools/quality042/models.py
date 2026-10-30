"""Original 0.042 boat models. Pure model source; importing never bakes assets.

Coordinates are *physical world units*: +X bow, +Y starboard, +Z elevation.
Only Hull.p() scales hull-local XY. Height is deliberately never size-scaled.
No installed weapons are authored here. Socket rings end at MountLayout elevation.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from math import cos, sin, pi, sqrt

TAU = 2 * pi
REVISION = "073-authored-hulls-r1"


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(a):
    return mul(a, 1 / max(1e-12, sqrt(sum(x*x for x in a))))


@dataclass(frozen=True)
class Material:
    color: tuple
    roughness: float = .5
    metallic: float = .0
    texture: str = "paint"


# Restrained common dockyard palette. Colors are sRGB; renderer linearizes them.
MATERIALS = {
    "tin": Material((.52, .62, .63), .34, .65, "metal"),
    "teal": Material((.09, .29, .29), .43, .18),
    "teal_light": Material((.22, .45, .43), .44, .12),
    "ivory": Material((.78, .76, .62), .56, .05),
    "armor": Material((.22, .27, .28), .4, .55, "metal"),
    "armor_light": Material((.37, .42, .42), .34, .6, "metal"),
    "oxide": Material((.52, .18, .095), .64, .12),
    "brass": Material((.64, .43, .17), .28, .78, "metal"),
    "brass_light": Material((.83, .64, .31), .24, .7, "metal"),
    "timber": Material((.43, .27, .13), .68, .0, "wood"),
    "deck": Material((.56, .43, .27), .72, .0, "wood"),
    "seam": Material((.13, .16, .15), .8),
    "rubber": Material((.045, .058, .055), .88),
    "machinery": Material((.16, .21, .20), .39, .55, "metal"),
    "steel": Material((.52, .57, .56), .24, .8, "metal"),
    "glass": Material((.10, .30, .34), .12, .62, "glass"),
    "glass_edge": Material((.42, .66, .68), .2, .45, "glass"),
    "canvas": Material((.42, .47, .31), .85, .0, "fabric"),
    "rope": Material((.59, .50, .32), .95, .0, "rope"),
    "lamp": Material((.95, .77, .35), .28, .12),
    "red": Material((.58, .12, .08), .45, .15),
}


@dataclass
class Part:
    name: str
    material: str
    vertices: list = field(default_factory=list)
    normals: list = field(default_factory=list)
    faces: list = field(default_factory=list)

    def quad(self, indices):
        a, b, c, d = indices
        self.faces.extend(((a, b, c), (a, c, d)))


@dataclass
class Model:
    hull_id: str
    size: float
    parts: list = field(default_factory=list)
    sockets: list = field(default_factory=list)

    def part(self, name, material):
        p = Part(name, material)
        self.parts.append(p)
        return p

    def p(self, x, y, z):
        return (x*self.size, y*self.size, z)


def tube(m, name, points, radius, mat="steel", sides=8, closed=False):
    """Solid round rails, pipes, ropes; parallel frame avoids caps through corners."""
    p = m.part(name, mat)
    count = len(points)
    for i, pos in enumerate(points):
        prev = points[(i-1) % count] if closed or i else points[0]
        nxt = points[(i+1) % count] if closed or i < count-1 else points[-1]
        tangent = unit(sub(nxt, prev))
        side = unit(cross(tangent, (0, 0, 1) if abs(tangent[2]) < .95 else (0, 1, 0)))
        up = cross(side, tangent)
        for j in range(sides):
            n = add(mul(side, cos(TAU*j/sides)), mul(up, sin(TAU*j/sides)))
            p.vertices.append(add(pos, mul(n, radius)))
            p.normals.append(n)
    for i in range(count if closed else count-1):
        for j in range(sides):
            a, b = i*sides+j, i*sides+(j+1) % sides
            c, d = ((i+1) % count)*sides+(j+1) % sides, ((i+1) % count)*sides+j
            # Correct winding by the explicit radial normals, independent of frame sign.
            ids = [a, b, c, d]
            if sum(x*y for x, y in zip(cross(sub(p.vertices[b], p.vertices[a]), sub(p.vertices[c], p.vertices[a])), p.normals[a])) < 0:
                ids.reverse()
            p.quad(ids)
    if not closed:
        for base, reverse in ((0, True), ((count-1)*sides, False)):
            for j in range(1, sides-1):
                ids = (base, base+j, base+j+1)
                p.faces.append(tuple(reversed(ids)) if reverse else ids)
    return p


def lathe(m, name, center, profile, mat, segments=24):
    """Z-axis turned fitting; profile is (radius,height), bottom to top."""
    p = m.part(name, mat)
    for i, (r, z) in enumerate(profile):
        lo, hi = profile[max(0, i-1)], profile[min(len(profile)-1, i+1)]
        dr, dz = hi[0]-lo[0], hi[1]-lo[1]
        for j in range(segments):
            t = TAU*j/segments
            p.vertices.append(add(center, (r*cos(t), r*sin(t), z)))
            p.normals.append(unit((dz*cos(t), dz*sin(t), -dr)))
    for i in range(len(profile)-1):
        for j in range(segments):
            p.quad((i*segments+j, i*segments+(j+1) % segments,
                    (i+1)*segments+(j+1) % segments, (i+1)*segments+j))
    return p


def box(m, name, center, dimensions, mat, bevel=.25, yaw=0):
    """True round bevel with explicit flat-face and curved-edge vertex normals."""
    p = m.part(name, mat)
    hx, hy, hz = (d*.5 for d in dimensions)
    b = min(bevel, hx*.45, hy*.45, hz*.45)
    # Rounded rectangular rings sweep the lower fillet, wall and upper fillet.
    layers = [(b-hz, -pi/2), (b-hz, -pi/4), (b-hz, 0),
              (hz-b, 0), (hz-b, pi/4), (hz-b, pi/2)]
    corners = ((1, 1, 0), (-1, 1, pi/2), (-1, -1, pi), (1, -1, 3*pi/2))
    for zc, phi in layers:
        for sx, sy, start in corners:
            for j in range(4):
                t = start + j*pi/6
                nx, ny, nz = cos(t)*cos(phi), sin(t)*cos(phi), sin(phi)
                x, y, z = sx*(hx-b)+b*nx, sy*(hy-b)+b*ny, zc+b*nz
                p.vertices.append(add(center, (x*cos(yaw)-y*sin(yaw), x*sin(yaw)+y*cos(yaw), z)))
                p.normals.append((nx*cos(yaw)-ny*sin(yaw), nx*sin(yaw)+ny*cos(yaw), nz))
    n = 16
    for i in range(len(layers)-1):
        for j in range(n):
            p.quad((i*n+j, i*n+(j+1) % n, (i+1)*n+(j+1) % n, (i+1)*n+j))
    # Bottom/top faces; all boundary normals are +/-Z on these rings.
    for base, rev in ((0, True), (5*n, False)):
        for j in range(1, n-1):
            ids = (base, base+j, base+j+1)
            p.faces.append(tuple(reversed(ids)) if rev else ids)
    return p


def width_at(stations, x):
    """C1 cubic Hermite hull sheer with bounded, nonnegative half-beams."""
    if x <= stations[0][0]:
        return stations[0][1]
    if x >= stations[-1][0]:
        return stations[-1][1]
    for i in range(len(stations)-1):
        a, b = stations[i], stations[i+1]
        if a[0] <= x <= b[0]:
            prev, nxt = stations[max(0, i-1)], stations[min(len(stations)-1, i+2)]
            d = b[0]-a[0]
            t = (x-a[0])/d
            da = (b[1]-prev[1])/(b[0]-prev[0])
            db = (nxt[1]-a[1])/(nxt[0]-a[0])
            return max(.002, min(max(a[1], b[1])+.01,
                (2*t**3-3*t*t+1)*a[1]+(t**3-2*t*t+t)*d*da
                +(-2*t**3+3*t*t)*b[1]+(t**3-t*t)*d*db))
    raise ValueError(x)


def hull_shell(m, name, stations, offset, deck_z, mat, stripe="brass", samples=56, bow_rise=0.0):
    """Round-bilge hull at Z=0; optional local forefoot rise, same sheer and XY."""
    # Only explicitly selected light hulls lift their keel through the last
    # two station intervals. Default zero retains every other authored shell.
    def forefoot_at(x):
        span = stations[-1][0]-stations[-3][0]
        u = max(0.0, min(1.0, (x-stations[-3][0])/span))
        return bow_rise*u*u*(3-2*u), bow_rise*6*u*(1-u)/span

    p = m.part(name, mat)
    # Every transverse strip is curved, with 12 vertical samples per side.
    ring = 25
    for i in range(samples+1):
        x = stations[0][0]+(stations[-1][0]-stations[0][0])*i/samples
        w = width_at(stations, x)
        dx = .001
        dw = (width_at(stations, min(x+dx, stations[-1][0]))-width_at(stations, max(x-dx, stations[0][0])))/(2*dx)
        sheer = .45*(abs(x)/max(abs(stations[0][0]), stations[-1][0]))**3
        rise, rise_slope = forefoot_at(x)
        height = deck_z+sheer
        for j in range(ring):
            t = -pi/2 + pi*j/(ring-1)
            # Narrow visible waterline rising to a generously rounded topside.
            y = w*sin(t)
            curve = abs(sin(t))**1.6
            z = height*(rise+(1-rise)*curve)
            # Midbody keel stays at the waterline; the selected forefoot rises.
            p.vertices.append(m.p(x, offset+y, z))
            dt = .0001
            def sect(q):
                return (w*sin(q)*m.size, height*(rise+(1-rise)*abs(sin(q))**1.6))
            yl, zl = sect(t-dt)
            yh, zh = sect(t+dt)
            nx = -dw*sin(t)*(zh-zl)
            if rise > 0.0:
                # Longitudinal forefoot slope belongs in the surface normal.
                length = max(abs(stations[0][0]), stations[-1][0])
                sheer_slope = 1.35*x*abs(x)/length**3
                dzdx = (sheer_slope*(rise+(1-rise)*curve)
                        +height*rise_slope*(1-curve))/m.size
                nx += dzdx*(yh-yl)
            n = unit((nx, zh-zl, -(yh-yl)))
            p.normals.append(n)
    # A broad painted sheer uses the existing shell surface, not a larger hull.
    band = m.part(name+"_painted_sheer", stripe)
    edge_rows = tuple(range(5))+tuple(range(ring-5, ring))
    for i in range(samples+1):
        for j in edge_rows:
            band.vertices.append(p.vertices[i*ring+j])
            band.normals.append(p.normals[i*ring+j])
    for i in range(samples):
        for j in range(ring-1):
            # Parametric X / section orientation has outward winding.
            if 4 <= j < ring-5:
                p.quad((i*ring+j+1, (i+1)*ring+j+1, (i+1)*ring+j, i*ring+j))
        for side in (0, 5):
            for j in range(4):
                a = i*10+side+j
                band.quad((a+1, a+11, a+10, a))
    # Close stern transom with separate flat normals.
    for i, reverse in ((0, True), (samples, False)):
        verts = [p.vertices[i*ring+j] for j in range(ring)]
        verts += [m.p(stations[0 if i == 0 else -1][0], offset, deck_z)]
        flat = m.part(name+"_transom"+str(i), mat)
        flat.vertices = verts
        flat.normals = [(-1 if i == 0 else 1, 0, 0)]*len(verts)
        for j in range(ring-1):
            ids = (ring, j, j+1)
            flat.faces.append(tuple(reversed(ids)) if reverse else ids)
    # Fore/aft crowned continuous deck, with its own upward normal.
    d = m.part(name+"_deck", "deck")
    for i in range(samples+1):
        x = stations[0][0]+(stations[-1][0]-stations[0][0])*i/samples
        w = width_at(stations, x)
        for j in range(9):
            t = -1+j/4
            z = deck_z+.45*(abs(x)/max(abs(stations[0][0]), stations[-1][0]))**3+.35*(1-t*t)
            d.vertices.append(m.p(x, offset+w*t, z))
            d.normals.append(unit((0, .7*t/(max(w, .02)*m.size), 1)))
    for i in range(samples):
        for j in range(8):
            d.quad((i*9+j, (i+1)*9+j, (i+1)*9+j+1, i*9+j+1))
    # Inset waterways separate the working deck from the caprail at small zoom.
    for side in (-1, 1):
        margin = m.part(name+"_waterway_inlay"+str(side), stripe)
        for i in range(samples+1):
            x = stations[0][0]+(stations[-1][0]-stations[0][0])*i/samples
            w = width_at(stations, x)
            for t in (side*.74, side*.89):
                z = deck_z+.45*(abs(x)/max(abs(stations[0][0]), stations[-1][0]))**3+.35*(1-t*t)+.045
                margin.vertices.append(m.p(x, offset+w*t, z))
                margin.normals.append(unit((0, .7*t/(max(w, .02)*m.size), 1)))
        for i in range(samples):
            ids = (i*2, (i+1)*2, (i+1)*2+1, i*2+1)
            margin.quad(ids if side > 0 else tuple(reversed(ids)))
    for side in (-1, 1):
        pts = []
        belt = []
        for i in range(samples+1):
            x = stations[0][0]+(stations[-1][0]-stations[0][0])*i/samples
            w = width_at(stations, x)
            z = deck_z+.45*(abs(x)/max(abs(stations[0][0]), stations[-1][0]))**3
            pts.append(m.p(x, offset+side*w, z+.20))
            # Carry the existing strake with the lifted shell so no
            # unchanged low rail remains underneath the corrected bow.
            belt_z = deck_z*.65
            belt_z += (z-belt_z)*forefoot_at(x)[0]
            belt.append(m.p(x, offset+side*w*.96, belt_z))
        tube(m, name+"_caprail", pts, .30, stripe, 8)
        tube(m, name+"_rubbing_strake", belt, .32, "rubber", 8)


def godot_hash(s):
    """Godot String.hash(): 32-bit DJB2, signed before absi in MountLayout."""
    h = 5381
    for c in s:
        h = (h*33+ord(c)) & 0xffffffff
    return h if h < 0x80000000 else h-0x100000000


def sockets_for(hull_id, size, role, tier, faction):
    # Exact current MountLayout._ROLE_TABLE and _hull_variation, not art guesses.
    role_data = {
        "skiff": (.98, -1.48, .48, .42, 11.0),
        "cutter": (1.02, -1.49, .49, .42, 12.0),
        "torpedo": (1.04, -1.50, .50, .43, 12.0),
        "corvette": (1.02, -1.50, .50, .43, 11.5),
        "raider": (1.00, -1.48, .52, .56, 11.5),
        "gunboat": (1.00, -1.50, .49, .44, 12.5),
        "rocket": (1.01, -1.50, .50, .44, 12.0),
        "cruiser": (1.05, -1.52, .51, .44, 13.0),
    }
    bow, aft, side_x, side_y, h = role_data[role]
    f = {"forge": -.012, "reed": .014, "raiders": .008}.get(faction, 0)
    jitter = (abs(godot_hash(hull_id)) % 5-2)*.004
    step = (tier-2)*.010
    clamp = lambda n, a, b: max(a, min(b, n))
    primary = 1 if size < 19 else 2 if size < 27 else 3
    secondary = max(1, primary-1)
    items = [("mount0", clamp(bow+step+f+jitter, .96, 1.08), 0, h+.5, primary, 0),
             ("mount1", clamp(aft-step*.5+jitter, -1.53, -1.46), 0, h, secondary, pi)]
    sy = clamp(side_y+step*.4, .54 if role == "raider" else .42, .58 if role == "raider" else .445)
    sx = clamp(side_x+f*.8+jitter, .47, .53)
    if size >= 20:
        items.append(("mount2", sx, -sy, h, secondary, -pi/2))
    if size >= 28:
        items.append(("mount3", sx, sy, h, secondary, pi/2))
    result = []
    for mid, x, y, z, level, angle in items:
        side = mid in ("mount2", "mount3")
        r = (.14 if level <= 1 else .15) if side else (.16 if level <= 1 else .18 if level == 2 else .20)
        result.append({"id": mid, "local_xy": [x, y], "world_xy": [x*size, y*size],
                       "elevation": z, "size": level, "radius": r*size, "angle": angle})
    return result


def mounting_rings(m, deck_z):
    for s in m.sockets:
        x, y = s["world_xy"]
        r, top = s["radius"], s["elevation"]
        # Socket well is empty and flush at the physical mount plane.
        lathe(m, s["id"]+"_empty_socket", (x, y, 0),
              [(0, deck_z+.30), (r*.83, deck_z+.30), (r*.94, top-.32),
               (r, top-.12), (r*.98, top), (r*.77, top), (r*.75, top-.22)], "armor_light", 32)
        lathe(m, s["id"]+"_well", (x, y, 0), [(0, top-.22), (r*.75, top-.22)], "seam", 24)
        for j in range(8):
            a = TAU*j/8
            lathe(m, s["id"]+"_bolt", (x+cos(a)*r*.86, y+sin(a)*r*.86, top),
                  [(0, 0), (.15, 0), (.15, .10), (0, .15)], "brass", 6)


def railing(m, name, xs, side, width, z, mat="ivory", offset=0):
    # Fixed gaps at weapon decks; posts have a substantial visual thickness.
    pts = [m.p(x, offset+side*width(x), z) for x in xs]
    for k, pt in enumerate(pts):
        tube(m, name+"_post"+str(k), [add(pt, (0, 0, -2.7)), pt], .19, mat, 6)
    tube(m, name+"_top", pts, .23, mat, 8)
    tube(m, name+"_mid", [add(p, (0, 0, -1.45)) for p in pts], .14, "steel", 6)


def cleat(m, x, y, z, label="cleat"):
    c = m.p(x, y, z)
    box(m, label+"_base", c, (1.7, .8, .3), "armor", .12)
    tube(m, label+"_horns", [add(c, (-.8, 0, .7)), add(c, (.8, 0, .7))], .17, "steel", 8)
    tube(m, label+"_neck", [c, add(c, (0, 0, .7))], .2, "steel", 8)


def rope_coil(m, x, y, z, radius=1.4):
    c = m.p(x, y, z)
    pts = []
    for j in range(73):
        t = TAU*j/24
        r = max(.1, radius-.1)*(.3+.7*j/72)
        pts.append(add(c, (r*cos(t), r*sin(t), .10)))
    tube(m, "mooring_hawser", pts, .20, "rope", 6)


def hatch(m, x, y, z, length, width, mat="teal"):
    c = m.p(x, y, z)
    box(m, "hatch_coaming", c, (length*m.size, width*m.size, .8), "seam", .3)
    box(m, "hatch_lid", add(c, (0, 0, .55)), (length*m.size-.5, width*m.size-.5, .65), mat, .28)
    for side in (-1, 1):
        box(m, "hatch_hinge", add(c, (-length*m.size*.28, side*width*m.size*.43, .95)), (.8, .45, .32), "brass", .12)
    tube(m, "hatch_handle", [add(c, (.6, -.7, 1.0)), add(c, (.6, -.7, 1.4)),
                           add(c, (.6, .7, 1.4)), add(c, (.6, .7, 1.0))], .11, "steel", 6)


def ventilator(m, x, y, z, length=.40, width=.16, top=12.0, mat="ivory"):
    """Raised rectangular air trunk, with large dark slots and separate blades."""
    c = m.p(x,y,0)
    box(m,"vent_plinth",add(c,(0,0,z+.25)),(length*m.size,width*m.size,.5),"seam",.18)
    box(m,"vent_hood",add(c,(0,0,(z+.45+top)*.5)),
        (length*m.size*.94,width*m.size*.94,top-z-.45),mat,.3)
    box(m,"vent_dark_recess",add(c,(0,0,top-.13)),
        (length*m.size*.80,width*m.size*.72,.30),"seam",.10)
    for j in range(3):
        box(m,"vent_cross_blade",add(c,((j-1)*length*m.size*.25,0,top-.02)),
            (length*m.size*.10,width*m.size*.82,.24),"steel",.08)


def deck_windlass(m, x, y, z, length=.24, width=.28):
    """A transverse rope drum, cheeks and gearbox read as working deck gear."""
    c = m.p(x,y,z)
    box(m,"windlass_bed",add(c,(0,0,.22)),(length*m.size,width*m.size,.44),"teal",.18)
    radius = min(1.0,length*m.size*.30)
    axle_z = z+radius+.55
    for side in (-1,1):
        box(m,"windlass_cheek",m.p(x,y+side*width*.36,z+1.0),
            (length*m.size*.66,width*m.size*.12,1.8),"ivory",.2)
        points=[m.p(x+radius/m.size*cos(TAU*j/20),y+side*width*.26,
                    axle_z+radius*sin(TAU*j/20)) for j in range(20)]
        tube(m,"windlass_flange",points,.18,"brass",8,True)
    tube(m,"windlass_hawser_drum",[m.p(x,y-width*.22,axle_z),m.p(x,y+width*.22,axle_z)],
         radius*.70,"rope",12)
    box(m,"windlass_gearbox",m.p(x,y+width*.37,z+.9),
        (length*m.size*.62,width*m.size*.18,1.25),"machinery",.25)


def engine(m, x, y, z, length, width, top, mat="machinery"):
    c = m.p(x, y, (z+top)*.5)
    box(m, "diesel_crankcase", c, (length*m.size, width*m.size, top-z), mat, .6)
    box(m, "engine_cover_gasket", m.p(x,y,top-.08),
        (length*m.size*.94,width*m.size*.94,.24), "seam", .12)
    for side in (-1, 1):
        box(m, "split_rocker_cover", m.p(x,y+side*width*.24,top+.18),
            (length*m.size*.84,width*m.size*.36,.65), "armor_light", .24)
    for j in range(4):
        xx = x-length*.30+j*length*.20
        box(m, "cooling_louver", m.p(xx, y, top+.54),
            (length*m.size*.10,width*m.size*.76,.22), "seam", .07)
    for side in (-1, 1):
        box(m, "engine_radiator_face", m.p(x,y+side*width*.47,(z+top)*.5),
            (length*m.size*.72,.16,max(.5,(top-z)*.50)), "seam", .08)
        for j in range(3):
            box(m, "radiator_divider", m.p(x+length*(-.24+j*.24),y+side*width*.475,(z+top)*.5),
                (max(.25,length*m.size*.06),.17,max(.6,(top-z)*.54)), "steel", .07)
        tube(m, "coolant_manifold", [m.p(x-length*.4, y+side*width*.47, z+.6),
                                   m.p(x+length*.35, y+side*width*.47, z+.6)], .23, "brass", 8)
    tube(m, "engine_oil_filler", [m.p(x+length*.28,y,top-.1),m.p(x+length*.28,y,top+.64)], .32, "brass", 10)
    box(m, "engine_drive_belt", m.p(x+length*.46,y,(z+top)*.5),
        (.16,width*m.size*.64,max(.6,(top-z)*.64)), "rubber", .1)


def drive(m, transom, y, outboard=False):
    x = transom-.15
    box(m, "drive_bracket", m.p(transom-.02, y, 7.0), (1.5, 1.8, 3.4), "steel", .35)
    box(m, "sculpted_motor_cowling", m.p(x, y, 9.5), (3.6, 2.4, 4.7), "teal" if outboard else "machinery", .8)
    c = m.p(x,y,0)
    box(m, "motor_lower_gasket", add(c,(0,0,8.05)), (3.5,2.3,.34), "rubber", .13)
    box(m, "motor_raised_top", add(c,(0,0,11.50)), (3.0,2.1,.55), "ivory" if outboard else "armor_light", .25)
    for side in (-1,1):
        box(m, "motor_side_flash", add(c,(0,side*1.15,10.1)), (2.5,.08,.62), "ivory", .13)
        box(m, "motor_side_inlet", add(c,(-.70,side*1.15,9.15)), (1.10,.09,.62), "seam", .13)
        tube(m, "trim_hydraulic_ram", [m.p(transom-.025,y+side*.04,7.9),
            m.p(x-.04,y+side*.04,5.3)], .19, "steel", 8)
    box(m, "motor_badge", m.p(x-.015, y+.046, 10.0), (2.0, .2, .7), "brass", .15)
    for j in range(4):
        box(m, "motor_intake", m.p(x-.06+j*.035, y, 11.95), (.2, 1.6, .16), "seam", .05)
    tube(m, "steering_link", [m.p(transom-.09,y-.045,7.8),m.p(transom-.09,y+.045,7.8)], .19, "brass", 8)
    tube(m, "motor_control_hose", [m.p(transom+.005,y,8.4),m.p(transom-.045,y,9.1),
        m.p(x+.025,y,9.1)], .20, "rubber", 8)
    tube(m, "drive_leg", [m.p(x-.04, y, 8.0), m.p(x-.15, y, 1.25)], .6, "armor", 12)
    # Above-water prop guard / shaft housing; no underwater black blob.
    pts = [m.p(x-.20, y+.07*cos(TAU*j/24), 1.8+1.25*sin(TAU*j/24)) for j in range(24)]
    tube(m, "propulsion_guard", pts, .15, "steel", 6, True)
    tube(m, "propeller_hub", [m.p(x-.22, y, 1.8), m.p(x-.07, y, 1.8)], .38, "brass", 12)
    for side in (-1, 1):
        box(m, "propeller_blade", m.p(x-.15, y+side*.034, 1.8), (.28, 1.6, .35), "brass", .13, yaw=.3*side)


def window(m, x, y, z, length, width, height, yaw=0):
    c = m.p(x, y, z)
    box(m, "window_gasket", c, (length*m.size, width*m.size, height), "rubber", .22, yaw)
    box(m, "window_glass", add(c, (0, 0, .10)), (length*m.size-.24, width*m.size+.08, height-.25), "glass", .16, yaw)
    box(m, "window_sky_edge", add(c, (0, 0, height*.5-.33)),
        (max(.05,length*m.size-.28),max(.05,width*m.size-.06),.24), "glass_edge", .08, yaw)


def lamp(m, x, y, z, mat="lamp"):
    c = m.p(x, y, z)
    lathe(m, "navigation_lamp", c, [(0, 0), (.4, 0), (.4, .25), (.3, .3), (.3, .9), (.4, 1), (0, 1.25)], "brass", 12)
    lathe(m, "lamp_lens", c, [(.31, .4), (.31, .8)], mat, 12)


def tin_skiff():
    m = Model("tin_skiff", 14)
    m.sockets = sockets_for(m.hull_id, m.size, "skiff", 1, "compact")
    st = [(-1.86,.42),(-1.62,.52),(-.95,.58),(-.15,.60),(.55,.58),(1.22,.46),(1.78,.22),(2.02,.002)]
    hull_shell(m, "rolled_aluminum_launch", st, 0, 9.7, "tin", "teal", bow_rise=.90)
    # Inset cockpit tub and two fixed helm assets; no generated people.
    box(m, "cockpit_well", m.p(-.30, 0, 10.2), (10.2, 6.8, .5), "seam", .8)
    box(m, "cockpit_floor", m.p(-.30, 0, 10.5), (9.2, 5.9, .35), "deck", .6)
    for y in (-.19, .19):
        box(m, "leather_seat_cushion", m.p(-.42, y, 12.1), (2.6, 2.0, 1.0), "canvas", .4)
        box(m, "seat_back", m.p(-.51, y, 13.1), (.7, 2.1, 2.1), "canvas", .3)
    box(m, "raked_helm_console", m.p(-.04, 0, 13.8), (1.9, 6.7, 4.5), "teal", .6)
    window(m, .02, 0, 17.0, .07, .49, 2.5)
    for y in (-.25, 0, .25):
        tube(m, "windscreen_mullion", [m.p(.01,y,15.6),m.p(.03,y,18.4)], .13, "steel", 8)
    # Wheel ring lies in the console's vertical plane.
    pts = [m.p(-.14, .15+.065*cos(TAU*j/20), 15+.85*sin(TAU*j/20)) for j in range(20)]
    tube(m, "helm_wheel", pts, .12, "rubber", 6, True)
    engine(m, -1.0, 0, 10.0, .34, .40, 13.0, "ivory")
    hatch(m, .40, -.28, 10.4, .22, .17, "teal")
    for y in (-.22, .22):
        drive(m, -1.86, y, True)
    # Ribs, plank seams, rolled gunwales, rivets and bow rubbing shoe.
    for side in (-1, 1):
        xs = [-1.05,-.75,-.35,.05,.4]
        railing(m, "cockpit_guard", xs, side, lambda x: width_at(st,x)*.94, 13.5, "tin")
        for i in range(13):
            x = -1.55+i*.245
            w = width_at(st,x)
            lathe(m,"gunwale_rivet",m.p(x,side*w*.94,10.05),[(0,0),(.12,0),(.10,.14),(0,.18)],"steel",6)
        cleat(m, 1.53, side*.19, 10.7)
        cleat(m, -1.66, side*.27, 10.5)
    rope_coil(m,1.42,.16,10.6,.75)
    box(m,"bow_nosing",m.p(1.83,0,9.2),(2.2,2.2,1.5),"rubber",.6)
    box(m,"tool_locker",m.p(-1.20,-.30,11.2),(2.8,2.0,1.7),"teal",.3)
    box(m,"portable_fuel_tank",m.p(-1.10,.35,11.3),(.25*14,.16*14,2.0),"oxide",.4)
    for x in (-1.18,-1.02):
        box(m,"fuel_tank_strap",m.p(x,.35,12.35),(.35,.17*14,.22),"steel",.07)
    tube(m,"exposed_fuel_hose",[m.p(-1.02,.34,11.2),m.p(-.88,.34,11.2),m.p(-.88,.19,11.2)],.18,"rubber",8)
    deck_windlass(m,1.66,0,10.7,.21,.25)
    lamp(m,-.02,-.28,18.3,"red")
    lamp(m,-.02,.28,18.3,"teal_light")
    mounting_rings(m,10.2)
    return m


def ash_corvette():
    m = Model("ash_corvette",21)
    m.sockets = sockets_for(m.hull_id,m.size,"corvette",2,"forge")
    st=[(-1.94,.52),(-1.66,.64),(-.88,.68),(.10,.68),(.72,.65),(1.36,.52),(1.86,.24),(2.10,.002)]
    hull_shell(m,"forged_round_bilge",st,0,10.5,"armor","oxide")
    # Individually bevelled armor courses and weld straps, no flat silhouette recolor.
    for side in (-1,1):
        for i in range(9):
            x=-1.55+i*.36
            w=width_at(st,x)
            box(m,"armor_belt_plate",m.p(x,side*(w-.022),7.1),(6.8,.65,3.4),"armor_light",.35)
            for dx in (-.12,.12):
                box(m,"belt_fastener",m.p(x+dx,side*(w+.002),7.25),(.40,.24,.40),"steel",.12)
        railing(m,"fore_guard",[1.48,1.66,1.82],side,lambda x:width_at(st,x)*.89,13.9,"steel")
        railing(m,"engine_walk",[-1.18,-.95,-.70],side,lambda x:width_at(st,x)*.91,14.0,"steel")
    box(m,"turtleback_lower_house",m.p(-.31,0,15.3),(.78*21,.59*21,8.2),"armor",1.6)
    box(m,"foundry_brow",m.p(-.21,0,20.1),(.69*21,.64*21,1.6),"oxide",.6)
    box(m,"curved_conning_roof",m.p(-.31,0,21.2),(.65*21,.50*21,2.5),"armor_light",1.0)
    for y in (-.17,0,.17):
        window(m,.081,y,18.05,.02,.13,2.3)
    for side in (-1,1):
        for x in (-.48,-.30,-.12):
            window(m,x,side*.299,17.8,.12,.012,2.15)
        box(m,"armored_bridge_door",m.p(-.48,side*.304,14.7),(2.5,.4,4.6),"armor_light",.35)
        tube(m,"door_handhold",[m.p(-.43,side*.324,14),m.p(-.43,side*.324,15.3)],.11,"brass",6)
        for x in (-.59,-.06):
            lamp(m,x,side*.29,21.0,"red" if side<0 else "teal_light")
    engine(m,-1.01,0,10.8,.35,.46,14.0)
    # Ringed exhaust with curved copper manifold, louver banks and rain cap.
    lathe(m,"exhaust_stack",m.p(-1.03,0,0),[(1.9,13),(1.7,14),(1.5,18.5),(1.85,18.9),(1.85,19.4),(1.45,19.7)],"machinery",24)
    lathe(m,"stack_rim",m.p(-1.03,0,0),[(1.46,19.5),(1.75,19.5),(1.75,20.1),(1.46,20.1)],"brass",24)
    lathe(m,"exhaust_dark_throat",m.p(-1.03,0,0),[(0,19.55),(1.45,19.55)],"seam",24)
    tube(m,"exhaust_header",[m.p(-.88,-.20,13),m.p(-.91,-.27,14.0),m.p(-1.08,-.27,15.1),m.p(-1.08,0,16)],.40,"brass",10)
    tube(m,"radio_mast",[m.p(-.42,0,22),m.p(-.42,0,29.0)],.18,"steel",8)
    tube(m,"radio_crossarm",[m.p(-.42,-.16,27.8),m.p(-.42,.16,27.8)],.12,"steel",6)
    for side in (-1,1):
        drive(m,-1.94,side*.27)
        hatch(m,-1.26,side*.34,11.2,.22,.19,"oxide")
        cleat(m,1.68,side*.23,11.5)
        # Fixed life rings, not weapon discs.
        c=m.p(-.36,side*.33,14.7)
        pts=[add(c,(1.25*cos(TAU*j/24),0,1.25*sin(TAU*j/24))) for j in range(24)]
        tube(m,"lifering",pts,.28,"ivory",8,True)
    hatch(m,1.56,0,11.3,.26,.24,"armor_light")
    rope_coil(m,1.60,-.20,11.6,1.0)
    for side in (-1,1):
        ventilator(m,-.31,side*.49,11.0,.42,.15,14.1,"oxide")
        box(m,"vent_walk_grating",m.p(-.31,side*.49,11.10),(.56*21,.24*21,.24),"seam",.15)
        for j in range(4):
            box(m,"walk_grating_bar",m.p(-.50+j*.13,side*.49,11.27),(.50,.21*21,.16),"steel",.05)
    deck_windlass(m,1.78,0,11.2,.21,.25)
    mounting_rings(m,10.8)
    return m


def brasswind_motor_galleon():
    m=Model("brasswind_motor_galleon",28)
    m.sockets=sockets_for(m.hull_id,m.size,"raider",3,"compact")
    st=[(-2.50,.36),(-2.06,.38),(-.90,.38),(.45,.38),(1.30,.33),(1.94,.23),(2.44,.09),(2.65,.002)]
    for side in (-1,1):
        hull_shell(m,"timber_demi_hull"+str(side),st,side*.62,10.1,"teal","brass")
    # The bridge deck unites two actual demi-hulls; pointed bows remain distinct.
    box(m,"bridgedeck_structure",m.p(-.30,0,9.0),(3.78*28,1.15*28,2.4),"timber",.75)
    box(m,"bridgedeck_teak",m.p(-.30,0,10.4),(3.75*28,1.13*28,.65),"deck",.45)
    for x in (-1.85,-1.35,-.8,-.1,.45,1.10,1.48):
        box(m,"transverse_timber",m.p(x,0,8.7),(1.35,1.75*28,1.4),"timber",.4)
    # Tall cream packet house, wraparound brass windows and walkaround balcony.
    box(m,"packet_house_lower",m.p(-.28,0,15.1),(.75*28,.59*28,8.8),"ivory",1.1)
    box(m,"balcony_floor",m.p(-.28,0,19.8),(.91*28,.76*28,1.0),"timber",.6)
    box(m,"upper_packet_house",m.p(-.32,0,22.1),(.55*28,.49*28,4.2),"teal",.8)
    box(m,"brass_roof_eave",m.p(-.32,0,24.7),(.67*28,.58*28,1.1),"brass",.45)
    box(m,"roof_crown",m.p(-.32,0,25.35),(.58*28,.49*28,.9),"ivory",.4)
    for y in (-.16,0,.16):
        window(m,-.031,y,22.2,.014,.13,2.1)
    for side in (-1,1):
        for x in (-.49,-.33,-.17):
            window(m,x,side*.249,22.2,.11,.012,2.1)
        for x in (-.52,-.31,-.10):
            window(m,x,side*.299,16.7,.12,.012,2.0)
        railing(m,"balcony",[-.69,-.50,-.28,-.06,.15],side,lambda x:.37,22.6,"brass")
        railing(m,"outer_deck",[-1.20,-.90,-.65],side,lambda x:.98,13.9,"ivory")
        railing(m,"fore_deck",[1.48,1.72,1.98,2.17],side,lambda x: .62+width_at(st,x)*.9,13.5,"ivory")
        engine(m,-1.02,side*.20,10.8,.37,.23,14.3,"teal")
        lathe(m,"merchant_funnel",m.p(-1.04,side*.20,0),[(1.3,14),(1.1,15),(1.1,20),(1.4,20.4),(1.4,21),(1.0,21)],"brass",24)
        lathe(m,"funnel_throat",m.p(-1.04,side*.20,0),[(0,20.8),(1.0,20.8)],"seam",20)
        drive(m,-2.50,side*.62)
        hatch(m,1.45,side*.65,10.8,.44,.28,"teal")
        # Slatted cargo lids with brass bands, stacked canvas-covered bales aft.
        for j in range(5):
            box(m,"hatch_batten",m.p(1.29+j*.08,side*.65,11.9),(.3,.22*28,.22),"timber",.08)
        for x in (-2.08,-1.78):
            box(m,"cargo_crate",m.p(x,side*.62,12.7),(.26*28,.29*28,4.8),"timber",.5)
            box(m,"canvas_bale",m.p(x,side*.62,15.3),(.27*28,.30*28,1.4),"canvas",.6)
            for dy in (-.10,.10):
                box(m,"cargo_binding",m.p(x,side*.62+dy,16.05),(.28*28,.26,.22),"rope",.07)
        cleat(m,2.10,side*.72,11.2)
        cleat(m,-2.20,side*.83,10.9)
        rope_coil(m,1.91,side*.72,11.4,1.5)
        ventilator(m,-.22,side*.66,10.8,.44,.18,14.2,"ivory")
        deck_windlass(m,2.15,side*.62,10.9,.20,.24)
        # Raised cargo runners and iron corners break up the broad bridge deck.
        for x in (-2.08,-1.78):
            for edge in (-1,1):
                box(m,"crate_corner_iron",m.p(x+edge*.105,side*.62,12.8),
                    (.55,.30*28,4.1),"armor",.15)
        box(m,"paired_cargo_skylight_frame",m.p(.16,side*.63,10.95),(.28*28,.24*28,.6),"ivory",.25)
        box(m,"paired_cargo_skylight",m.p(.16,side*.63,11.30),(.21*28,.17*28,.25),"glass",.10)
    # Visible industrial cargo derrick: collar, gooseneck, boom, sheave and rigging.
    for side,height in ((-1,35.5),(1,31.5)):
        x,y=-.55,side*.57
        lathe(m,"derrick_base",m.p(x,y,0),[(1.0,10.8),(1.0,12),(.55,12),(.38,height),(.16,height+.6)],"timber",16)
        for z in (14,22,height-1):
            lathe(m,"mast_iron_band",m.p(x,y,0),[(.57,z),(.57,z+.6)],"brass",16)
        tube(m,"cargo_boom",[m.p(x,y,16.0),m.p(.28,side*.80,27.0)],.34,"timber",12)
        tube(m,"boom_topping_lift",[m.p(x,y,height),m.p(.28,side*.80,27.0)],.075,"rope",6)
        tube(m,"derrick_stay",[m.p(x,y,height),m.p(-1.20,side*.90,11.2)],.065,"rope",6)
        tube(m,"cargo_fall",[m.p(.28,side*.80,27.0),m.p(.28,side*.80,17.0)],.09,"rope",6)
        lathe(m,"cargo_hook",m.p(.28,side*.80,16),[(0,0),(.35,.2),(.38,.8),(.14,1.1)],"steel",10)
        lamp(m,-.10,side*.30,25.5,"red" if side<0 else "teal_light")
    mounting_rings(m,10.8)
    return m


BUILDERS={"tin_skiff":tin_skiff,"ash_corvette":ash_corvette,"brasswind_motor_galleon":brasswind_motor_galleon}


# Load only recipe declarations. Construction remains lazy and creates no files.
# Passing this module's primitives avoids a circular import or a second renderer.
from importlib.util import spec_from_file_location, module_from_spec
from pathlib import Path

_roster_spec = spec_from_file_location("brass_tide_roster049", Path(__file__).resolve().parents[1]/"quality049"/"recipes.py")
_roster = module_from_spec(_roster_spec)
_roster_spec.loader.exec_module(_roster)
BUILDERS.update({hid: (lambda hid=hid: _roster.build(hid, globals())) for hid in _roster.DESIGNS})


def build(hull_id):
    return BUILDERS[hull_id]()
