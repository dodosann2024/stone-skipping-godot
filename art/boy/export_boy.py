"""Join the boy, bake AO + all clips, export boy/boy.glb and boy/boy_meta.json for Godot."""
import bpy, json, os, math
import posekit, clips, clearance, face
from mathutils import Vector

FPS = 30
LOOPS = {"idle", "stroll", "walk", "run", "hammock_sleep", "sun_rest", "seat_rest", "seat_nap"}
RIGID = ("Hat", "Glasses", "Stone", "Eyes", "BoyHead")  # mitts are skinned into BoyMesh
OWN_UV2 = ("hair", "tank", "vest", "shorts")


def join_parts(rig):
    body = bpy.data.objects["Body"]
    parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name not in RIGID and o != body]
    if body.data.uv_layers:
        body.data.uv_layers[0].name = "UVMap"
    for o in parts:
        me = o.data
        while len(me.uv_layers) < 2:
            me.uv_layers.new()
        me.uv_layers[0].name = "UVMap"
        me.uv_layers[1].name = "Face"
        if "cb" in me.attributes:
            continue        # hair / clothes: UV2 carries their own data (hair.gdshader, cloth.gdshader)
        for d in me.uv_layers[1].data:
            d.uv = (5.0, 5.0)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts + [body]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "BoyMesh"
    body.data.name = "BoyMesh"
    return body


def bake_ao(objs):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.device = "CPU"
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.world.light_settings.distance = 0.25
    for o in objs:
        me = o.data
        if "AO" not in me.color_attributes:
            me.color_attributes.new("AO", "BYTE_COLOR", "POINT")
        me.color_attributes.active_color = me.color_attributes["AO"]
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")


def face_mask(body, rig):
    """AO lives in the colour's red channel; green = 1 on the face; blue / alpha = the "cb" / "ca"
    attributes (hair under the hat crown; clothes: distance to the garment edge / to a seam); on the skin
    blue = warmth (the ears' thin, sun-reddened rims).
    UV2 becomes one continuous front projection so the shader's fwidth() has no seams (except on the
    hair and clothes, whose UV2 is their own data)"""
    me = body.data
    hz = rig.data.bones["head"].head_local.z
    uv2 = me.uv_layers["Face"]
    hair_mi = [i for i, m in enumerate(me.materials) if m and m.name in OWN_UV2]
    hair_l = set()
    for p in me.polygons:
        if p.material_index in hair_mi:
            hair_l.update(p.loop_indices)
    face = set(l.vertex_index for l in me.loops if uv2.data[l.index].uv.x < 4.0 and l.index not in hair_l)
    cg = me.attributes.get("cg")
    cb = me.attributes.get("cb")
    ca = me.attributes.get("ca")
    col = me.color_attributes["AO"]
    skin_mi = [i for i, m in enumerate(me.materials) if m and m.name == "skin"]
    skin_v = {v for p in me.polygons if p.material_index in skin_mi for v in p.vertices}
    hg = body.vertex_groups["head"].index
    warm = {}
    for i in skin_v:
        v = me.vertices[i]
        hw = sum(g.weight for g in v.groups if g.group == hg)
        k = max(0.0, min(1.0, (abs(v.co.x) - 0.060) / 0.010)) * hw * (1.0 if hz - 0.01 < v.co.z < hz + 0.10 else 0.0)
        if k > 0.0:
            warm[i] = k * k * (3.0 - 2.0 * k)
    for i, d in enumerate(col.data):
        c = d.color
        b = cb.data[i].value if cb else 0.0
        d.color = (c[0], 1.0 if i in face else (cg.data[i].value if cg else 0.0), max(b, warm.get(i, 0.0)), ca.data[i].value if ca else 1.0)
    for l in me.loops:
        if l.index in hair_l:
            continue
        co = me.vertices[l.vertex_index].co
        uv2.data[l.index].uv = (co.x, co.z - hz)


def bake_clips(rig_obj, meta):
    rig = posekit.Rig(rig_obj)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = 0
    acts = {}
    gaits = clips.gaits(rig)
    def cycle(g):
        # the baked frames must span exactly one stride cycle, or the loop pops and planted feet creep
        n = int(round(g.T * FPS))
        return lambda t: g.pose(t * g.T * FPS / n)
    todo = [
        ("idle", clips.idle(rig), 4.0),
        ("stroll", cycle(gaits["stroll"]), gaits["stroll"].T),
        ("walk", cycle(gaits["walk"]), gaits["walk"].T),
        ("run", cycle(gaits["run"]), gaits["run"].T),
    ]
    f, L = clips.throw_stand(rig); todo.append(("throw_stand", f, L))
    f, L = clips.throw_crouch(rig); todo.append(("throw_crouch", f, L))
    f, L = clips.cheer(rig); todo.append(("cheer", f, L))
    f, L = clips.oops(rig); todo.append(("oops", f, L))
    for k, f in clips.hammock_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    for k, f in clips.towel_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    for k, f in clips.seat_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    meta["clips"] = {}
    for name, fn, L in todo:
        frames = int(round(L * FPS))
        act, info = posekit.bake(rig, name, fn, frames, FPS, loop=name in LOOPS)
        acts[name] = act
        m = {"length": frames / FPS, "loop": name in LOOPS}
        if name in gaits:
            g = gaits[name]
            m.update({"period": g.T, "stride": g.S, "speed": g.S / g.T, "duty": g.duty})
        if name.startswith(("hammock", "sun", "seat")):
            m["pelvis"] = [list(p) for p in info["pelvis"]]
        if name.startswith("throw"):
            fr = int(round(clips.T_RELEASE * FPS))
            m["t_charge"] = clips.T_CHARGE
            m["t_release"] = clips.T_RELEASE
            m["hand_r"] = [list(p) for p in info["hand_r"]]
            # stone sits in the palm: a bit along the hand from the wrist
            m["release"] = list(info["hand_r"][fr])
        meta["clips"][name] = m
    return acts


