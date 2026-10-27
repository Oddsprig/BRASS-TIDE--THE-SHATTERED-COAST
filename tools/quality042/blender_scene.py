"""Shared 0.042 Blender5.2 CPU bake setup, used by hulls and weapons.

SOURCE ONLY until Root invokes Blender in the shared Test Bridge lane.
The slight orthographic pixel-aspect correction is intentional: rounded .82/.41
is not a mathematically orthonormal camera. Ignoring that changes mount heights.
"""
import math
from pathlib import Path

import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

KEY = Vector((-.55, -.65, 1.0)).normalized()
VIEW = Vector((1, 1, .82)).normalized()
HORIZONTAL = .82*math.sqrt(2)
VERTICAL = math.sqrt(1+2*.41**2)


def _area(scene, name, position, color, energy, size):
    data=bpy.data.lights.new(name,"AREA")
    data.energy=energy
    data.color=color
    data.shape="DISK"
    data.size=size
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=position
    obj.rotation_euler=(-obj.location).to_track_quat("-Z","Y").to_euler()
    return obj


def configure_scene(scene, cell_px=(384,320), pivot_px=(192,200), pixels_per_world_unit=2,
                    samples=16, threads=6):
    """Transparent, fixed world-light Cycles CPU camera. Never starts a render."""
    width,height=cell_px
    density=float(pixels_per_world_unit)
    scene.render.engine="CYCLES"
    scene.cycles.device="CPU"
    scene.cycles.samples=int(samples)
    scene.cycles.seed=42
    scene.cycles.use_animated_seed=False
    scene.cycles.use_adaptive_sampling=True
    scene.cycles.adaptive_threshold=.04
    scene.cycles.use_denoising=True
    scene.cycles.max_bounces=4
    scene.cycles.diffuse_bounces=2
    scene.cycles.glossy_bounces=2
    scene.cycles.transmission_bounces=1
    scene.render.threads_mode="FIXED"
    scene.render.threads=int(threads)
    scene.render.resolution_x=int(width)
    scene.render.resolution_y=int(height)
    scene.render.resolution_percentage=100
    scene.render.pixel_aspect_x=1
    scene.render.pixel_aspect_y=HORIZONTAL/VERTICAL
    scene.render.film_transparent=True
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.render.image_settings.color_depth="8"
    scene.render.image_settings.compression=25
    scene.view_settings.view_transform="AgX"
    scene.view_settings.exposure=.35
    scene.view_settings.gamma=1
    scene.world=bpy.data.worlds.new("042_cool_maritime_sky")
    scene.world.use_nodes=True
    background=scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value=(.42,.54,.66,1)
    background.inputs["Strength"].default_value=.45
    cam_data=bpy.data.cameras.new("042_exact_iso_camera")
    cam_data.type="ORTHO"
    cam_data.sensor_fit="HORIZONTAL"
    cam_data.ortho_scale=width/(density*HORIZONTAL)
    cam_data.shift_x=(width*.5-pivot_px[0])/width
    cam_data.shift_y=(pivot_px[1]-height*.5)/(width*VERTICAL/HORIZONTAL)
    cam_data.clip_start=.1
    cam_data.clip_end=2000
    camera=bpy.data.objects.new("042_exact_iso_camera",cam_data)
    scene.collection.objects.link(camera)
    camera.location=VIEW*500
    camera.rotation_euler=(-camera.location).to_track_quat("-Z","Y").to_euler()
    scene.camera=camera
    sun_data=bpy.data.lights.new("042_fixed_world_sun","SUN")
    sun_data.energy=2.6
    sun_data.color=(1,.91,.77)
    sun_data.angle=.075
    sun=bpy.data.objects.new("042_fixed_world_sun",sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler=(-KEY).to_track_quat("-Z","Y").to_euler()
    _area(scene,"042_sky_fill",(0,0,140),(.59,.74,1),18000,180)
    # Actual native camera projection assertion; Root gets a hard failure if
    # Blender's interpretation changes instead of silently misaligned guns.
    bpy.context.view_layer.update()
    for point in ((0,0,0),(1,0,0),(0,1,0),(0,0,1),(31,-9,12)):
        q=world_to_camera_view(scene,camera,Vector(point))
        actual=(q.x*width,(1-q.y)*height)
        x,y,z=point
        expected=(pivot_px[0]+(x-y)*.82*density,
                  pivot_px[1]+((x+y)*.41-z)*density)
        if max(abs(a-b) for a,b in zip(actual,expected)) > .02:
            raise RuntimeError(f"042 camera contract mismatch: {point}: {actual} != {expected}")
    return camera


def render_frame(scene, object_root, heading, output_path, cell_px=(384,320),
                 pivot_px=(192,200), pixels_per_world_unit=2, headings=32):
    """Rotate model only (world lighting stays fixed), then render one frame.

    Call configure_scene once before the first frame. object_root is an Empty
    parent of model objects, NOT lights or camera. heading is an integer index.
    Alternate dimensions require configure_scene again before calling.
    """
    del cell_px,pivot_px,pixels_per_world_unit  # passed explicitly for call-site clarity
    object_root.rotation_euler.z=(int(heading) % headings)*math.tau/headings
    target=Path(output_path)
    target.parent.mkdir(parents=True,exist_ok=True)
    scene.render.filepath=str(target)
    bpy.ops.render.render(write_still=True)
    return target
