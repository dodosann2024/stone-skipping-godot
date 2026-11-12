extends SceneTree
## Night lighting verification shots at 390x844, no HUD.
## Spots: dock lantern end, hill path by the fence, beach with moon in view.
## Camera: default gameplay follow (behind + above), same as the player sees.

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
	# Do NOT enable demo_mode — that can start the demo tour. Just lock the explore cam.
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz:
		m.zzz.visible = false
	m.mode = m.Mode.EXPLORE
	m.demo_mode = false
	m.demo_cam = false
	m.demo_track = []

	m.night_on = true
	m.night_k = 1.0
	m._update_night(0.0, true)
	for i in 30:
		await process_frame

	var moon: Vector3 = m.sun.global_basis.z.normalized()
	var emis := 0.0
	if m.boy._boy_mat != null:
		emis = m.boy._boy_mat.emission_energy_multiplier
	print("MOON", moon, "e", m.sun.light_energy, "opac", m.sun.shadow_opacity,
		"amb", m.env.ambient_light_energy, "exp", m.env.tonemap_exposure,
		"fill", m.boy.face_fill.light_energy, "rim", m.boy._night_rim.light_energy,
		"emis", emis, "lamps", m.night_fx.lamp_lights.size(),
		"boy_mat", m.boy._boy_mat != null)

	var shot_paths: Array[String] = []
	var shot_pos: Array[Vector3] = []

	# --- 1) Dock end by lantern post (warm light on boy + planks) ---
	var dock_lamp: Vector3 = Vector3.ZERO
	for l in m.island.lamps:
		if str(l[1]) == "dock":
			dock_lamp = l[0]
			break
	# Stand on the open deck beside the lantern post so warm light hits boy + planks.
	# Offset from the post so the follow cam stays clear of the lamp mesh.
	var dock_stand := Vector3(clampf(dock_lamp.x * 0.35, -1.0, 1.0), 0.0, m.island.dock_end_z + 2.05)
	# Face the sea, slightly toward the lantern so the warm side reads in the follow cam.
	var dock_face: float = atan2(-(dock_lamp.x - dock_stand.x) * 0.35, -1.0)
	await _gameplay_shot(m, vp, "night_dock", dock_stand, dock_face)
	shot_paths.append("/workspace/screenshots/v23/night_dock.png")
	shot_pos.append(m.player.global_position)
	_print_lamp(m, "DOCK")
	_print_pos(m, "DOCK")

	# --- 2) Hill path by the fence (paths[1] lighthouse path, upper segment) ---
	var fence_pl: Array = m.island.paths[1]
	# Higher on the hill near the fence (segment toward the lighthouse).
	var a: Vector2 = fence_pl[2]
	var b: Vector2 = fence_pl[3]
	var path_xz: Vector2 = a.lerp(b, 0.55)
	var path_p := Vector3(path_xz.x, 0.0, path_xz.y)
	path_p.y = Island.ground_h(path_p.x, path_p.z)
	var path_dir: Vector2 = (b - a).normalized()
	var path_face: float = atan2(-path_dir.x, -path_dir.y)
	await _gameplay_shot(m, vp, "night_path", path_p, path_face)
	shot_paths.append("/workspace/screenshots/v23/night_path.png")
	shot_pos.append(m.player.global_position)
	_print_lamp(m, "PATH")
	_print_pos(m, "PATH")

	# --- 3) Open beach sand facing the sea, moon in view ---
	# Shore sand near the waterline (not the hill path).
	var beach: Vector3 = m.island.shore_pt(-0.35, 1.2)
	beach.y = Island.ground_h(beach.x, beach.z)
	# Boy faces the moon so the follow-behind camera looks at the moon disk / sea.
	# forward = (-sin(yaw),0,-cos(yaw)) ‖ moon.xz  ⇒  yaw = atan2(-moon.x, -moon.z)
	var moon_h := Vector3(moon.x, 0.0, moon.z)
	if moon_h.length_squared() < 0.01:
		moon_h = Vector3(0, 0, 1)
	moon_h = moon_h.normalized()
	var beach_face: float = atan2(-moon_h.x, -moon_h.z)
	await _gameplay_shot(m, vp, "night_beach", beach, beach_face)
	shot_paths.append("/workspace/screenshots/v23/night_beach.png")
	shot_pos.append(m.player.global_position)
	_print_lamp(m, "BEACH")
	_print_pos(m, "BEACH")

	# --- 4) Day control (same beach spot) ---
	m.night_on = false
	m.night_k = 0.0
	m._update_night(0.0, true)
	await _gameplay_shot(m, vp, "day_beach", beach, 0.25)

	# Uniqueness: positions must be far apart, and PNGs must differ substantially.
	var ok := true
	for i in shot_pos.size():
		for j in range(i + 1, shot_pos.size()):
			var d: float = shot_pos[i].distance_to(shot_pos[j])
			print("POS_DIFF ", i, "-", j, " ", d)
			if d < 3.0:
				print("FAIL spots too close ", i, " ", j, " d=", d)
				ok = false
	# Pixel uniqueness via Image load
	var imgs: Array = []
	for p in shot_paths:
		var img := Image.new()
		var err := img.load(p)
		if err != OK:
			print("FAIL load ", p, " ", err)
			ok = false
			continue
		imgs.append(img)
		print("IMG ", p.get_file(), " ", img.get_width(), "x", img.get_height())
	for i in imgs.size():
		for j in range(i + 1, imgs.size()):
			var mean_d := _mean_abs_diff(imgs[i], imgs[j])
			print("IMG_DIFF ", i, "-", j, " ", mean_d)
			if mean_d < 8.0:
				print("FAIL images too similar ", i, " ", j, " d=", mean_d)
				ok = false

	var alb := Color(0, 0, 0, 1)
	if m.boy._boy_mat != null:
		alb = m.boy._boy_mat.albedo_color
	print("DONE glow", m.island.glow_mat.get_shader_parameter("boost"),
		"fill", m.boy.face_fill.light_energy, "albedo", alb,
		"boy_mat", m.boy._boy_mat != null, "ok", ok)
	quit(0 if ok else 1)


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


