extends SceneTree
## Clear hammock day+night sequence, sleep face (closed-eye albedo), walk/run filmstrips.
## Uses rest_frozen so _rest_tick cannot advance phases during stills.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	DirAccess.make_dir_recursive_absolute("/workspace/screenshots/v24")
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 50:
		await process_frame
	m.demo_mode = true
	m.rest_frozen = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false

	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 80:
			await process_frame

	# ---- Hammock DAY sequence ----
	m._begin_rest("sleep")
	m.rest_frozen = true
	m.rest_phase = 0
	m.rest_t = 0.0

	var hh0: Vector3 = (m.island.hammock_a + m.island.hammock_b) * 0.5
	var along: Vector3 = (m.island.hammock_b - m.island.hammock_a).normalized()
	var side: Vector3 = m.rest_side.normalized()
	var hidden: Array = []
	_hide_occluders(m, hh0, hidden)

	# ENTER: stand beside hammock, clear of fabric (no walk-through)
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.rotation = Vector3(0, atan2(-side.x, -side.z), 0)
	m.boy.set_idle()
	m.boy.end_activity()
	m.island.set_hammock_load([] as Array[Vector3])
	for _i in 8:
		await process_frame
	await _cam_shot(m, vp, "hammock_enter",
		m.rest_approach + Vector3(0, 0.55, 0),
		m.rest_approach + side * 2.4 + along * (-0.2) + Vector3(0, 1.15, 0))

	# SIT: butt on sag, facing outward, legs hanging over near edge
	m.rest_phase = 2
	for _p in 24:
		var pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var knee: Vector3 = m.boy.lie_bone_world("mixamorig_LeftLeg")
	var ankle: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
	var fwd: Vector3 = (-m.rest_sit_b.z).normalized()
	print("HAM_SIT elev=%.1f fwd=%.2f" % [m.boy.sit_thigh_elev_deg(), (knee - hips).normalized().dot(fwd)])
	# Side-outward camera: see legs hanging + fabric under pelvis; no palm in path
	var sit_look: Vector3 = (hips + knee + ankle) * 0.33
	await _cam_shot(m, vp, "hammock_sit", sit_look,
		sit_look + side * 2.8 + along * 0.15 + Vector3(0, 0.85, 0))

	# Night sit (same pose, moon fill)
	m.boy.restore_pose_mesh()
	if not m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	if m.boy.face_fill:
		m.boy.face_fill.light_energy = 2.1
		m.boy.face_fill.omni_range = 2.4
	if m.boy._night_body:
		m.boy._night_body.light_energy = 1.9
	if m.boy._night_rim:
		m.boy._night_rim.light_energy = 1.1
	for _p in 10:
		m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	hips = m.boy.lie_bone_world("mixamorig_Hips")
	knee = m.boy.lie_bone_world("mixamorig_LeftLeg")
	ankle = m.boy.lie_bone_world("mixamorig_LeftFoot")
	sit_look = (hips + knee + ankle) * 0.33
	await _cam_shot(m, vp, "hammock_sit_night", sit_look,
		sit_look + side * 2.8 + along * 0.15 + Vector3(0, 0.85, 0))
	m.boy.restore_pose_mesh()

	# Day again for hold/exit
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 80:
			await process_frame

	# HOLD: lie in cradle with fabric load + contact snap (no poke-through)
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	for _p in 36:
		var pl2 = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl2)
		m._update_hammock_load()
		m._snap_lie_contact()
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	# Extra lift passes if mesh still penetrates
	for _lift in 8:
		var md: float = m.lie_mesh_penetration_depth(true)
		if md >= -0.008:
			break
		m.rest_lie += Vector3.UP * minf(-md, 0.04)
		var pl3 = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
		m._update_hammock_load()
		await process_frame
	m.boy.set_face_expr("sleep")
	for _i in 10:
		m.boy._update_face(0.1)
		await process_frame
	m.boy.bake_pose_mesh()
	m.boy._set_eyes_closed(true)
	hips = m.boy.lie_bone_world("mixamorig_Hips")
	var head_b: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var hold_look: Vector3 = hips.lerp(head_b, 0.45)
	await _cam_shot(m, vp, "hammock_hold", hold_look,
		hold_look + side * 3.0 + Vector3(0, 1.1, 0))
	m.boy.restore_pose_mesh()

	# EXIT: sit on edge again (not walking through fabric)
	m.rest_phase = 6
	m.boy.set_face_expr("smile")
	m.boy._set_eyes_closed(false)
	for _p in 16:
		m.boy.activity("sleep", 0.85, 0.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	hips = m.boy.lie_bone_world("mixamorig_Hips")
	knee = m.boy.lie_bone_world("mixamorig_LeftLeg")
	sit_look = (hips + knee) * 0.5
	await _cam_shot(m, vp, "hammock_exit", sit_look,
		sit_look + side * 2.6 + along * 0.2 + Vector3(0, 0.9, 0))
	m.boy.restore_pose_mesh()
	m.island.set_hammock_load([] as Array[Vector3])
	for mi3 in hidden:
		(mi3 as MeshInstance3D).visible = true
	m.rest_frozen = false
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()
	m.boy._set_eyes_closed(false)

	# ---- face_sleep: standing frontal close-up so closed-eye albedo is verifiable ----
	m.rest_frozen = false
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()
	m._place(Vector3(2.0, 0.0, -6.0), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	# Reload closed-eye albedo (PNG may have been updated since boot).
	m.boy._boy_albedo_tex_sleep = null
	m.boy._eyes_closed_tex = false
	m.boy.set_face_expr("sleep")
	m.boy.act_kind = "sleep"
	m.boy.act_lie_k = 1.0
	for _i in 24:
		m.boy._update_face(0.1)
		m.boy._set_eyes_closed(true)
		await process_frame
	m.boy.bake_pose_mesh()
	m.boy._set_eyes_closed(true)
	m.island.visible = false
	var sk: Skeleton3D = m.boy.skel
	var bi: int = sk.find_bone("mixamorig_Head")
	sk.force_update_transform()
	var hx: Transform3D = sk.global_transform * sk.get_bone_global_pose(bi)
	var head: Vector3 = hx.origin
	# yaw=0 → character faces world −Z; pull back so both eyes read.
	if m.boy.face_fill:
		m.boy.face_fill.light_energy = 0.25
	var look_f: Vector3 = head + Vector3(0.0, -0.02, 0.0)
	var cam_f: Vector3 = look_f + Vector3(0.03, 0.01, -0.58)
	await _cam_shot(m, vp, "face_sleep", look_f, cam_f)
	m.island.visible = true
	m.boy.restore_pose_mesh()
	m.boy.set_face_expr("smile")
	m.boy._set_eyes_closed(false)
	m.boy.end_activity()

	# ---- Walk / run filmstrips ----
	await _gait(m, vp, "walk", 1.25)
	await _gait(m, vp, "run", 2.25)
	print("FINISH done")
	quit(0)


func _hide_occluders(m, hh0: Vector3, hidden: Array) -> void:
	for n in m.island.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		var d: float = mi.global_position.distance_to(hh0)
		var nm := String(mi.name).to_lower()
		if d < 5.0 and d > 0.35 and ("palm" in nm or "树" in String(mi.name) or "bush" in nm or "叶" in String(mi.name)):
			hidden.append(mi)
			mi.visible = false
			continue
		if mi.mesh == null:
			continue
		var aabb: AABB = mi.get_aabb()
		var world_size: Vector3 = aabb.size * mi.global_transform.basis.get_scale().abs()
		if d < 5.5 and world_size.y > 1.6 and maxf(world_size.x, world_size.z) < 1.6:
			hidden.append(mi)
			mi.visible = false


func _cam_shot(m, vp, name: String, target: Vector3, cam_from: Vector3) -> void:
	var to: Vector3 = target - cam_from
	m.demo_cam = true
	m.cam_fixed = true
	m.cam_target = target
	m.cam_yaw = atan2(-to.x, -to.z)
	m.cam_pitch = asin(clampf((-to).normalized().y, -0.55, 0.55))
	m.cam_dist = cam_from.distance_to(target)
	for _i in 10:
		if m.mode == m.Mode.REST and m.rest_kind == "sleep" and m.rest_phase in [2, 6]:
			m.boy.activity("sleep", 1.0 if m.rest_phase == 2 else 0.85, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			m._update_hammock_load()
		elif m.mode == m.Mode.REST and m.rest_kind == "sleep" and m.rest_phase == 4:
			var plh = m.boy.activity("sleep", 1.0, 1.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * plh)
			m._update_hammock_load()
			m.boy._set_eyes_closed(true)
		if name == "face_sleep":
			m.boy._set_eyes_closed(true)
			m.island.visible = false
		m.cam_target = target
		m.cam_yaw = atan2(-to.x, -to.z)
		m.cam_pitch = asin(clampf((-to).normalized().y, -0.55, 0.55))
		m.cam_dist = cam_from.distance_to(target)
		m._apply_camera()
		await process_frame
	if name.begins_with("hammock") or name == "face_sleep":
		m.boy.bake_pose_mesh()
		if name == "face_sleep" or name == "hammock_hold":
			m.boy._set_eyes_closed(true)
		for _b in 4:
			m._apply_camera()
			await process_frame
	vp.get_texture().get_image().save_png("/workspace/screenshots/v24/%s.png" % name)
	print("SHOT ", name)


func _gait(m, vp, tag: String, speed: float) -> void:
	m._place(Vector3(4, 0, -8), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	for _i in 6:
		await process_frame
	m.boy.anim = "move"
	m.boy.set_move(speed)
	m.boy.move_w = 1.0
	m.boy.act_w = 0.0
	m.boy.run_k = 0.0 if tag == "walk" else 1.0
	m.boy.pivoting = false
	m.boy.has_prev = false
	for _w in 14:
		m.boy.phase = 0.15
		m.boy.move_w = 1.0
		m.boy._apply_mixer()
		m.boy._polish_gait(1.0 / 30.0)
		await process_frame
	var n := 8
	var strip := Image.create(390 * n, 844, false, Image.FORMAT_RGBA8)
	var phases: Array[float] = [0.08, 0.20, 0.32, 0.44, 0.56, 0.68, 0.80, 0.92]
	for f in n:
		m.boy.phase = phases[f]
		m.boy.move_w = 1.0
		m.boy.act_w = 0.0
		m.boy.run_k = 0.0 if tag == "walk" else 1.0
		m.boy.pivoting = false
		m.boy._apply_mixer()
		m.boy._polish_gait(1.0 / 30.0)
		m.boy.bake_pose_mesh()
		var wt: Vector3 = m.player.global_position + Vector3(0, 0.65, 0)
		m.demo_cam = true
		m.cam_fixed = true
		m.cam_target = wt
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.04
		m.cam_dist = 2.5
		for _i in 4:
			m.boy.phase = phases[f]
			m.boy.move_w = 1.0
			m.boy._apply_mixer()
			m.boy._polish_gait(1.0 / 30.0)
			m.boy.bake_pose_mesh()
			m._apply_camera()
			await process_frame
		strip.blit_rect(vp.get_texture().get_image(), Rect2i(0, 0, 390, 844), Vector2i(f * 390, 0))
		m.boy.restore_pose_mesh()
	strip.save_png("/workspace/screenshots/v24/%s_filmstrip.png" % tag)
	print("SHOT ", tag, "_filmstrip")
