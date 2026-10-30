"""Original authored marine weapons for Brass Tide 0.042.

Offline model SOURCE ONLY. Root owns every bake invocation.
Coordinates: +X muzzle, +Y starboard, +Z up; origin is the deck mounting pivot.
One model unit is WeaponGeometry.unit(...); base deck height is added at runtime.
The returned layers permit recoil of actual receivers/barrels without rebaking.

Ordinary battle zoom leaves only a few pixels for a size-18 tier-1 weapon.
Each mechanism is therefore one heavy profile: machine-gun receiver, cannon
shield and barrel, rocket cell pod, or banded torpedo tube. Materials are the
shared dockyard keys (teal mounts, dark machinery, armor steel, brass).
Sub-pixel rings, vents, spokes and straps are omitted. Nothing here claims
a baked or on-screen visual pass.
"""
import math
from models import Model, box as rounded_box, add, sub, mul, cross, unit

VARIANTS = (
    "gun_single", "gun_twin", "cannon", "rocket_three", "rocket_six",
    "torpedo_single", "torpedo_twin",
)
MUZZLES = {"gun": (8.8, 4.8), "cannon": (14.2, 5.8),
           "rocket": (5.9, 6.0), "torpedo": (7.9, 2.8)}


MATERIAL_KEYS = {"paint": "teal", "steel": "armor_light", "edge": "steel",
                 "dark": "machinery", "brass": "brass", "rubber": "rubber",
                 "case": "canvas", "bore": "seam", "warning": "oxide"}


class Author:
    def __init__(self, variant):
        self.variant = variant
        self.layers = {}
        self.layer = "base"

    @property
    def model(self):
        return self.layers.setdefault(self.layer, Model(self.variant+"_"+self.layer, 1.0))

    def box(self, name, center, size, mat="steel", bevel=0.06):
        return rounded_box(self.model, name, center, size, MATERIAL_KEYS[mat], bevel=bevel)

    def cylinder(self, name, a, b, radius, mat="steel", vertices=16):
        axis = unit(sub(b, a))
        across = unit(cross(axis, (0, 0, 1) if abs(axis[2]) < .95 else (0, 1, 0)))
        up = cross(across, axis)
        side = self.model.part(name, MATERIAL_KEYS[mat])
        for center in (a, b):
            for i in range(vertices):
                t = i*math.tau/vertices
                normal = add(mul(across, math.cos(t)), mul(up, math.sin(t)))
                side.vertices.append(add(center, mul(normal, radius)))
                side.normals.append(normal)
        for i in range(vertices):
            j = (i+1) % vertices
            side.quad((i, j, vertices+j, vertices+i))
        for end, sign in ((a, -1), (b, 1)):
            cap = self.model.part(name+"_cap", MATERIAL_KEYS[mat])
            cap.vertices.append(end)
            for i in range(vertices):
                t = i*math.tau/vertices
                off = add(mul(across, math.cos(t)*radius), mul(up, math.sin(t)*radius))
                cap.vertices.append(add(end, off))
            cap.normals = [mul(axis, sign)]*len(cap.vertices)
            for i in range(vertices): cap.faces.append((0, i+1, (i+1) % vertices+1))
        return side

    def tube(self, name, a, b, radius, wall=0.16, mat="steel", vertices=16):
        """A physical open tube, including inner wall and annular mouth.

        Recessed darkness is a lit inner wall, never a solid black front disc.
        """
        axis = unit(sub(b, a))
        across = unit(cross(axis, (0, 0, 1) if abs(axis[2]) < .95 else (0, 1, 0)))
        up = cross(across, axis)
        for inside, r, material in ((False, radius, MATERIAL_KEYS[mat]),
                                     (True, max(0.08, radius-wall), MATERIAL_KEYS["bore"])):
            side = self.model.part(name+("_inner_wall" if inside else "_outer_wall"), material)
            for center in (a, b):
                for i in range(vertices):
                    t = i*math.tau/vertices
                    normal = add(mul(across, math.cos(t)), mul(up, math.sin(t)))
                    side.vertices.append(add(center, mul(normal, r)))
                    side.normals.append(mul(normal, -1 if inside else 1))
            for i in range(vertices):
                j = (i+1) % vertices
                side.quad((i, j, vertices+j, vertices+i))
        for end, sign in ((a, -1), (b, 1)):
            rim = self.model.part(name+"_annular_mouth", MATERIAL_KEYS["edge"])
            for r in (radius, max(0.08, radius-wall)):
                for i in range(vertices):
                    t = i*math.tau/vertices
                    off = add(mul(across, math.cos(t)*r), mul(up, math.sin(t)*r))
                    rim.vertices.append(add(end, off))
            rim.normals = [mul(axis, sign)]*len(rim.vertices)
            for i in range(vertices):
                j = (i+1) % vertices
                rim.quad((i, j, vertices+j, vertices+i))
        return rim

    def mount(self, radius=2.2):
        # Teal foot matches hull paint. The steel race is the readable step.
        self.cylinder("octagonal_bolted_foot", (0, 0, 0.08), (0, 0, 0.42),
                      radius, "paint", vertices=8)
        self.cylinder("bearing_outer_race", (0, 0, 0.40), (0, 0, 0.72),
                      radius*0.72, "edge", vertices=16)
        self.cylinder("bearing_neck", (0, 0, 0.70), (0, 0, 2.35),
                      radius*0.46, "paint", vertices=12)


