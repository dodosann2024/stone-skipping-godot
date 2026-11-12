extends SceneTree
## Capture start-face, sunbathing, hammock, face close-up after color/pose polish

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	for i in 50:
		await process_frame
	m._start_audio()
	m.demo_mode = true
	_clear_overlays(m)
	await m.get_tree().create_timer(0.4).timeout

	# 1) start face (no UI overlays)
	m._snap_explore_cam(true)
	m._apply_camera()
	for i in 20:
		await m.get_tree().process_frame
	_clear_overlays(m)
	_save(vp, "/workspace/screenshots/v22/web_start_face.png")
	print("START face_yaw", m.face_yaw, "ex_yaw", m.ex_yaw)

	# 2) face close-up under game lighting
	m.ui_root.visible = false
	var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
	m.cam_target = head + Vector3(0, -0.02, 0)
	m.cam_yaw = m.face_yaw + PI + 0.28
	m.cam_pitch = -0.02
	m.cam_dist = 0.68
	m._apply_camera()
	for i in 12:
		await m.get_tree().process_frame
	_save(vp, "/workspace/screenshots/v22/face_lit_closeup.png")
	_clear_overlays(m)
	print("FACE fill", m.boy.face_fill.light_energy if m.boy.face_fill else -1)
	_sample_mat(m)

	# 3) sunbathing
	await _force_lie(m, "sun")
	_clear_overlays(m)
	var pel: Vector3 = (m.boy.parts["pelvis"] as Node3D).global_position
	var head2: Vector3 = (m.boy.parts["head"] as Node3D).global_position
	var along_s: Vector3 = (head2 - pel).normalized()
	var side_s: Vector3 = Vector3.UP.cross(along_s).normalized()
	m.cam_target = (pel + head2) * 0.5 + Vector3(0, 0.05, 0)
	m.cam_yaw = atan2(side_s.x, side_s.z) + 0.15
	m.cam_pitch = 0.12
	m.cam_dist = 2.55
	m._apply_camera()
	for i in 10:
		await m.get_tree().process_frame
	_clear_overlays(m)
	_save(vp, "/workspace/screenshots/v22/05_sunbathing.png")
	_print_arms(m, "SUN")
	print("SUN pel", pel, "head", head2)

	m.boy.end_activity()
	m.mode = m.Mode.EXPLORE
	m.rest_phase = 0
	m.zzz.visible = false
	await m.get_tree().create_timer(0.3).timeout

	# 4) hammock — no start overlay
	await _force_lie(m, "sleep")
	_clear_overlays(m)
	pel = (m.boy.parts["pelvis"] as Node3D).global_position
	head2 = (m.boy.parts["head"] as Node3D).global_position
	var along: Vector3 = (m.island.hammock_b - m.island.hammock_a).normalized()
	var hside: Vector3 = along.cross(Vector3.UP).normalized()
	m.cam_target = (pel + head2) * 0.5
	m.cam_yaw = atan2(hside.x, hside.z) + 0.2
	m.cam_pitch = 0.22
	m.cam_dist = 2.85
	m._apply_camera()
	for i in 12:
		await m.get_tree().process_frame
	_clear_overlays(m)
	# one blank frame after squash so the previous zzz glyphs leave the framebuffer
	await m.get_tree().process_frame
	_clear_overlays(m)
	_save(vp, "/workspace/screenshots/v22/06_hammock.png")
	_print_arms(m, "HAM")
	print("HAM pel", pel, "head", head2)
	print("SHOTS_DONE")
	quit(0)

func _clear_overlays(m) -> void:
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.audio_started = true
	if m.tip_box:
		m.tip_box.visible = false
	m.tip_timer = 0.0
	if m.lbl_toast:
		m.lbl_toast.modulate.a = 0.0
		m.toast_timer = 0.0
	# hide all HUD so screenshots have no title / buttons / hint bar
	if m.ui_root:
		m.ui_root.visible = false
	# rest _process forces zzz.visible every frame — squash so glyphs never draw
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.scale = Vector3.ZERO
		m.zzz.visible = false
		m.zzz.text = ""
		m.zzz.modulate.a = 0.0

func _force_lie(m, kind: String) -> void:
	m.boy.end_activity()
	m.mode = m.Mode.EXPLORE
	m.rest_phase = 0
	m.seat_lying = false
	m.zzz.visible = false
	if kind == "sun":
		m._place(m.island.towel_pos + m.island.towel_dir * 0.4, 0.0)
	else:
		var hs: Array = m._hammock_spot()
		m._place(hs[0] + hs[2] * 1.2, atan2(-hs[2].x, -hs[2].z))
	await m.get_tree().create_timer(0.15).timeout
	m._begin_rest(kind)
	m.rest_phase = 4
	m.rest_t = 0.0
	m.swing_amp = 0.05 if kind == "sleep" else 0.0
	m._update_ui()
	_clear_overlays(m)
	for i in 30:
		var pl: Vector3 = m.boy.activity(kind, 1.0, 1.0, m.gt)
		var swing := Transform3D.IDENTITY
		if kind == "sleep":
			swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		m.gt += 1.0 / 30.0
		await m.get_tree().process_frame
	await m.get_tree().create_timer(0.35).timeout

func _print_arms(m, tag: String) -> void:
	var sk: Skeleton3D = m.boy.skel
	for bn in ["mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_LeftForeArm", "mixamorig_RightForeArm", "mixamorig_Head", "mixamorig_Hips"]:
		var g: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn))
		print(tag, " ", bn, " ", g.origin)

func _sample_mat(m) -> void:
	for c in m.boy.skel.get_children():
		if c is MeshInstance3D:
			var mat: StandardMaterial3D = (c as MeshInstance3D).material_override as StandardMaterial3D
			if mat:
				print("MAT emission", mat.emission_enabled, mat.emission_energy_multiplier,
					" metal", mat.metallic, " transp", mat.transparency, " alpha", mat.albedo_color.a)

func _save(vp: Viewport, path: String) -> void:
	var img: Image = vp.get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
