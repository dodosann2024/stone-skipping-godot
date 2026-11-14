extends SceneTree
## Native CPU profile — Time.get_ticks_usec around main hotspots.
## godot --path . --script res://dev/v27_cpu_profile.gd

const W := 390
const H := 844
const OUT := "/workspace/screenshots/v27/timing"
const FRAMES := 90


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 60:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	m.mode = m.Mode.EXPLORE
	m.mq.setup(true, true, vp, m.sun)
	m.mq.frozen = true
	m.mq.tier = 1
	m.mq._apply(vp, m.sun)
	m._apply_mq_materials()
	m.refl_auto = false
	m._set_refl_level(2)
	m.night_k = 0.0
	m._update_night(0.0, true)

	var pl: Array = m.island.paths[1]
	var a: Vector2 = pl[mini(3, pl.size() - 2)]
	var b: Vector2 = pl[mini(4, pl.size() - 1)]
	var xz: Vector2 = a.lerp(b, 0.55)
	var p := Vector3(xz.x, 0.0, xz.y)
	p.y = m._surface(p.x, p.z)
	var to_lh: Vector3 = m.island.lighthouse_pos - p
	to_lh.y = 0.0
	m._place(p, atan2(-to_lh.x, -to_lh.z))
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.16
	m.ex_dist = 3.8
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	for _i in 30:
		await process_frame

	var sums := {
		"explore_tick": 0.0,
		"apply_camera": 0.0,
		"update_night": 0.0,
		"night_fx": 0.0,
		"path_lamp_pool": 0.0,
		"cap_omnis": 0.0,
		"island_set_time": 0.0,
		"boy_tick": 0.0,
		"water_refl": 0.0,
		"prints": 0.0,
		"wade": 0.0,
		"time_process": 0.0,
		"time_physics": 0.0,
	}
	var n := 0
	for i in FRAMES:
		# Mild forward walk via explore stick if present.
		if "joy" in m and m.joy:
			pass
		var u := Time.get_ticks_usec()
		m._explore_tick(1.0 / 60.0)
		sums["explore_tick"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m._apply_camera(1.0 / 60.0)
		sums["apply_camera"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m._update_night(1.0 / 60.0)
		sums["update_night"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m.night_fx.apply(m.night_k, m.camera.global_position, m.sun.global_basis.z.normalized(), 1.0 / 60.0)
		sums["night_fx"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m._cap_night_omnis()
		sums["cap_omnis"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m._update_path_lamp_pool()
		sums["path_lamp_pool"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m.island.set_time(m.gt)
		sums["island_set_time"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		if m.boy and m.boy.has_method("_tick"):
			m.boy._tick(1.0 / 60.0)
		sums["boy_tick"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		if m.refl:
			m.refl.update()
		sums["water_refl"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		if m.has_method("_update_prints"):
			m._update_prints()
		sums["prints"] += float(Time.get_ticks_usec() - u)
		u = Time.get_ticks_usec()
		m._update_wade_ring(1.0 / 60.0)
		sums["wade"] += float(Time.get_ticks_usec() - u)
		sums["time_process"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1.0e6
		sums["time_physics"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1.0e6
		n += 1
		await process_frame

	var rows: PackedStringArray = ["rank,name,avg_ms"]
	var items: Array = []
	for k in sums.keys():
		items.append([sums[k] / float(maxi(n, 1)) / 1000.0, k])
	items.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(12, items.size()):
		rows.append("%d,%s,%.4f" % [i + 1, items[i][1], items[i][0]])
		print("CPU#%d %s %.3f ms" % [i + 1, items[i][1], items[i][0]])
	var path := "%s/cpu_profile_day.csv" % OUT
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("WROTE ", path)
	print("V27_CPU_PROFILE_DONE")
	quit(0)
