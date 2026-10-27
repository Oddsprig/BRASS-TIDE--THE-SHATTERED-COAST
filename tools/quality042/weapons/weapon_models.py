"""Original authored marine weapons for Brass Tide 0.042.

Blender SOURCE ONLY. Import with Blender's Python; Root owns every invocation.
Coordinates: +X muzzle, +Y starboard, +Z up; origin is the deck mounting pivot.
One model unit is WeaponGeometry.unit(...); base deck height is added at runtime.
The returned layers permit recoil of actual receivers/barrels without rebaking.
"""
import math
import bpy
from mathutils import Vector

VARIANTS = (
    "gun_single", "gun_twin", "cannon", "rocket_three", "rocket_six",
    "torpedo_single", "torpedo_twin",
)
MUZZLES = {"gun": (8.8, 4.8), "cannon": (14.2, 5.8),
           "rocket": (5.9, 6.0), "torpedo": (7.9, 2.8)}


def material(name, color, metal=0.0, rough=0.4):
    existing = bpy.data.materials.get("042_weapon_" + name)
    if existing:
        return existing
    mat = bpy.data.materials.new("042_weapon_" + name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = rough
    return mat


class Author:
    def __init__(self, variant):
        self.variant = variant
        self.layers = {}
        self.layer = "base"
        self.mats = {
            "paint": material("sea_green", (0.18, 0.27, 0.25), 0.35, 0.46),
            "steel": material("machined_steel", (0.32, 0.40, 0.43), 0.75, 0.29),
            "edge": material("bright_worn_edges", (0.62, 0.68, 0.65), 0.8, 0.25),
            "dark": material("oiled_steel", (0.085, 0.12, 0.13), 0.62, 0.36),
            "brass": material("brass", (0.65, 0.43, 0.17), 0.72, 0.28),
            "rubber": material("grip", (0.06, 0.075, 0.068), 0.0, 0.7),
            "case": material("ammo_case", (0.34, 0.37, 0.23), 0.24, 0.52),
            "bore": material("inside_tube", (0.055, 0.08, 0.075), 0.3, 0.65),
            "warning": material("oxide_red", (0.53, 0.18, 0.095), 0.15, 0.5),
        }

    def finish(self, obj, name, mat, bevel=0):
        obj.name = self.variant + "_" + name
        obj.data.materials.append(self.mats[mat])
        self.layers.setdefault(self.layer, []).append(obj)
        if bevel:
            bevel_mod = obj.modifiers.new("Manufactured edge radii", "BEVEL")
            bevel_mod.width = bevel
            bevel_mod.segments = 2
            bevel_mod.affect = "EDGES"
            normal = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
            normal.keep_sharp = True
        return obj

    def box(self, name, center, size, mat="steel", bevel=0.06):
        bpy.ops.mesh.primitive_cube_add(size=1, location=center)
        obj = bpy.context.object
        obj.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        return self.finish(obj, name, mat, bevel)

    def cylinder(self, name, a, b, radius, mat="steel", vertices=20):
        delta = Vector(b) - Vector(a)
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                          depth=delta.length, location=(Vector(a)+Vector(b))/2)
        obj = bpy.context.object
        obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
        return self.finish(obj, name, mat, 0.025)

    def tube(self, name, a, b, radius, wall=0.16, mat="steel", vertices=20):
        """A physical open tube, including inner wall and annular mouth.

        Recessed darkness is a lit inner wall, never a solid black front disc.
        """
        axis = (Vector(b)-Vector(a)).normalized()
        across = axis.cross(Vector((0, 0, 1))).normalized()
        if across.length < 0.1:
            across = Vector((1, 0, 0))
        up = across.cross(axis).normalized()
        points, faces, slots = [], [], []
        for center, r in [(a, radius), (b, radius),
                          (a, radius-wall), (b, radius-wall)]:
            for i in range(vertices):
                t = i*math.tau/vertices
                points.append(Vector(center)+(across*math.cos(t)+up*math.sin(t))*r)
        for i in range(vertices):
            j = (i+1) % vertices
            faces.extend([(i, j, vertices+j, vertices+i),
                          (2*vertices+j, 2*vertices+i, 3*vertices+i, 3*vertices+j),
                          (vertices+i, vertices+j, 3*vertices+j, 3*vertices+i),
                          (i, 2*vertices+i, 2*vertices+j, j)])
            slots.extend([0, 1, 2, 0])
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(points, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        self.finish(obj, name, mat)
        obj.data.materials.append(self.mats["bore"])
        obj.data.materials.append(self.mats["edge"])
        for face, slot in zip(mesh.polygons, slots):
            face.material_index = slot
        return obj

    def bolts(self, z, xs, ys):
        for x in xs:
            for y in ys:
                self.cylinder("hex_bolt", (x, y, z), (x, y, z+0.13), 0.15,
                              "edge", vertices=6)

    def mount(self, radius=2.2):
        # Eight cut corners, stepped bearing race and separated bolt heads.
        self.cylinder("octagonal_bolted_foot", (0, 0, 0.08), (0, 0, 0.38),
                      radius, "paint", vertices=8)
        self.cylinder("bearing_outer_race", (0, 0, 0.39), (0, 0, 0.65),
                      radius*0.70, "edge", vertices=24)
        self.cylinder("bearing_neck", (0, 0, 0.64), (0, 0, 2.3),
                      radius*0.48, "paint", vertices=20)
        self.bolts(0.38, [-radius*0.58, radius*0.58], [-radius*0.58, radius*0.58])
        self.box("traverse_gear_case", (-1.1, 0.72, 1.5), (1.2, 0.65, 0.75), "dark")


def machine_gun(m, twin):
    m.mount()
    m.box("fork_crossmember", (0, 0, 2.7), (2.5, 2.5 if twin else 2.1, 0.7), "paint")
    for y in [-1.1, 1.1]:
        m.box("fork_cheek", (-0.25, y, 3.45), (1.6, 0.38, 2.0), "paint")
        m.cylinder("elevation_trunnion", (-0.25, y-0.25, 4.2),
                   (-0.25, y+0.25, 4.2), 0.42, "brass")
    # Fixed broad ammunition chest and feed apron break up the barrel silhouette.
    m.box("ammunition_chest", (-1.5, -2.0, 3.7), (2.7, 1.2, 2.1), "case", 0.10)
    m.box("ammunition_lid", (-1.5, -2.0, 4.8), (2.9, 1.3, 0.18), "edge", 0.04)
    m.box("feed_bridge", (-0.9, -1.05, 4.65), (1.3, 1.3, 0.30), "dark")
    for i in range(5):
        y = -1.7+i*0.25
        m.cylinder("linked_brass_round", (-1.45, y, 4.9), (-0.75, y, 4.9), 0.13, "brass", 10)
    m.layer = "moving"
    for y in [-0.53, 0.53] if twin else [0.0]:
        m.box("receiver", (-0.55, y, 4.6), (4.0, 0.84, 1.25), "steel", 0.08)
        m.box("receiver_cover", (-0.7, y, 5.28), (3.4, 0.92, 0.22), "edge", 0.04)
        m.tube("ribbed_cooling_jacket", (1.25, y, 4.8), (6.5, y, 4.8), 0.45, 0.13)
        for x in [2.0, 3.0, 4.0, 5.0, 6.0]:
            m.tube("cooling_ring", (x, y, 4.8), (x+0.14, y, 4.8), 0.52, 0.14, "dark", 16)
        m.tube("muzzle_sleeve", (6.45, y, 4.8), (8.8, y, 4.8), 0.32, 0.10)
        m.tube("flash_suppressor", (8.25, y, 4.8), (8.8, y, 4.8), 0.43, 0.15, "edge")
        m.box("charging_handle", (-1.0, y+0.53, 4.65), (0.8, 0.35, 0.25), "dark")
    m.box("rear_spade_grip_bar", (-2.9, 0, 4.5), (0.32, 2.2, 0.28), "dark")
    for y in [-0.95, 0.95]:
        m.box("rubber_spade_grip", (-2.9, y, 4.15), (0.36, 0.38, 0.85), "rubber")
    m.box("front_sight_post", (1.4, 0, 5.7), (0.2, 0.16, 0.72), "dark", 0.02)


def cannon(m):
    m.mount(3.0)
    m.box("cradle", (-0.4, 0, 2.75), (6.6, 4.0, 1.15), "paint", 0.15)
    for y in [-1.8, 1.8]:
        m.box("cradle_side", (-0.35, y, 4.1), (5.4, 0.56, 2.2), "paint", 0.12)
        m.cylinder("elevation_bearing", (0.2, y-0.35, 5.4), (0.2, y+0.35, 5.4), 0.72, "edge")
        m.cylinder("recoil_cylinder", (-1.3, y, 6.0), (3.9, y, 6.0), 0.40, "steel")
        m.cylinder("polished_recoil_piston", (3.8, y, 6.0), (5.3, y, 6.0), 0.20, "edge")
    m.box("angular_gun_shield", (1.1, 0, 4.3), (0.48, 5.1, 2.7), "paint", 0.1)
    m.box("loading_tray", (-3.8, 0, 4.3), (2.6, 1.45, 0.35), "dark")
    m.cylinder("handwheel_axis", (-1.3, 2.1, 3.6), (-1.3, 2.6, 3.6), 0.15, "brass")
    # A wheel with actual spokes and open gaps, not a black filled disc.
    for theta in [i*math.tau/8 for i in range(8)]:
        m.cylinder("handwheel_spoke", (-1.3, 2.6, 3.6),
                   (-1.3+math.cos(theta)*0.65, 2.6, 3.6+math.sin(theta)*0.65), 0.06, "brass", 8)
    m.layer = "moving"
    m.box("breech_block", (-1.15, 0, 5.8), (4.6, 2.6, 2.35), "steel", 0.16)
    m.box("interrupted_screw_breech", (-3.45, 0, 5.8), (0.52, 2.2, 1.95), "dark", 0.07)
    m.box("breech_operating_lever", (-3.0, 1.58, 6.15), (1.8, 0.26, 0.27), "brass")
    m.tube("reinforced_chamber", (0.8, 0, 5.8), (5.3, 0, 5.8), 1.04, 0.28, "dark")
    m.tube("barrel", (4.8, 0, 5.8), (13.0, 0, 5.8), 0.64, 0.19)
    for x in [5.2, 7.0]:
        m.tube("barrel_band", (x, 0, 5.8), (x+0.3, 0, 5.8), 0.78, 0.21, "edge")
    m.tube("slotted_muzzle_brake", (12.5, 0, 5.8), (14.2, 0, 5.8), 0.93, 0.31)
    for x in [12.8, 13.45]:
        for y in [-0.93, 0.93]:
            m.box("muzzle_brake_vent_recess", (x, y, 5.8), (0.25, 0.04, 0.62), "bore", 0.02)
    m.bolts(7.0, [-2.4, -0.2], [-0.9, 0.9])


def rockets(m, six):
    m.mount(3.0)
    m.box("rack_saddle", (-0.8, 0, 2.7), (4.8, 5.7, 0.9), "paint", 0.12)
    for y in [-2.7, 2.7]:
        m.box("triangular_rack_cheek", (-1.9, y, 3.6), (1.35, 0.35, 2.2), "paint")
    for row in range(2 if six else 1):
        rise = row*1.9
        for y in [-1.8, 0, 1.8]:
            m.tube("open_launch_cell", (-4.8, y, 4.5+rise), (5.9, y, 6.0+rise), 0.76, 0.15)
            m.tube("launch_mouth_collar", (5.45, y, 5.94+rise), (5.9, y, 6.0+rise), 0.89, 0.25, "edge")
            m.cylinder("rear_loaded_rocket", (-4.5, y, 4.55+rise), (-3.1, y, 4.74+rise), 0.40, "case")
            m.box("ignition_terminal", (-4.6, y, 4.15+rise), (0.30, 0.45, 0.45), "brass")
        for x, z in [(-2.2, 4.0), (3.5, 4.8)]:
            m.box("rack_cross_tie", (x, 0, z+rise), (0.38, 6.2, 0.42), "paint")
    m.box("ignition_junction_box", (-2.0, -3.2, 3.0), (1.6, 0.7, 1.0), "warning")
    m.cylinder("protected_ignition_conduit", (-4.6, -2.6, 3.9), (-2.1, -2.6, 3.1), 0.11, "brass", 12)


def torpedoes(m, twin):
    m.mount(2.7 if twin else 2.2)
    for y in [-1.5, 1.5] if twin else [0.0]:
        for x in [-3.1, 3.1]:
            m.box("tube_saddle_foot", (x, y, 0.65), (1.5, 2.7, 1.0), "paint", 0.10)
            m.tube("retaining_strap", (x-0.25, y, 2.8), (x+0.25, y, 2.8), 1.34, 0.20, "brass")
        m.tube("torpedo_pressure_tube", (-7.1, y, 2.8), (7.9, y, 2.8), 1.16, 0.20, "paint")
        m.tube("bronze_mouth_lip", (6.9, y, 2.8), (7.9, y, 2.8), 1.36, 0.37, "brass")
        m.cylinder("closed_rear_breech", (-7.3, y, 2.8), (-6.9, y, 2.8), 1.23, "steel")
        m.cylinder("air_pipe", (-5.7, y+0.85, 3.95), (0.5, y+0.85, 3.95), 0.13, "brass", 12)
        m.box("air_flask_valve", (-1.1, y+0.85, 4.12), (1.35, 0.6, 0.65), "brass")
        m.box("firing_latch", (4.9, y, 4.0), (1.1, 0.65, 0.6), "steel")
        m.cylinder("rear_door_hinge", (-7.2, y-1.2, 2.0), (-7.2, y-1.2, 3.6), 0.18, "brass", 12)


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
    for layer, objects in m.layers.items():
        for obj in objects:
            obj["brass_tide_variant"] = variant
            obj["brass_tide_layer"] = layer
    return m.layers
