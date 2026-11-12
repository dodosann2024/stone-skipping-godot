extends SceneTree
## Night lighting verification shots at 390x844, no HUD.
## Spots match the live-v22 references: dock lantern, hill path, beach+moon.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 55:
		await process_frame
	m.demo_mode = true
	m.demo_cam = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz:
		m.zzz.visible = false

	m.night_on = true
	m.night_k = 1.0
	m._update_night(0.0, true)
	for i in 25:
		await process_frame

	var moon: Vector3 = m.sun.global_basis.z.normalized()
	print("MOON", moon, "e", m.sun.light_energy, "opac", m.sun.shadow_opacity,
		"amb", m.env.ambient_light_energy, "lamps", m.night_fx.lamp_lights.size())

	# --- 1) Dock end by lantern (gameplay-style follow, lantern in frame) ---
	var dock_lamp: Vector3 = Vector3.ZERO
	for l in m.island.lamps:
		if str(l[1]) == "dock":
			dock_lamp = l[0]
			break
	# Stand on the deck near the lantern, facing the sea (yaw ~ 0 faces -Z).
	var dock_stand := Vector3(clampf(dock_lamp.x * 0.45, -1.6, 1.6), 0.0, m.island.dock_end_z + 1.55)
	m._place(dock_stand, 0.05)
	m.demo_cam = true
	# Slight 3/4 behind so the lantern-side of the boy (warm) faces the camera.
	var dock_target: Vector3 = m.player.global_position + Vector3(0, 1.05, 0)
	var dock_yaw: float = m.face_yaw + 0.55
	await _shot(m, vp, "night_dock", dock_target, dock_yaw, 0.14, 2.5)
	_print_lamp(m, "DOCK")

	# --- 2) Hill path (follow-behind, palm moon shadows) ---
	var path_p: Vector3 = m.island.hut_pos + Vector3(3.5, 0, 5.0)
	path_p.y = Island.ground_h(path_p.x, path_p.z)
	var path_face: float = atan2(-(path_p.x - 2.0), -(path_p.z + 8.0))
	m._place(path_p, path_face)
	m.demo_cam = true
	await _shot(m, vp, "night_path", m.player.global_position + Vector3(0, 1.05, 0), path_face, 0.22, 3.3)
	_print_lamp(m, "PATH")

	# --- 3) Beach facing moon: boy faces camera, moon behind ---
	var beach := Vector3(1.8, 0, m.island.dock_start_z + 4.5)
	beach.y = Island.ground_h(beach.x, beach.z)
	# Face away from moon so moon is behind him. Forward = -basis.z.
	var away := Vector3(-moon.x, 0, -moon.z)
	if away.length_squared() < 0.01:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var beach_face: float = atan2(-away.x, -away.z)
	m._place(beach, beach_face)
	m.demo_cam = true
	# Face-on camera (same idea as game_cam_v22._face_cam).
	var beach_yaw: float = beach_face + PI
	await _shot(m, vp, "night_beach", m.player.global_position + Vector3(0, 1.15, 0), beach_yaw, 0.14, 2.6)

	# --- 4) Day control ---
	m.night_on = false
	m.night_k = 0.0
	m._update_night(0.0, true)
	var day_p := Vector3(1.5, 0, m.island.dock_start_z + 6.0)
	day_p.y = Island.ground_h(day_p.x, day_p.z)
	m._place(day_p, 0.25)
	m.demo_cam = true
	await _shot(m, vp, "day_beach", m.player.global_position + Vector3(0, 1.1, 0), 0.25, 0.20, 3.0)

	print("DONE glow", m.island.glow_mat.get_shader_parameter("boost"),
		"fill", m.boy.face_fill.light_energy, "albedo", m.boy._boy_mat.albedo_color)
	quit(0)


func _print_lamp(m, tag: String) -> void:
	var nearest_d := 999.0
	var nearest_e := 0.0
	for ol in m.night_fx.lamp_lights:
		var d: float = ol.global_position.distance_to(m.player.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest_e = ol.light_energy
	print(tag, " lamp_d", nearest_d, " e", nearest_e, " fill", m.boy.face_fill.light_energy,
		" rim", m.boy._night_rim.light_energy)


func _shot(m, vp, name: String, target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.demo_cam = true
	m.demo_track = []
	m._update_night(0.0, true)
	for _i in 22:
		m.demo_cam = true
		m.cam_target = target
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m.cam_dist = dist
		m._apply_camera()
		await process_frame
	var path := "/workspace/screenshots/v23/%s.png" % name
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path)
