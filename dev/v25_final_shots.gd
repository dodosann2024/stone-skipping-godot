extends SceneTree
## Pre-release stills: 390×844, default gameplay camera, HUD on.
## screenshots/v25/final/01_*.png … 09_*.png + final_montage.png

const OUT := "/workspace/screenshots/v25/final"
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
	for i in 80:
		await process_frame
	# Keep HUD; dismiss start overlay only.
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 80:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)
	_day_light(m)
	m._update_ui()

	var imgs: Array = []

	# ── 1. Island overview at start (day) — 观景 camera, sea + dock + hill ──
	await _overview(m, "day")
	imgs.append(await _shot(vp, "01_overview_day.png"))

	# ── 2. Dock mid-throw with stone on water ──
	await _ensure_day(m)
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(0.0, 0, m.island.dock_end_z + 1.55), 0.0)
	m.face_yaw = 0.0
	m.ex_yaw = m.face_yaw + PI
	for _i in 8:
		await process_frame
	m._enter_throw()
	# Finish walk-to-spot
	var t0 := Time.get_ticks_msec()
	while m.throw_walk and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	m.throw_walk = false
	m.player.position = m.throw_spot
	m.player.position.y = Island.DECK_Y + 0.04
	m.boy.global_position = m.player.global_position
	m.boy.set_idle()
	m.aim_yaw = 0.0
	m.cam_aim_yaw = 0.0
	m.aim_pitch = 6.0
	m.aim_tilt = 20.0
	m.power = 0.92
	m.throw_spin = 0.95
	m.aim_src = "script"
	m.state = m.State.READY
	m._update_ui()
	m._throw()
	# Wait until stone is mid-skip ~8–12 m ahead so both boy + stone read in frame.
	t0 = Time.get_ticks_msec()
	while m.state != m.State.FLYING and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	for _i in 160:
		if m.state != m.State.FLYING:
			break
		var d_st: float = Vector2(m.stone.position.x - m.player.global_position.x, m.stone.position.z - m.player.global_position.z).length()
		if m.skips >= 1 and d_st >= 7.5 and d_st <= 14.0:
			break
		if m.skips >= 1 and d_st > 14.0:
			break
		await process_frame
	# THROW mode ignores cam_fixed and follows the stone — pin with demo_cam so
	# the boy stays on the dock in frame with the stone skipping beyond.
	# Camera sits at target+off(yaw); yaw≈aim keeps cam on land looking seaward.
	# Freeze flight so _process won't yank the stone out of frame while we shoot.
	var kept_skips: int = m.skips
	var kept_dist: float = m.throw_dist
	m.state = m.State.READY
	m.demo_cam = true
	m.cam_fixed = false
	m.cam_target = m.player.global_position + Vector3(0, 0.85, 0)
	m.cam_yaw = m.aim_yaw + 0.12
	m.cam_pitch = 0.22
	m.cam_dist = 6.2
	var fwd := Vector3(-sin(m.aim_yaw), 0.0, -cos(m.aim_yaw))
	var stone_at: Vector3 = m.player.global_position + fwd * 8.5 + Vector3(-0.35, 0.14, 0)
	m.stone.visible = true
	m.stone.position = stone_at
	m.stone_pos = stone_at
	# Slightly larger than gameplay so the skip reads at 390px width.
	m.stone.scale = Vector3(1.6, 0.55, 1.4)
	m.skips = maxi(kept_skips, 1)
	m.throw_dist = maxf(kept_dist, 9.5)
	m._update_ui()
	for _i in 8:
		m._apply_camera()
		m.stone.position = stone_at
		m.stone_pos = stone_at
		m.stone.visible = true
		await process_frame
	imgs.append(await _shot(vp, "02_dock_throw.png"))
	# Cleanup throw
	m.demo_cam = false
	m.stone.visible = false
	m.stone.scale = Vector3(0.7, 0.24, 0.6)
	m.state = m.State.READY
	m.mode = m.Mode.EXPLORE
	m.boy.set_idle()
	m._hide_preview()

	# ── 3. Walking on beach path (sand by the dock, ocean in view) ──
	await _ensure_day(m)
	var path_p := Vector3(1.8, 0, m.island.dock_start_z + 3.2)
	# Face along the shore toward the campfire / lighthouse side so the path reads,
	# with the open sea on one side of frame.
	var face_to := atan2(-0.35, -0.9)
	m._place(path_p, face_to)
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.mode = m.Mode.EXPLORE
	m.demo_mode = true
	m.demo_input = Vector2(0.0, -1.0)
	m.demo_run = false
	m.ex_yaw = m.face_yaw + PI + 0.25
	m.ex_pitch = 0.18
	m.ex_dist = 4.8
	for _i in 35:
		await process_frame
	m.demo_input = Vector2.ZERO
	m.demo_mode = false
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.boy.set_move(1.15)
	m.boy._tick(0.0)
	for _i in 8:
		await process_frame
	imgs.append(await _shot(vp, "03_walk_path.png"))
	m.boy.set_idle()

	# ── 4. Bench sit idle ──
	await _ensure_day(m)
	await _sit_seat(m, "长椅")
	for _i in 10:
		await process_frame
	imgs.append(await _shot(vp, "04_bench_sit.png"))
	m._finish_rest_exit()
	for _i in 20:
		await process_frame

	# ── 5. Log sit by fire ──
	await _ensure_day(m)
	await _sit_seat(m, "坐木")
	for _i in 10:
		await process_frame
	imgs.append(await _shot(vp, "05_log_sit.png"))
	m._finish_rest_exit()
	for _i in 20:
		await process_frame

	# ── 6. Hammock sleep ──
	await _ensure_day(m)
	m.mode = m.Mode.EXPLORE
	m._begin_rest("sleep")
	m.rest_frozen = true
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(3.0)
	m._sync_hammock_cloth_to_boy()
	m.boy.set_face_expr("sleep")
	m.boy.expr = "sleep"
	m.boy._apply_face_pack("sleep")
	m.boy._tick(0.0)
	# Let rest camera settle (default gameplay rest cam)
	m.rest_cam_yaw = INF
	m.demo_cam = false
	m.cam_fixed = false
	for _i in 40:
		await process_frame
	m._update_ui()
	imgs.append(await _shot(vp, "06_hammock_sleep.png"))
	m._finish_rest_exit()
	for _i in 25:
		await process_frame

	# ── 7. Same overview at sunset ──
	await _overview(m, "sunset")
	imgs.append(await _shot(vp, "07_overview_sunset.png"))

	# ── 8. Same overview at night ──
	await _overview(m, "night")
	imgs.append(await _shot(vp, "08_overview_night.png"))

	# ── 9. Face close-up smile ──
	await _ensure_day(m)
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(1.2, 0, m.island.dock_start_z + 3.5), 0.2)
	m.face_yaw = 0.2
	m.boy.rotation.y = m.face_yaw
	m.boy.set_idle()
	m.boy.set_face_expr("smile")
	m.boy.expr = "smile"
	m.boy._apply_face_pack("smile")
	m.boy._tick(0.0)
	for _i in 8:
		await process_frame
	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	# Tight default-style framing on the face (still gameplay cam feel, HUD on)
	m.demo_cam = false
	m.cam_fixed = true
	m.fix_target = head + Vector3(0, 0.02, 0)
	m.fix_yaw = m.face_yaw + PI + 0.35
	m.fix_pitch = 0.08
	m.fix_dist = 1.05
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	m._update_ui()
	for _i in 10:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "09_face_smile.png"))

	_montage(imgs, "final_montage.png")
	print("FINAL_SHOTS_DONE")
	quit(0)


