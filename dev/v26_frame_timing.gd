extends SceneTree
## Record per-frame boy screen delta + camera delta at fixed 60/120 fps.
## Writes CSV + stats under screenshots/v26/timing/; a companion Python plotter draws PNGs.

const OUT := "/workspace/screenshots/v26/timing"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	var args := OS.get_cmdline_user_args()
	var fps := 60
	for a in args:
		if a.begins_with("fps="):
			fps = int(a.substr(4))
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	Engine.max_fps = fps
	DirAccess.make_dir_recursive_absolute(OUT)

	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 70:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	# Soft-GL frames are ~100ms; without a fixed sim dt the warm walk overshoots into
	# rocks/lighthouse and the boy_ds spike is a wall shove, not a camera event.
	var dt := 1.0 / float(fps)
	m.sim_dt_override = dt
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 60:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)

	# Flat beach: face +X, camera behind on a palm-clear line with ≥7 m sand ahead
	# (covers walk+run warm). Face-camera (ex_yaw=face+PI) walked into the lighthouse.
	var open_p := Vector3(15.0, 0.0, 4.0)
	open_p.y = m._surface(open_p.x, open_p.z)
	m._place(open_p, -PI * 0.5)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.20
	m.ex_dist = 4.8
	m.mode = m.Mode.EXPLORE
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.68, 0)
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	for _i in 20:
		await process_frame

	await _prep_move(m, open_p, -PI * 0.5, Vector2(0, -0.55), fps, 1.4)
	await _seq(m, vp, "walk", fps, dt, 1.2, Vector2(0, -0.55), false)

	await _prep_move(m, open_p, -PI * 0.5, Vector2(0, -1.0), fps, 1.3)
	await _seq(m, vp, "run", fps, dt, 1.2, Vector2(0, -1.0), false)

	if m.joy:
		m.joy.value = Vector2.ZERO
		m.joy.active = false
	# Fresh place for orbit so drag-start has no lag / collision to correct.
	m._place(open_p, -PI * 0.5)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.20
	m.ex_dist = 4.8
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.68, 0)
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._orbit_ease = 0.0
	for _i in 35:
		await process_frame
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m._orbit_ease = 0.0
	await _seq(m, vp, "orbit", fps, dt, 1.2, Vector2.ZERO, true)

	await _prep_move(m, open_p, -PI * 0.5, Vector2(0, -0.55), fps, 0.9)
	await _seq(m, vp, "walk_spike", fps, dt, 0.9, Vector2(0, -0.55), false, true)

	print("V26_TIMING_DONE fps=", fps)
	quit(0)


func _prep_move(m, pos: Vector3, yaw: float, stick: Vector2, fps: int, warm_s: float) -> void:
	## Re-place on open sand and warm the stick so each seq starts at steady speed.
	m._place(pos, yaw)
	# Follow-behind: stick-forward walks along face_yaw (clear +X shore), not into the lighthouse.
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.20
	m.ex_dist = 4.8
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.68, 0)
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	m._orbit_ease = 0.0
	m.move_vel = Vector3.ZERO
	m.cur_speed = 0.0
	m.spot_turning = false
	if m.joy:
		m.joy.active = true
		m.joy.value = stick
	for _i in int(fps * warm_s):
		await process_frame


func _seq(m, vp, tag: String, fps: int, dt: float, secs: float, stick: Vector2, orbit: bool, spike := false) -> void:
	var n := int(ceil(secs * float(fps)))
	var path := "%s/%s_%dfps.csv" % [OUT, tag, fps]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("frame,dt,boy_sx,boy_sy,boy_ds,cam_x,cam_y,cam_z,cam_ds,yaw,pitch,dist,arm,slide,spd,px,pz,tx,tz")
	var prev_s := Vector2.ZERO
	var prev_c := Vector3.ZERO
	var have := false
	var boy_ds: Array[float] = []
	var cam_ds: Array[float] = []
	# Hold stick via demo-ish: drive move_input by writing joy
	m.demo_mode = false
	for i in n:
		var use_dt := dt
		if spike and i == int(n * 0.45):
			use_dt = dt * 4.0
		if orbit:
			# Steady orbit rate (pitch kept small so spring-arm / framing stay stable).
			m.orbit_pending += Vector2(0.028, 0.0)
			m.dragging = true
		elif stick.length() > 0.01 and m.joy:
			m.joy.active = true
			m.joy.value = stick
		await process_frame
		var hips: Vector3 = m.player.global_position + Vector3(0, 0.7, 0)
		var s: Vector2 = m.camera.unproject_position(hips)
		var c: Vector3 = m.camera.global_position
		var bds := 0.0
		var cds := 0.0
		if have:
			bds = s.distance_to(prev_s)
			cds = c.distance_to(prev_c)
			boy_ds.append(bds)
			cam_ds.append(cds)
		have = true
		prev_s = s
		prev_c = c
		f.store_line("%d,%.6f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.5f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [
			i, use_dt, s.x, s.y, bds, c.x, c.y, c.z, cds, m.cam_yaw, m.cam_pitch, m.cam_dist,
			m._cam_arm_k, m._cam_slide, m.cur_speed, m.player.global_position.x, m.player.global_position.z,
			m.cam_target.x, m.cam_target.z
		])
	f.close()
	m.dragging = false
	m.orbit_pending = Vector2.ZERO
	if m.joy:
		m.joy.value = Vector2.ZERO
		m.joy.active = false
	_write_stats("%s/%s_%dfps_stats.txt" % [OUT, tag, fps], boy_ds, cam_ds, fps, tag)
	print("TIMING ", tag, " ", fps, "fps n=", boy_ds.size())


func _write_stats(path: String, boy_ds: Array, cam_ds: Array, fps: int, tag: String) -> void:
	var bs := _stats(boy_ds, fps)
	var cs := _stats(cam_ds, fps)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("tag=%s fps=%d" % [tag, fps])
	f.store_line("boy_ds median=%.4f p95=%.4f max=%.4f max/median=%.3f" % [bs[0], bs[1], bs[2], bs[3]])
	f.store_line("cam_ds median=%.5f p95=%.5f max=%.5f max/median=%.3f" % [cs[0], cs[1], cs[2], cs[3]])
	f.close()
	print("STATS ", tag, " ", fps, " boy max/med=", "%.3f" % bs[3], " cam max/med=", "%.3f" % cs[3])


func _stats(arr: Array, fps: int = 60) -> Array:
	if arr.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	# Skip the first ~0.35 s (accel / orbit ease-in), then ignore near-zero idle.
	var start := mini(int(round(float(fps) * 0.35)), maxi(arr.size() - 8, 0))
	var a: Array = []
	for i in range(start, arr.size()):
		var v := float(arr[i])
		if v > 0.012:
			a.append(v)
	if a.is_empty():
		for i in range(start, arr.size()):
			a.append(float(arr[i]))
	if a.is_empty():
		a = arr.duplicate()
	a.sort()
	var med: float = float(a[a.size() / 2])
	var p95: float = float(a[mini(a.size() - 1, int(a.size() * 0.95))])
	var mx: float = float(a[a.size() - 1])
	# Near-perfect tracking (sub-pixel noise) → treat as flat.
	var ratio := 1.0 if mx < 0.04 else mx / maxf(med, 1e-6)
	return [med, p95, mx, ratio]
