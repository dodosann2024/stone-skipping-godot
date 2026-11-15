extends SceneTree
## Walk on the grass and save a side view when the harness would flag float,
## plus one frame where the lower sole is inside the bar. Prints sole vs ground.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://dev/v40_float_side.gd

const OUT := "screenshots/v40"


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for _i in 40:
		await process_frame
	m.audio_started = true
	if m.start_overlay:
		m.start_overlay.visible = false
	var xz := Vector2(1.2, m.island.dock_start_z + 5.5)
	var y: float = m._surface(xz.x, xz.y)
	m.player_ctrl.write_body(Vector3(xz.x, y, xz.y), 0.0)
	m._shot_side = true
	m.joy.value = Vector2(0.0, -0.95)
	var float_n := 0
	var plant_saved := false
	var scored := 0
	var float_ct := 0
	for _i in 200:
		await process_frame
		if _i < 50:
			continue
		var fk = m.boy.foot_ik if m.boy != null else null
		if fk == null or not fk.pose_ready:
			continue
		scored += 1
		var gap: float = fk.mesh_gap_min
		# Startup can report a metre while the skeleton is still in bind pose.
		if gap > 0.40 or gap < -0.40:
			continue
		if gap > 0.015:
			float_ct += 1
		if not plant_saved and gap > -0.01 and gap < 0.012:
			_grab(m, fk, "float_plant.png")
			plant_saved = true
		elif float_n < 3 and gap > 0.020:
			_grab(m, fk, "float_flag_%d.png" % float_n)
			float_n += 1
		if plant_saved and float_n >= 3:
			break
	var pct: float = 100.0 * float(float_ct) / maxf(float(scored), 1.0)
	print("FLOAT_SIDE scored=%d float=%d pct=%.1f plant=%s shots=%d" % [scored, float_ct, pct, plant_saved, float_n])
	m.joy.value = Vector2(0.0, -1.0)
	for _i in 50:
		await process_frame
	m.joy.value = Vector2.ZERO
	for _i in 28:
		await process_frame
	var fk2 = m.boy.foot_ik if m.boy != null else null
	_grab(m, fk2, "side_run_stop.png")
	print("SIDE_RUN_STOP y=%.2f" % m.player.global_position.y)
	quit(0)


func _grab(m, fk, name: String) -> void:
	if fk == null:
		return
	RenderingServer.force_draw()
	var path := ProjectSettings.globalize_path("res://%s/%s" % [OUT, name])
	m.get_viewport().get_texture().get_image().save_png(path)
	print("FLOAT_SHOT %s gap_cm=%.2f sole=%.3f %.3f hit=%.3f %.3f body_y=%.3f" % [
		name, fk.mesh_gap_min * 100.0,
		fk.mesh_sole_y[0], fk.mesh_sole_y[1],
		fk.mesh_hit_y[0], fk.mesh_hit_y[1],
		m.player.global_position.y])
