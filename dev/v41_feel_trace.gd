extends SceneTree
## Fixed stick sequence. One line per physics frame:
##   t stick speed yaw_err cam_dist cam_yaw_err
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://dev/v41_feel_trace.gd

func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for _i in 30:
		await process_frame
	m.audio_started = true
	if m.start_overlay:
		m.start_overlay.visible = false
	var xz := Vector2(1.2, m.island.dock_start_z + 3.2)
	var y: float = m._surface(xz.x, xz.y)
	m.player_ctrl.write_body(Vector3(xz.x, y, xz.y), 0.0)
	m.ex_yaw = m.face_yaw
	m._snap_explore_cam(false)
	print("FEEL_TRACE_BEGIN")
	var t := 0.0
	var first_move := -1.0
	var stick_on := -1.0
	for i in 180:
		var dt := 1.0 / 60.0
		t += dt
		var stick := 0.0
		# Quiet, then a full push, hold, release, then a reverse.
		if t >= 0.20 and t < 1.40:
			stick = 0.95
		elif t >= 1.70 and t < 2.60:
			stick = -0.95
		if stick_on < 0.0 and absf(stick) > 0.2:
			stick_on = t
		m.joy.value = Vector2(0.0, -stick)
		await process_frame
		if first_move < 0.0 and stick_on > 0.0 and m.cur_speed > 0.15:
			first_move = t - stick_on
		var yaw_err := wrapf(m.face_yaw - atan2(-m.move_vel.x, -m.move_vel.z), -PI, PI) if m.cur_speed > 0.05 else 0.0
		var cam_err := wrapf(m.cam_yaw - m.face_yaw, -PI, PI)
		print("FEEL %.3f stick=%.2f spd=%.3f yaw_err=%.3f cam_dist=%.2f cam_yaw_err=%.3f" % [
			t, stick, m.cur_speed, yaw_err, m.cam_dist, cam_err])
	print("FEEL_FIRST_MOVE_S %.3f" % first_move)
	print("FEEL_TRACE_END")
	quit(0)