func _day_light(m) -> void:
	m.sun.rotation_degrees = Vector3(-42, 35, 0)
	m.sun.light_color = Color(1.0, 0.95, 0.85)
	m.sun.light_energy = 1.25
	if m.env:
		m.env.tonemap_exposure = 1.05
		m.env.fog_light_color = Color(0.75, 0.85, 0.95)


func _sunset_light(m) -> void:
	m.sun.rotation_degrees = Vector3(-8, 55, 0)
	m.sun.light_color = Color(1.0, 0.48, 0.22)
	m.sun.light_energy = 1.4
	if m.env:
		m.env.tonemap_exposure = 1.15
		m.env.fog_light_color = Color(1.0, 0.55, 0.32)


func _ensure_day(m) -> void:
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 70:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)
	_day_light(m)
	m.mode = m.Mode.EXPLORE
	m.demo_cam = false
	m.cam_fixed = false
	m._update_ui()
	for _i in 6:
		await process_frame


func _overview(m, tod: String) -> void:
	# Start-of-game beach spot; 观景 framing that shows dock → sea and the hill/lighthouse.
	var sp := Vector3(1.35, 0, m.island.dock_start_z + 4.0)
	m.mode = m.Mode.EXPLORE
	m._place(sp, 0.15)
	m.face_yaw = 0.15
	m.ex_yaw = m.face_yaw + PI + 0.45
	m.ex_pitch = 0.22
	m.ex_dist = 4.0
	for _i in 6:
		await process_frame
	# Enter 观景 (player-facing overview)
	if m.mode != m.Mode.VIEW:
		m._toggle_view()
	# Look from open water toward the island (dock into the frame, hill + lighthouse).
	# yaw≈2.85 ≈ looking inland/up-coast so sea fills the left and the island the right.
	m.view_yaw = 2.95
	m.view_pitch = 0.28
	m.view_dist = 32.0
	m.orbit_vel = Vector2.ZERO
	if tod == "day":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 70:
				await process_frame
		m.night_k = 0.0
		m._update_night(0.0, true)
		_day_light(m)
	elif tod == "sunset":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 70:
				await process_frame
		m.night_k = 0.0
		m._update_night(0.0, true)
		_sunset_light(m)
	else:
		if not m.night_on:
			m.night_btn.pressed.emit()
		for _i in 100:
			await process_frame
		m.night_k = 1.0
		m._update_night(0.0, true)
	m._update_ui()
	for _i in 25:
		await process_frame