func _print_pos(m, tag: String) -> void:
	print(tag, " pos", m.player.global_position, " yaw", m.face_yaw,
		" cam", m.cam_yaw, m.cam_pitch, m.cam_dist)


## Teleport, snap the default gameplay follow camera, settle, capture.
func _gameplay_shot(m, vp, name: String, stand: Vector3, face: float) -> void:
	m.mode = m.Mode.EXPLORE
	m.demo_mode = false
	m.demo_cam = false
	m.demo_track = []
	m._place(stand, face)
	# Default gameplay camera: behind and above (ex_yaw = face_yaw).
	m.ex_yaw = face
	m.ex_pitch = 0.26
	m.ex_dist = 4.5
	m._snap_explore_cam(false)
	m._update_night(0.0, true)
	var moon_dir: Vector3 = m.sun.global_basis.z.normalized()
	m.night_fx.apply(m.night_k, m.camera.global_position, moon_dir, 0.0)
	for _i in 28:
		m.demo_cam = false
		m.demo_track = []
		# Re-assert explore follow each frame so nothing steals the camera.
		m.ex_yaw = m.face_yaw
		m._snap_explore_cam(false)
		m._apply_camera()
		moon_dir = m.sun.global_basis.z.normalized()
		m.night_fx.apply(1.0, m.camera.global_position, moon_dir, 1.0 / 30.0)
		await process_frame
	var path := "/workspace/screenshots/v23/%s.png" % name
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path, " at", m.player.global_position, " cam_yaw", m.cam_yaw)


func _mean_abs_diff(a: Image, b: Image) -> float:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return 999.0
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var w := a.get_width()
	var h := a.get_height()
	var acc := 0.0
	var n := 0
	# Subsample for speed.
	var step := 4
	for y in range(0, h, step):
		for x in range(0, w, step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			acc += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	if n == 0:
		return 0.0
	return (acc / float(n)) * 255.0 / 3.0