def machine_gun(m, twin):
    """Tall dark receiver, narrow barrel, brass muzzle. Shield stays on the base.

    The wide brow sits lower than the receiver cap. A wide plate at the top
    would stretch the side-on sprite without making the gun easier to read.
    A moving barrel root at the bore line joins the receiver to the jacket.
    The fixed shield does not travel with recoil, so it is not that joint.
    """
    m.mount()
    m.box("fork_crossmember", (0.15, 0, 3.05),
          (2.0, 2.8 if twin else 2.1, 0.7), "paint", 0.08)
    m.box("ammunition_chest", (-1.5, -1.9, 3.45), (2.4, 1.15, 1.9), "case", 0.1)
    m.box("ammunition_lid", (-1.5, -1.9, 4.48), (2.45, 1.2, 0.3), "brass", 0.04)
    cheek_y = 1.28 if twin else 1.08
    for y in (-cheek_y, cheek_y):
        m.box("receiver_shield", (1.85, y, 4.15), (1.15, 0.56, 2.05), "steel", 0.06)
        m.cylinder("elevation_trunnion", (0.15, y-0.34, 4.2),
                   (0.15, y+0.34, 4.2), 0.42, "brass", 12)
    m.box("shield_brow", (1.8, 0, 5.22),
          (1.2, 3.15 if twin else 2.7, 0.4), "brass", 0.04)
    m.layer = "moving"
    barrels = (-0.7, 0.7) if twin else (0.0,)
    jacket_r = 0.36 if twin else 0.7
    barrel_r = 0.3 if twin else 0.48
    muzzle_r = 0.4 if twin else 0.64
    receiver_w = 0.9 if twin else 1.22
    for y in barrels:
        m.box("receiver", (-0.45, y, 4.05), (3.05, receiver_w, 2.35), "dark", 0.1)
        m.box("receiver_cover", (-0.5, y, 5.28), (2.7, 0.9, 0.68), "brass", 0.05)
        # Receiver ends at 1.075 and the jacket starts at 2.55. Same radius as
        # the jacket, so the outer wall is one piece and stays in its envelope.
        m.tube("barrel_root", (0.9, y, 4.8), (2.7, y, 4.8), jacket_r, 0.14, vertices=12)
        m.tube("cooling_jacket", (2.55, y, 4.8), (4.55, y, 4.8), jacket_r, 0.14, vertices=12)
        m.tube("barrel", (4.4, y, 4.8), (7.4, y, 4.8), barrel_r, 0.12, vertices=12)
        m.tube("muzzle", (7.2, y, 4.8), (8.8, y, 4.8), muzzle_r, 0.16, "brass", 12)
    m.box("spade_grip", (-2.4, 0, 4.0), (1.05, 1.35, 1.2), "rubber", 0.08)


