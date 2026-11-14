extends SceneTree
## Phone-proxy frame timing: force --mobile=1 quality, record TIME_PROCESS for walk/run/orbit/campfire.
## Writes screenshots/v27/timing/{tag}_after.csv + stats. Pair with tools/v27_throttle_timing.py for web.

const OUT := "/workspace/screenshots/v27/timing"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(OUT)

	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 80:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	# Force mobile quality ladder even on desktop GL; freeze so llvmpipe doesn't step to MIN.
	m.mq.setup(true, true, vp, m.sun)
	m.mq.frozen = true
	m.mq.tier = 1
	m.mq._apply(vp, m.sun)
	m._apply_mq_materials()
	m.refl_auto = false
	m._set_refl_level(2)

	# Lighthouse climb (same spot as budget / user day_path).
	var pl: Array = m.island.paths[1]
	var a: Vector2 = pl[mini(3, pl.size() - 2)]
	var b: Vector2 = pl[mini(4, pl.size() - 1)]
	var xz: Vector2 = a.lerp(b, 0.55)
	var path_p := Vector3(xz.x, 0.0, xz.y)
	path_p.y = m._surface(path_p.x, path_p.z)
	var to_lh: Vector3 = m.island.lighthouse_pos - path_p
	to_lh.y = 0.0
	var path_yaw := atan2(-to_lh.x, -to_lh.z) if to_lh.length_squared() > 1e-6 else 0.35

	await _prep(m, path_p, path_yaw, Vector2(0, -0.55))
	await _seq(m, "walk_path", 10.0, Vector2(0, -0.55), false, false)

	await _prep(m, path_p, path_yaw, Vector2(0, -1.0))
	await _seq(m, "run_path", 10.0, Vector2(0, -1.0), false, false)

	await _prep(m, path_p, path_yaw, Vector2.ZERO)
	await _seq(m, "orbit_path", 10.0, Vector2.ZERO, true, false)

	# Campfire night stand
	if not m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	m.night_k = 1.0
	m._update_night(1.0, true)
	var fire: Vector3 = m.island.campfire_pos + Vector3(1.05, 0, 0.35)
	fire.y = m._surface(fire.x, fire.z)
	await _prep(m, fire, atan2(-(m.island.campfire_pos.x - fire.x), -(m.island.campfire_pos.z - fire.z)), Vector2.ZERO)
	await _seq(m, "campfire_night", 10.0, Vector2.ZERO, false, false)

	_write_summary()
	print("V27_TIMING_DONE")
	quit(0)


func _prep(m, pos: Vector3, yaw: float, stick: Vector2) -> void:
	m._place(pos, yaw)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.22
	m.ex_dist = 4.2
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.68, 0)
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._orbit_ease = 0.0
	m.move_vel = Vector3.ZERO
	m.cur_speed = 0.0
	if m.joy:
		m.joy.active = stick.length() > 0.01
		m.joy.value = stick
	for _i in 45:
		await process_frame


func _seq(m, tag: String, secs: float, stick: Vector2, orbit: bool, _unused: bool) -> void:
	var n := int(ceil(secs * 60.0))
	var path := "%s/%s_after.csv" % [OUT, tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("frame,dt_ms,proc_ms,fps")
	var times: Array[float] = []
	for i in n:
		if orbit:
			m.orbit_pending += Vector2(0.03, 0.0)
			m.dragging = true
		elif stick.length() > 0.01 and m.joy:
			m.joy.active = true
			m.joy.value = stick
		var t0 := Time.get_ticks_usec()
		await process_frame
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		times.append(dt_ms)
		f.store_line("%d,%.3f,%.3f,%.2f" % [i, dt_ms, proc_ms, fps])
	f.close()
	m.dragging = false
	m.orbit_pending = Vector2.ZERO
	if m.joy:
		m.joy.value = Vector2.ZERO
		m.joy.active = false
	_write_stats("%s/%s_after_stats.txt" % [OUT, tag], tag, times)
	print("TIMING ", tag, " n=", times.size())


func _write_stats(path: String, tag: String, arr: Array) -> void:
	var a: Array = arr.duplicate()
	# skip first 0.5s warm
	var start := mini(30, maxi(a.size() - 8, 0))
	var slice: Array = []
	for i in range(start, a.size()):
		slice.append(float(a[i]))
	slice.sort()
	var med := float(slice[slice.size() / 2])
	var p95 := float(slice[mini(slice.size() - 1, int(slice.size() * 0.95))])
	var p99 := float(slice[mini(slice.size() - 1, int(slice.size() * 0.99))])
	var mx := float(slice[slice.size() - 1])
	var hitches := 0
	for v in slice:
		if float(v) > 33.0:
			hitches += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("tag=%s n=%d" % [tag, slice.size()])
	f.store_line("dt_ms median=%.3f p95=%.3f p99=%.3f max=%.3f hitches_gt33=%d" % [med, p95, p99, mx, hitches])
	f.close()
	print("STATS ", tag, " med=", "%.2f" % med, " p95=", "%.2f" % p95, " max=", "%.2f" % mx, " hitches=", hitches)


func _write_summary() -> void:
	var f := FileAccess.open("%s/summary_after.txt" % OUT, FileAccess.WRITE)
	for tag in ["walk_path", "run_path", "orbit_path", "campfire_night"]:
		var p := "%s/%s_after_stats.txt" % [OUT, tag]
		if FileAccess.file_exists(p):
			f.store_string(FileAccess.get_file_as_string(p))
			f.store_string("\n")
	f.close()