def _cartoon_face_mask(head, rig):
    """AO red already baked; green = 1 on skin faces so boy.gdshader draws the face map.
    Hair AO is forced flat — baked AO on the dense helmet reads as a waffle grid."""
    me = head.data
    col = me.color_attributes.get("AO") or me.color_attributes.new("AO", "BYTE_COLOR", "POINT")
    skin_mi = [i for i, m in enumerate(me.materials) if m and m.name == "skin"]
    hair_mi = [i for i, m in enumerate(me.materials) if m and m.name == "hair"]
    skin_v = {v for p in me.polygons if p.material_index in skin_mi for v in p.vertices}
    hair_v = {v for p in me.polygons if p.material_index in hair_mi for v in p.vertices}
    cb = me.attributes.get("cb")
    for i, d in enumerate(col.data):
        c = d.color
        b = cb.data[i].value if cb else 0.0
        ao = 1.0 if i in hair_v else c[0]
        d.color = (ao, 1.0 if i in skin_v else 0.0, b, 1.0)
    hz = rig.data.bones["head"].head_local.z
    uv2 = me.uv_layers.get("Face") or me.uv_layers.new(name="Face")
    hair_l = set()
    for p in me.polygons:
        if p.material_index in hair_mi:
            hair_l.update(p.loop_indices)
    for l in me.loops:
        if l.index in hair_l:
            continue
        co = me.vertices[l.vertex_index].co
        uv2.data[l.index].uv = (co.x, co.z - hz)


def export(rig_obj, out_dir):
    meta = {"fps": FPS, "ground": posekit.GROUND}
    # torso outline for the arm / body clearance check in dev/selftest.gd (measured before the join)
    clearance.save(clearance.measure_rig(posekit.Rig(rig_obj)), os.path.join(out_dir, "torso_profile.json"))
    body = join_parts(rig_obj)
    hat = bpy.data.objects["Hat"]
    props = [bpy.data.objects[n] for n in RIGID]
    head0 = bpy.data.objects.get("BoyHead")
    bake_ao([body, hat] + ([head0] if head0 else []))
    if head0:
        _cartoon_face_mask(head0, rig_obj)
    face_mask(body, rig_obj)
    acts = bake_clips(rig_obj, meta)
    # stone offset from the hand bone (palm centre), in the hand bone's rest frame
    hb = rig_obj.data.bones["hand_r"]
    mid = rig_obj.data.bones["middle_01_r"]
    palm = (Vector(hb.head_local) * 0.4 + Vector(mid.head_local) * 0.6)
    meta["stone_local"] = list(hb.matrix_local.inverted() @ palm)
    meta["eyes"] = [list(e) for e in body["eyes_uv"]]
    meta["face_rect"] = list(face.RECT)  # may be overwritten by BoyHead
    meta["height"] = max(v.co.z for v in body.data.vertices) - posekit.GROUND
    for b in ("pelvis", "head", "hand_r"):
        meta.setdefault("rest", {})[b] = list(rig_obj.data.bones[b].head_local)
    os.makedirs(out_dir, exist_ok=True)
    rig_obj.animation_data_create()
    rig_obj.animation_data.action = None
    for pb in rig_obj.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    head = bpy.data.objects.get("BoyHead")
    if head is None:
        head = face.split_head(body)
    else:
        # ensure armature points at the joined-rig body's armature object
        for m in head.modifiers:
            if m.type == "ARMATURE":
                m.object = rig_obj
    meta["morphs"] = [k.name for k in head.data.shape_keys.key_blocks[1:]]
    if "face_rect" in head:
        meta["face_rect"] = list(head["face_rect"])
    for o in [body, head] + props:
        mods = [m.type for m in o.modifiers if m.type != "ARMATURE"]
        assert not mods, (o.name, mods)     # shape keys only survive export_apply=False
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig_obj, body, head] + props:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig_obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, "boy.glb"), export_format="GLB", use_selection=True,
        export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_skins=True, export_all_influences=False,
        export_morph=True, export_morph_normal=True, export_morph_tangent=False, export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
        export_vertex_color="ACTIVE", export_materials="EXPORT", export_image_format="NONE",
        export_optimize_animation_size=False, export_anim_slide_to_zero=False, export_def_bones=False,
        export_rest_position_armature=True, export_extras=False,
    )
    with open(os.path.join(out_dir, "boy_meta.json"), "w") as f:
        json.dump(meta, f, indent=0, separators=(",", ":"))
    print("EXPORTED", out_dir, "clips", len(acts), "tris", sum(len(p.vertices) - 2 for p in body.data.polygons) + sum(len(p.vertices) - 2 for p in hat.data.polygons))
