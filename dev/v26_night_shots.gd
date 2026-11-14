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

	# Night: boy on open beach (match user night_beach_boy framing-ish)
	await _set_tod(m, "night")
	m._place(Vector3(-2.2, 0, m.island.dock_start_z + 1.2), -0.4)
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.ex_yaw = m.face_yaw + PI + 0.15
	m.ex_pitch = 0.18
	m.ex_dist = 4.6
	for _i in 30:
		await process_frame
	await _shot(vp, "night_beach_boy.png")

	# Night: near campfire
	var fire: Vector3 = m.island.campfire_pos
	m._place(fire + Vector3(1.4, 0, 0.6), atan2(-0.2, -1.0))
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.ex_yaw = m.face_yaw + PI + 0.35
	m.ex_pitch = 0.22
	m.ex_dist = 4.8
	for _i in 30:
		await process_frame
	await _shot(vp, "night_campfire.png")

	# Night: dock overview (观景-like framing toward island)
	m._place(Vector3(1.35, 0, m.island.dock_start_z + 4.0), 0.15)
	if m.mode != m.Mode.VIEW:
		m._toggle_view()
	m.view_yaw = 2.95
	m.view_pitch = 0.28
	m.view_dist = 32.0
	for _i in 30:
		await process_frame
	await _shot(vp, "night_dock_overview.png")
	if m.mode == m.Mode.VIEW:
		m._toggle_view()

	# Night: forest path
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(-0.8, 0, 6.5), 0.6)
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.ex_yaw = m.face_yaw + PI + 0.2
	m.ex_pitch = 0.18
	m.ex_dist = 4.5
	for _i in 30:
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
