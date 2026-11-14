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
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 60:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)

	# Open beach start, face along shore.
	m._place(Vector3(1.6, 0, m.island.dock_start_z + 3.5), 0.0)
	m.ex_yaw = m.face_yaw + PI
	m.ex_pitch = 0.20
	m.ex_dist = 4.8
	m.mode = m.Mode.EXPLORE
	for _i in 20:
		await process_frame

	var dt := 1.0 / float(fps)
	# Warm up walk so first recorded frames aren't idle→spot-turn zeros.
	if m.joy:
		m.joy.active = true
		m.joy.value = Vector2(0, -0.55)
	for _i in int(fps * 0.8):
		await process_frame
	await _seq(m, vp, "walk", fps, dt, 1.4, Vector2(0, -0.55), false)
	await _seq(m, vp, "run", fps, dt, 1.4, Vector2(0, -1.0), false)
	if m.joy:
		m.joy.value = Vector2.ZERO
		m.joy.active = false
	for _i in 20:
		await process_frame
	await _seq(m, vp, "orbit", fps, dt, 1.2, Vector2.ZERO, true)
	# Resume walk then record (spike tag marks intentional hitch frame in CSV).
	if m.joy:
		m.joy.active = true
		m.joy.value = Vector2(0, -0.55)
	for _i in int(fps * 0.5):
		await process_frame
	await _seq(m, vp, "walk_spike", fps, dt, 0.9, Vector2(0, -0.55), false, true)

	print("V26_TIMING_DONE fps=", fps)
	quit(0)


func _seq(m, vp, tag: String, fps: int, dt: float, secs: float, stick: Vector2, orbit: bool, spike := false) -> void:
	var n := int(ceil(secs * float(fps)))
	var path := "%s/%s_%dfps.csv" % [OUT, tag, fps]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("frame,dt,boy_sx,boy_sy,boy_ds,cam_x,cam_y,cam_z,cam_ds,yaw,pitch,dist")
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
			m.orbit_pending += Vector2(0.035, 0.008)
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
		f.store_line("%d,%.6f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.5f,%.4f,%.4f,%.4f" % [
			i, use_dt, s.x, s.y, bds, c.x, c.y, c.z, cds, m.cam_yaw, m.cam_pitch, m.cam_dist
		])
	f.close()
	if m.joy:
		m.joy.value = Vector2.ZERO
		m.joy.active = false
	_write_stats("%s/%s_%dfps_stats.txt" % [OUT, tag, fps], boy_ds, cam_ds, fps, tag)
	print("TIMING ", tag, " ", fps, "fps n=", boy_ds.size())


func _write_stats(path: String, boy_ds: Array, cam_ds: Array, fps: int, tag: String) -> void:
	var bs := _stats(boy_ds)
	var cs := _stats(cam_ds)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("tag=%s fps=%d" % [tag, fps])
	f.store_line("boy_ds median=%.4f p95=%.4f max=%.4f max/median=%.3f" % [bs[0], bs[1], bs[2], bs[3]])
	f.store_line("cam_ds median=%.5f p95=%.5f max=%.5f max/median=%.3f" % [cs[0], cs[1], cs[2], cs[3]])
	f.close()
	print("STATS ", tag, " ", fps, " boy max/med=", "%.3f" % bs[3], " cam max/med=", "%.3f" % cs[3])


func _stats(arr: Array) -> Array:
	if arr.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	# Ignore near-zero frames (idle / pre-motion) so max/median isn't inflated.
	var a: Array = []
	for v in arr:
		if float(v) > 0.02:
			a.append(float(v))
	if a.is_empty():
		a = arr.duplicate()
	a.sort()
	var med: float = float(a[a.size() / 2])
	var p95: float = float(a[mini(a.size() - 1, int(a.size() * 0.95))])
	var mx: float = float(a[a.size() - 1])
	var ratio := mx / maxf(med, 1e-6)
	return [med, p95, mx, ratio]
