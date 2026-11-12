extends SceneTree
## Night lighting verification shots at 390x844, no HUD.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 50:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz:
		m.zzz.visible = false

	# Force full night.
	m.night_on = true
	m.night_k = 1.0
	m._update_night(0.0, true)
	for i in 20:
		await process_frame

	var shots: Array = []
	# Dock end by lantern
	if m.island.lamps.size() > 0:
		var dock_p: Vector3 = m.island.lamps[0][0]
		for l in m.island.lamps:
			if str(l[1]) == "dock":
				dock_p = l[0]
				break
		m._place(dock_p + Vector3(0.8, 0, 1.2), atan2(-0.3, -1.0))
		shots.append(["night_dock", dock_p + Vector3(0.2, 1.1, 0.4), atan2(0.8, 1.2), 0.18, 2.4])
	# Hill / path
	var path_p := Vector3(0, 0, 0)
	if m.island.hut_pos != Vector3.ZERO:
		path_p = m.island.hut_pos + Vector3(2.0, 0, 3.0)
		path_p.y = Island.ground_h(path_p.x, path_p.z)
	else:
		path_p = Vector3(4, 0, -6)
		path_p.y = Island.ground_h(path_p.x, path_p.z)
	m._place(path_p, 0.4)
	shots.append(["night_path", path_p + Vector3(0, 1.0, 0), 0.4, 0.2, 3.0])
	# Beach facing moon
	var beach := Vector3(8, 0, -12)
	beach.y = Island.ground_h(beach.x, beach.z)
	m._place(beach, PI)
	var moon_yaw := atan2(m.sun.global_basis.z.x, m.sun.global_basis.z.z)
	shots.append(["night_beach", beach + Vector3(0, 1.0, 0), moon_yaw + PI, 0.15, 2.8])

	# Apply night again after placing
	m.night_on = true
	m.night_k = 1.0
	m._update_night(0.0, true)
	for s in shots:
		m.cam_target = s[1]
		m.cam_yaw = s[2]
		m.cam_pitch = s[3]
		m.cam_dist = s[4]
		m._apply_camera()
		for _i in 12:
			await process_frame
		var path := "/workspace/screenshots/v23/%s.png" % s[0]
		vp.get_texture().get_image().save_png(path)
		print("SHOT ", path)

	# One daytime control shot
	m.night_on = false
	m.night_k = 0.0
	m._update_night(0.0, true)
	m._place(beach, 0.0)
	m.cam_target = beach + Vector3(0, 1.0, 0)
	m.cam_yaw = 0.5
	m.cam_pitch = 0.2
	m.cam_dist = 2.8
	m._apply_camera()
	for _i in 12:
		await process_frame
	vp.get_texture().get_image().save_png("/workspace/screenshots/v23/day_beach.png")
	print("SHOT day_beach")
	print("night_k", m.night_k, " fill", m.boy.face_fill.light_energy if m.boy.face_fill else -1,
		" sun_e", m.sun.light_energy, " lamps", m.night_fx.lamp_lights.size())
	quit(0)
