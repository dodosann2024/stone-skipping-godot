extends SceneTree
## v27 verification stills — day path (user spot), day beach, night beach/campfire/forest/dock.
## screenshots/v27/*.png — no docs/ export.

const OUT := "/workspace/screenshots/v27"
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
	# Full-res stills for visual review (timing uses mobile ladder separately).
	m.mq.setup(false, false, vp, m.sun)
	m.refl_auto = false
	m._set_refl_level(0)
	if m.boy:
		m.boy.show_stone(false)

	# Day path — user iPhone dirt-path spot
	await _set_tod(m, "day")
	var path_p := Vector3(-0.55, 0.0, 6.15)
	path_p.y = m._surface(path_p.x, path_p.z)
	m._place(path_p, 0.35)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.22
	m.ex_dist = 4.2
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	for _i in 35:
		await process_frame
	await _shot(vp, "day_path.png")

	# Day beach
	m._place(Vector3(1.6, 0, m.island.dock_start_z + 3.5), 0.2)
	m.ex_yaw = m.face_yaw + PI + 0.2
	m.ex_pitch = 0.20
	m.ex_dist = 5.0
	for _i in 25:
		await process_frame
	await _shot(vp, "day_beach.png")

	# Night beach
	await _set_tod(m, "night")
	var beach: Vector3 = m.island.shore_pt(-0.85, 1.7)
	m._place(beach, 0.12)
	m.ex_yaw = m.face_yaw + PI + 0.05
	m.ex_pitch = 0.28
	m.ex_dist = 4.6
	for _i in 40:
		await process_frame
	await _shot(vp, "night_beach.png")

	# Night campfire
	var fire: Vector3 = m.island.campfire_pos
	m._place(fire + Vector3(1.05, 0, 0.35), atan2(-1.05, -0.35))
	m.ex_yaw = m.face_yaw + PI + 0.55
	m.ex_pitch = 0.18
	m.ex_dist = 3.6
	for _i in 35:
		await process_frame
	await _shot(vp, "night_campfire.png")

	# Night forest path
	m._place(path_p, 0.35)
	m.ex_yaw = m.face_yaw + PI + 0.15
	m.ex_pitch = 0.24
	m.ex_dist = 4.0
	for _i in 40:
		await process_frame
	await _shot(vp, "night_forest_path.png")

	# Night dock
	m._place(Vector3(0.8, 0, m.island.dock_start_z + 1.5), 0.0)
	if m.mode != m.Mode.VIEW:
		m._toggle_view()
	m.view_yaw = 0.55
	m.view_pitch = 0.20
	m.view_dist = 36.0
	for _i in 40:
		await process_frame
	await _shot(vp, "night_dock.png")

	print("V27_SHOTS_DONE")
	quit(0)


func _set_tod(m, tod: String) -> void:
	if tod == "day":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 80:
				await process_frame
		m.night_k = 0.0
		m._update_night(0.0, true)
	elif tod == "night":
		if not m.night_on:
			m.night_btn.pressed.emit()
			for _i in 90:
				await process_frame
		m.night_k = 1.0
		m._update_night(1.0, true)
	for _i in 10:
		await process_frame


func _shot(vp: Viewport, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.save_png("%s/%s" % [OUT, name])
	print("SHOT ", name)
