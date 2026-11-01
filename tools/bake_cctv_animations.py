"""Run with Blender -b assets/models/GuyRig.blend --python this_file.

Exports temporary, untextured animation sources; never changes the artist's blend/GLBs.
Then run tools/bake_cctv_animations.gd in Godot to save the shared animation library.
"""
import math
import os
import bpy
from mathutils import Vector

OUT = os.path.join(os.environ['LOCALAPPDATA'], 'Temp', 'opencode', 'cctv-animation-bake')
os.makedirs(OUT, exist_ok=True)
rig = bpy.data.objects['rig']
scene = bpy.context.scene
scene.render.fps = 30


def reset():
    for bone in rig.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def place(name, point):
    bone = rig.pose.bones[name]
    matrix = bone.matrix.copy()
    matrix.translation = Vector(point)
    bone.matrix = matrix
    bpy.context.view_layer.update()


def pose(phase=0, sit=0, walking=False, carrying=False, reaching=0, typing=0):
    reset()
    # Rigify's existing IK controls solve the deform skeleton, including split limbs.
    pelvis = rig.pose.bones['torso'].matrix.translation.copy()
    pelvis.z += -0.45 * sit + (0.018 * math.cos(phase * 2) if walking else 0)
    pelvis.y -= 0.02 * sit
    place('torso', pelvis)
    for side, sign in [('L', 1), ('R', -1)]:
        swing = math.sin(phase + (0 if side == 'L' else math.pi)) if walking else 0
        place('foot_ik.' + side, (sign * 0.11, 0.03 - 0.43 * sit - 0.28 * swing,
                                 0.091 + max(0, math.cos(phase + (0 if side == 'L' else math.pi))) * 0.09 * int(walking)))
        hand = (sign * 0.20, 0.01 + 0.20 * swing, 1.01)
        if sit > 0:
            seated_hand = (sign * (0.13 + 0.01 * math.sin(typing)), -0.55,
                           0.98 + 0.008 * math.sin(typing + sign))
            hand = Vector(hand).lerp(Vector(seated_hand), sit)
        elif side == 'R' and (carrying or reaching > 0):
            hand = (-0.21, -0.23 - 0.30 * reaching, 1.05 + 0.06 * reaching)
        place('hand_ik.' + side, hand)
        bone = rig.pose.bones['hand_ik.' + side]
        matrix = bone.matrix.copy()
        forward = max(sit, 1 if side == 'R' and (carrying or reaching > 0) else 0)
        direction = Vector((0, -forward, -(1 - forward))).normalized()
        old_direction = (matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
        rotation = old_direction.rotation_difference(direction) @ matrix.to_quaternion()
        matrix = rotation.to_matrix().to_4x4()
        matrix.translation = Vector(hand)
        bone.matrix = matrix
        bpy.context.view_layer.update()


def bake(name, duration, sampler, loop=False):
    # Bake evaluated local transforms, not just control keys: Godot has no Blender constraints.
    rig.animation_data_clear()
    samples = []
    frames = round(duration * 30)
    for frame in range(frames + 1):
        scene.frame_set(frame + 1)
        sampler(frame / frames)
        evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        samples.append({b.name: b.matrix.copy() for b in evaluated.pose.bones})
    # Remove constraints/drivers only on a temporary copy, keeping the source rig untouched.
    copy = rig.copy()
    copy.data = rig.data.copy()
    scene.collection.objects.link(copy)
    copy.name = 'BakedRig'
    copy.animation_data_clear()
    for bone in copy.pose.bones:
        for constraint in list(bone.constraints):
            bone.constraints.remove(constraint)
    for frame, matrices in enumerate(samples, 1):
        scene.frame_set(frame)
        for bone in copy.pose.bones:
            matrix = matrices[bone.name]
            parent_matrix = matrices[bone.parent.name] if bone.parent else None
            bone.matrix_basis = copy.convert_space(pose_bone=bone, matrix=matrix,
                                                  from_space='POSE', to_space='LOCAL') if parent_matrix is None else (
                (bone.parent.bone.matrix_local.inverted() @ bone.bone.matrix_local).inverted()
                @ parent_matrix.inverted() @ matrix)
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
            bone.keyframe_insert('scale', frame=frame, group=bone.name)
    copy.animation_data.action.name = name
    # Export with the identical node path expected by the original imported models.
    rig.name = 'SourceRig'
    copy.name = 'rig'
    bpy.ops.object.select_all(action='DESELECT')
    copy.select_set(True)
    temporary_meshes = []
    for original in list(bpy.data.objects):
        if original.type == 'MESH' and original.parent == rig:
            mesh = original.copy()
            scene.collection.objects.link(mesh)
            mesh.parent = copy
            for modifier in mesh.modifiers:
                if modifier.type == 'ARMATURE':
                    modifier.object = copy
            mesh.select_set(True)
            temporary_meshes.append(mesh)
    scene.frame_start = 1
    scene.frame_end = frames + 1
    bpy.context.view_layer.objects.active = copy
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), use_selection=True,
                              export_materials='NONE', export_animation_mode='ACTIVE_ACTIONS',
                              export_force_sampling=True, export_frame_range=True,
                              export_optimize_animation_size=True, export_skins=True)
    for mesh in temporary_meshes:
        bpy.data.objects.remove(mesh, do_unlink=True)
    bpy.data.objects.remove(copy, do_unlink=True)
    rig.name = 'rig'
    print('CCTV_BAKED', name, duration, 'loop', loop)


bake('idle', 2.4, lambda t: pose(typing=t * math.tau), True)
bake('walk', 1.0, lambda t: pose(phase=t * math.tau, walking=True), True)
bake('work', 2.0, lambda t: pose(sit=1, typing=t * math.tau * 3), True)
bake('stand', 1.4, lambda t: pose(sit=1 - (t * t * (3 - 2 * t))))
bake('carry_idle', 2.4, lambda t: pose(carrying=True), True)
bake('carry_walk', 1.0, lambda t: pose(phase=t * math.tau, walking=True, carrying=True), True)
bake('reach', 0.9, lambda t: pose(carrying=True, reaching=math.sin(t * math.pi)))
print('CCTV animation sources:', OUT)
