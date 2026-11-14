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

	# Night: forest path — same spot as screenshots/v26/ref/night_forest_path_b3ec.png.
	# Default follow cam, boy facing the camera (3/4-front), face visible; lantern pool beside him.
	# Foliage cut is handled by explore cut_radius (not a special fixed cam).
	m.mode = m.Mode.EXPLORE
	m.cam_fixed = false
	m.demo_cam = false
	m.demo_track = []
	# Geographic match to the user ref (fence path on the lighthouse climb).
	var ref_p := Vector3(-0.8, 0, 6.5)
	var lamp_p := ref_p
	var best_ld := 999.0
	for L in m.island.lamps:
		if str(L[1]) != "path":
			continue
		var lp: Vector3 = L[0]
		var ld := Vector2(lp.x - ref_p.x, lp.z - ref_p.z).length()
		if ld < best_ld:
			best_ld = ld
			lamp_p = lp
	# Stand on the ref path ~1.05 m from the lantern so the pool reads at his feet.
	var away: Vector3 = Vector3(ref_p.x - lamp_p.x, 0.0, ref_p.z - lamp_p.z)
	if away.length_squared() < 1e-6:
		away = Vector3(-0.6, 0.0, -0.4)
	var path_p: Vector3 = Vector3(lamp_p.x, 0.0, lamp_p.z) + away.normalized() * 1.05
	# Bias toward the ref geographic spot so the fence / uphill path matches the screenshot.
	path_p = path_p.lerp(Vector3(ref_p.x, 0.0, ref_p.z), 0.55)
	path_p.y = m._surface(path_p.x, path_p.z)
	# Face so the camera (3/4-front) sees him and the lantern keys one side.
	var to_lamp: Vector3 = lamp_p - path_p
	to_lamp.y = 0.0
	# Prefer looking down-path (seaward) so the uphill fence stays behind like the ref.
	var face := atan2(-(path_p.x - 2.0), -(path_p.z - 2.5))
	if to_lamp.length_squared() > 1e-6:
		var side := atan2(-to_lamp.x, -to_lamp.z) + PI * 0.55
		face = lerp_angle(face, side, 0.55)
	m._place(path_p, face)
	# Default follow, 3/4-front, closer so he fills the frame like the ref (not tiny in foliage).
	m.ex_yaw = m.face_yaw + PI + 0.35
	m.ex_pitch = 0.18
	m.ex_dist = 3.9
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.72, 0)
	for _i in 55:
		m.ex_yaw = m.face_yaw + PI + 0.35
		m.ex_pitch = 0.18
		m.ex_dist = 3.9
		m.cam_yaw = m.ex_yaw
		m.cam_pitch = m.ex_pitch
		m.cam_dist = m.ex_dist
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
