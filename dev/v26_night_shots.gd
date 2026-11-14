extends SceneTree
## v26 night lighting verification stills — 390×844 default gameplay cam + HUD.
## screenshots/v26/{day,sunset,night_*}.png — no docs/ export.

const OUT := "/workspace/screenshots/v26"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 90:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	if m.boy:
		m.boy.show_stone(false)

	# Day regression near dock path
	await _set_tod(m, "day")
	m._place(Vector3(1.6, 0, m.island.dock_start_z + 3.5), 0.2)
	m.ex_yaw = m.face_yaw + PI + 0.2
	m.ex_pitch = 0.20
	m.ex_dist = 5.0
	for _i in 20:
		await process_frame
	await _shot(vp, "day_beach.png")

	# Sunset
	await _set_tod(m, "sunset")
	m._place(Vector3(1.6, 0, m.island.dock_start_z + 3.5), 0.2)
	m.ex_yaw = m.face_yaw + PI + 0.25
	for _i in 25:
		await process_frame
	await _shot(vp, "sunset_beach.png")

	# Night: open moonlit sand — shared spot so boy/sand share the same key.
	await _set_tod(m, "night")
	var beach: Vector3 = m.island.shore_pt(-0.85, 1.7)
	m._place(beach, 0.12)
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.island.foliage_mat.set_shader_parameter("cut_radius", 3.4)
	m.island.leaf_mat.set_shader_parameter("cut_radius", 3.4)
	m.island.static_mat.set_shader_parameter("cut_radius", 3.4)
	m.ex_yaw = m.face_yaw + PI + 0.05
	m.ex_pitch = 0.28
	m.ex_dist = 4.6
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m.island.foliage_mat.set_shader_parameter("cut_radius", 3.8)
	m.island.leaf_mat.set_shader_parameter("cut_radius", 3.8)
	m.island.static_mat.set_shader_parameter("cut_radius", 3.8)
	for _i in 45:
		m._cam_arm_k = 1.0
		m._cam_arm_want = 1.0
		await process_frame
	await _shot(vp, "night_beach_boy.png")
	# Clear: same feet, slight yaw change only.
	m.ex_yaw = m.face_yaw + PI + 0.22
	m.ex_pitch = 0.28
	m.ex_dist = 5.0
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	for _i in 35:
		m._cam_arm_k = 1.0
		m._cam_arm_want = 1.0
		await process_frame
	await _shot(vp, "night_beach_clear.png")

	# Night: near campfire — face the flames so warm Omni keys the skin
	var fire: Vector3 = m.island.campfire_pos
	var to_fire := fire - (fire + Vector3(1.05, 0, 0.35))
	m._place(fire + Vector3(1.05, 0, 0.35), atan2(-to_fire.x, -to_fire.z))
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.ex_yaw = m.face_yaw + PI + 0.55
	m.ex_pitch = 0.18
	m.ex_dist = 3.6
	for _i in 30:
		await process_frame
	await _shot(vp, "night_campfire.png")

	# Night: dock overview — look toward the moon over open water; lighthouse stays in frame.
	m._place(Vector3(0.8, 0, m.island.dock_start_z + 1.5), 0.0)
	if m.mode != m.Mode.VIEW:
		m._toggle_view()
	# Moon dir ≈ (-0.43, 0.24, -0.87) → look seaward so the glitter path is on-screen.
	m.view_yaw = 0.55
	m.view_pitch = 0.20
	m.view_dist = 36.0
	for _i in 40:
		await process_frame
	await _shot(vp, "night_dock_overview.png")
	if m.mode == m.Mode.VIEW:
		m._toggle_view()

	# Night: path lantern — first inland lamp; hanging open-cage lantern midground.
	# LB / static_nocut so cut-out never dissolves the cage. Dim porch so only path Omni keys.
	m.mode = m.Mode.EXPLORE
	var lamp_p := Vector3(-3.08, 2.42, -9.02)
	for L in m.island.lamps:
		if str(L[1]) == "path":
			lamp_p = L[0] as Vector3
			break
	for i in m.night_fx.lamp_kinds.size():
		if m.night_fx.lamp_kinds[i] == "porch":
			m.night_fx.lamp_energy[i] = 0.0
	var path_p := lamp_p
	var best_pd := 999.0
	for i in 24:
		var a := float(i) * TAU / 24.0
		var t := Vector3(lamp_p.x + cos(a) * 1.35, 0.0, lamp_p.z + sin(a) * 1.35)
		var pd: float = m.island.path_dist(t.x, t.z)
		if pd < best_pd:
			best_pd = pd
			path_p = t
	path_p.y = m._surface(path_p.x, path_p.z)
	var to_lamp: Vector3 = lamp_p - path_p
	to_lamp.y = 0.0
	m._place(path_p, atan2(-to_lamp.x, -to_lamp.z) + 0.15)
	var along := Vector3(-to_lamp.z, 0.0, to_lamp.x).normalized()
	var mid := path_p.lerp(Vector3(lamp_p.x, path_p.y, lamp_p.z), 0.30) + Vector3(0, 0.78, 0)
	var yaw := atan2(-along.x, -along.z) + PI * 0.92
	m.island.foliage_mat.set_shader_parameter("cut_radius", 7.5)
	m.island.leaf_mat.set_shader_parameter("cut_radius", 7.5)
	m.island.static_mat.set_shader_parameter("cut_radius", 1.4)
	m._fixed_cam(mid, yaw, 0.32, 5.2)
	m.cam_fixed = true
	for _i in 55:
		for i in m.night_fx.lamp_kinds.size():
			if m.night_fx.lamp_kinds[i] == "porch":
				m.night_fx.lamp_energy[i] = 0.0
				m.night_fx.lamp_lights[i].light_energy = 0.0
		m._fixed_cam(mid, yaw, 0.32, 5.2)
		await process_frame
	await _shot(vp, "night_forest_path.png")

	print("V26_NIGHT_SHOTS_DONE")
	quit(0)


func _set_tod(m, tod: String) -> void:
	if tod == "day":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 80:
				await process_frame
		m.night_k = 0.0
		m._update_night(0.0, true)
	elif tod == "sunset":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 80:
				await process_frame
		# Hold mid-transition so sunset lobe is active.
		m.night_on = true
		m.night_k = 0.38
		m._update_night(0.0, true)
	else:
		if not m.night_on:
			m.night_btn.pressed.emit()
		for _i in 100:
			await process_frame
		m.night_k = 1.0
		m._update_night(0.0, true)
	m._update_ui()
	for _i in 8:
		await process_frame


func _shot(vp, name: String) -> void:
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("null " + name)
		return
	img.set_pixel(0, 0, Color(0.91, 0.12, 0.74, 1.0))
	img.set_pixel(1, 0, Color(0.12, 0.91, 0.55, 1.0))
	img.set_pixel(0, 1, Color(0.95, 0.85, 0.10, 1.0))
	var path := "%s/%s" % [OUT, name]
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