def cannon(m):
    """One barrel and a broad shield. Cradle rods no longer imitate extra guns.

    The breech stops behind the shield opening, and the brass brow clears the
    barrel. The barrel starts inside the breech. Shield width is kept low,
    where it does not add side-on height.
    """
    m.mount(3.0)
    m.box("cradle", (-0.5, 0, 3.0), (5.0, 3.3, 1.4), "paint", 0.1)
    m.box("gun_shield_face", (1.25, 0, 3.7), (1.5, 4.6, 1.55), "steel", 0.08)
    for y in (-1.58, 1.58):
        m.box("gun_shield_cheek", (1.35, y, 5.05), (1.2, 0.72, 2.85), "steel", 0.06)
        m.cylinder("elevation_bearing", (0.4, y-0.4, 5.1),
                   (0.4, y+0.4, 5.1), 0.52, "brass", 12)
    m.box("gun_shield_brow", (1.25, 0, 6.78), (1.3, 2.2, 0.46), "brass", 0.04)
    m.box("loading_tray", (-3.7, 0, 4.05), (2.5, 1.45, 0.65), "dark", 0.08)
    m.layer = "moving"
    m.box("breech_block", (-1.3, 0, 5.6), (3.2, 2.05, 2.3), "dark", 0.1)
    m.cylinder("breech_cap", (-3.25, 0, 5.6), (-2.55, 0, 5.6), 0.96, "brass", 12)
    # Breech face is x=0.3. Starting at 0.2 seats the tube in the block.
    m.tube("barrel", (0.2, 0, 5.8), (12.0, 0, 5.8), 0.74, 0.2, vertices=16)
    m.tube("barrel_band", (6.4, 0, 5.8), (7.55, 0, 5.8), 0.94, 0.24, "brass", 12)
    m.tube("muzzle_brake", (11.85, 0, 5.8), (14.2, 0, 5.8), 1.06, 0.3, "brass", 12)


def rockets(m, six):
    """A dark pod with a brass face and three open cells, not hairline tubes."""
    m.mount(3.0)
    m.box("rack_saddle", (-0.15, 0, 2.95), (6.2, 5.3, 1.55), "paint", 0.1)
    for row in range(2 if six else 1):
        rise = row*1.9
        zc = 5.05+rise
        m.box("cell_pod", (0.1, 0, zc), (8.2, 5.05, 2.85), "dark", 0.1)
        m.box("cell_face", (3.95, 0, zc), (1.2, 5.05, 2.85), "brass", 0.06)
        for y, z in ((0.0, 6.0), (-1.86, 4.4), (1.86, 4.4)):
            m.tube("launch_cell", (4.4, y, z+rise), (5.9, y, z+rise),
                   0.66, 0.18, "steel", 12)
    m.box("ignition_junction_box", (-2.15, -3.02, 3.35),
          (1.65, 0.82, 1.15), "warning", 0.08)


def torpedoes(m, twin):
    """Dark tube, two long brass bands, and a brass mouth. Bands use the old lip radius.

    The pressure tube overlaps the rear breech. No extra band is added.
    """
    m.mount(2.7 if twin else 2.2)
    for y in ((-1.5, 1.5) if twin else (0.0,)):
        for x in (-3.1, 3.1):
            m.box("tube_saddle_foot", (x, y, 0.68), (1.55, 2.5, 1.05), "paint", 0.08)
        m.box("tube_cradle", (0.15, y, 1.72), (7.0, 1.25, 1.05), "paint", 0.08)
        m.cylinder("rear_breech", (-7.15, y, 2.8), (-6.35, y, 2.8), 1.24, "steel", 16)
        # Breech ends at -6.35. Starting at -6.5 overlaps it by 0.15.
        m.tube("torpedo_pressure_tube", (-6.5, y, 2.8), (5.6, y, 2.8),
               1.16, 0.3, "dark", 16)
        m.tube("brass_band_aft", (-2.5, y, 2.8), (-0.9, y, 2.8),
               1.36, 0.3, "brass", 16)
        m.tube("brass_band_forward", (1.5, y, 2.8), (3.1, y, 2.8),
               1.36, 0.3, "brass", 16)
        m.tube("bronze_mouth", (5.6, y, 2.8), (7.9, y, 2.8),
               1.36, 0.34, "brass", 16)


def build_weapon(variant):
    if variant not in VARIANTS:
        raise ValueError("Unknown weapon variant: " + variant)
    m = Author(variant)
    if variant.startswith("gun_"):
        machine_gun(m, variant == "gun_twin")
    elif variant == "cannon":
        cannon(m)
    elif variant.startswith("rocket_"):
        rockets(m, variant == "rocket_six")
    else:
        torpedoes(m, variant == "torpedo_twin")
    return m.layers
