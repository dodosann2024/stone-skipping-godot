extends SceneTree
## Report Godot Performance monitors + viewport/light budget for v27.
## Usage: godot --headless --path . --script res://dev/v27_budget_probe.gd [-- --night=1 --path=dirt]

const W := 390
const H := 844
const OUT := "/workspace/screenshots/v27/timing"


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
	m.mode = m.Mode.EXPLORE
	# Freeze quality at phone MID for a stable budget (don't let llvmpipe adaptive eat shadows).
	m.mq.setup(true, true, vp, m.sun)
	m.mq.frozen = true
	m.mq.tier = 1  # MobileQuality.Tier.MID
	m.mq._apply(vp, m.sun)
	m._apply_mq_materials()
	m.refl_auto = false
	m._set_refl_level(2)  # reflection off — matches mobile default

	var night := false
	for a in OS.get_cmdline_user_args():
		if a == "--night=1" or a == "night=1":
			night = true
	if night and not m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	elif (not night) and m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	m.night_k = 1.0 if night else 0.0
	m._update_night(m.night_k, true)

	# Lighthouse climb (user iPhone day_path: rope fence + tower).
	var pl: Array = m.island.paths[1]
	var a: Vector2 = pl[mini(3, pl.size() - 2)]
	var b: Vector2 = pl[mini(4, pl.size() - 1)]
	var xz: Vector2 = a.lerp(b, 0.55)
	var p := Vector3(xz.x, 0.0, xz.y)
	p.y = m._surface(p.x, p.z)
	var to_lh: Vector3 = m.island.lighthouse_pos - p
	to_lh.y = 0.0
	m._place(p, atan2(-to_lh.x, -to_lh.z) if to_lh.length_squared() > 1e-6 else 0.0)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.16
	m.ex_dist = 3.8
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cap_night_omnis()
	for _i in 40:
		await process_frame
	m._cap_night_omnis()
	await process_frame

	var rows: PackedStringArray = []
	rows.append("metric,value")
	_row(rows, "canvas_size", "%dx%d" % [W, H])
	_row(rows, "window_size", str(DisplayServer.window_get_size()))
	_row(rows, "vp_size", str(vp.size))
	_row(rows, "scaling_3d_scale", "%.3f" % vp.scaling_3d_scale)
	_row(rows, "msaa_3d", str(vp.msaa_3d))
	_row(rows, "positional_shadow_atlas_size", str(vp.positional_shadow_atlas_size))
	_row(rows, "render_info_objects_visible", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)))
	_row(rows, "render_info_draw_calls_visible", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	_row(rows, "render_info_primitives_visible", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)))
	_row(rows, "render_info_objects_shadow", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)))
	_row(rows, "render_info_draw_calls_shadow", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	_row(rows, "render_info_primitives_shadow", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)))
	_row(rows, "perf_draw_calls", "%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_row(rows, "perf_objects", "%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_row(rows, "perf_primitives", "%.0f" % Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_row(rows, "perf_video_mem_mb", "%.2f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)))
	_row(rows, "perf_texture_mem_mb", "%.2f" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / (1024.0 * 1024.0)))
	_row(rows, "perf_buffer_mem_mb", "%.2f" % (Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / (1024.0 * 1024.0)))
	_row(rows, "time_fps", "%.2f" % Performance.get_monitor(Performance.TIME_FPS))
	_row(rows, "time_process_ms", "%.3f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	_row(rows, "time_physics_ms", "%.3f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))

	var counts := {
		"omni": 0, "omni_visible": 0, "omni_shadow": 0, "spot": 0, "spot_shadow": 0,
		"dir": 0, "dir_shadow": 0, "particles": 0, "mm_instances": 0, "mesh_instances": 0,
	}
	_count_scene(m, counts)
	_row(rows, "lights_directional", str(counts["dir"]))
	_row(rows, "lights_directional_shadow", str(counts["dir_shadow"]))
	_row(rows, "lights_omni", str(counts["omni"]))
	_row(rows, "lights_omni_visible", str(counts["omni_visible"]))
	_row(rows, "lights_omni_shadow", str(counts["omni_shadow"]))
	_row(rows, "lights_spot", str(counts["spot"]))
	_row(rows, "lights_spot_shadow", str(counts["spot_shadow"]))
	_row(rows, "particle_systems", str(counts["particles"]))
	_row(rows, "multimesh_instances", str(counts["mm_instances"]))
	_row(rows, "mesh_instances", str(counts["mesh_instances"]))
	_row(rows, "draw_calls_visible", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	_row(rows, "draw_calls_shadow", str(vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	if m.sun:
		_row(rows, "sun_shadow_mode", str(m.sun.directional_shadow_mode))
		_row(rows, "sun_shadow_max_distance", "%.1f" % m.sun.directional_shadow_max_distance)
		_row(rows, "sun_shadow_blur", "%.2f" % m.sun.shadow_blur)
	if m.refl:
		_row(rows, "refl_enabled", str(m.refl.enabled))
		_row(rows, "refl_scale", "%.3f" % m.refl.scale)
		_row(rows, "refl_every", str(m.refl.every))
		_row(rows, "refl_vp_size", str(m.refl.vp.size if m.refl.vp else Vector2i.ZERO))
		_row(rows, "refl_level", str(m.refl_level))
	_row(rows, "night_on", str(night))
	_row(rows, "player_pos", "%.2f,%.2f,%.2f" % [m.player.global_position.x, m.player.global_position.y, m.player.global_position.z])

	var csv := "\n".join(rows) + "\n"
	var tag := "night" if night else "day"
	var path := "%s/budget_%s.csv" % [OUT, tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(csv)
	f.close()
	print("=== V27 BUDGET %s ===" % tag)
	print(csv)
	# Still only when a real GL texture exists (dummy headless has none).
	var tex := vp.get_texture()
	if tex:
		var img: Image = tex.get_image()
		if img:
			img.save_png("/workspace/screenshots/v27/budget_%s_path.png" % tag)
	print("V27_BUDGET_DONE ", path)
	quit(0)


func _row(rows: PackedStringArray, k: String, v: String) -> void:
	rows.append("%s,%s" % [k, v])


func _count_scene(n: Node, counts: Dictionary) -> void:
	if n is OmniLight3D:
		counts["omni"] += 1
		var ol := n as OmniLight3D
		if ol.visible and ol.light_energy > 0.01 and ol.light_cull_mask != 0:
			counts["omni_visible"] += 1
		if ol.shadow_enabled and ol.visible:
			counts["omni_shadow"] += 1
	elif n is SpotLight3D:
		counts["spot"] += 1
		if (n as SpotLight3D).shadow_enabled:
			counts["spot_shadow"] += 1
	elif n is DirectionalLight3D:
		counts["dir"] += 1
		if (n as DirectionalLight3D).shadow_enabled:
			counts["dir_shadow"] += 1
	elif n is GPUParticles3D or n is CPUParticles3D:
		counts["particles"] += 1
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm:
			counts["mm_instances"] += mm.instance_count
	elif n is MeshInstance3D:
		counts["mesh_instances"] += 1
	for c in n.get_children():
		_count_scene(c, counts)