func _sit_seat(m, seat_name: String) -> void:
	var bi := 0
	var best_d := -1.0
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		if String(st["name"]) != seat_name:
			continue
		if seat_name == "坐木":
			var d: float = (st["top"] as Vector3).distance_to(m.island.campfire_pos)
			if d > best_d:
				best_d = d
				bi = i
		else:
			bi = i
			break
	var st2: Dictionary = m.island.seats[bi]
	m.seat_i = bi
	m.seat_ap = st2["approach"]
	m.seat_face = st2["face"]
	m.mode = m.Mode.EXPLORE
	m._begin_rest("seat")
	m.rest_frozen = true
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(2.5)
	m.boy._tick(0.0)
	# Game picks front 3/4 face framing + LOS (do not override rest_cam_yaw).
	m.rest_cam_yaw = INF
	m.rest_cam_ease = 0.0
	m.demo_cam = false
	m.cam_fixed = false
	m._update_ui()
	# ~0.8 s ease onto the sit framing.
	for _i in 40:
		await process_frame


func _shot(vp, name: String) -> Image:
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("null shot " + name)
		return null
	# Marker pixels (same convention as other capture scripts)
	img.set_pixel(0, 0, Color(0.91, 0.12, 0.74, 1.0))
	img.set_pixel(1, 0, Color(0.12, 0.91, 0.55, 1.0))
	img.set_pixel(0, 1, Color(0.95, 0.85, 0.10, 1.0))
	var path := "%s/%s" % [OUT, name]
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
	return img


func _montage(imgs: Array, out_name: String) -> void:
	var n: int = imgs.size()
	if n == 0:
		return
	var strip := Image.create(W * n, H, false, Image.FORMAT_RGBA8)
	for i in n:
		var img: Image = imgs[i]
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(0, 0, mini(W, img.get_width()), mini(H, img.get_height())), Vector2i(i * W, 0))
	strip.save_png("%s/%s" % [OUT, out_name])
	print("MONTAGE ", out_name)
