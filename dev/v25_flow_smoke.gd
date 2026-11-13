extends SceneTree
## Full-flow smoke: bench sit/exit, log sit/exit, hammock sleep/exit, dock throw.
## Prints FOOT_SLIDE / POP / CAM_CLIP / ERR lines; exits 0 on clean run.

const TOL_FOOT := 0.045
const TOL_POP := 0.12


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 80:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 60:
			await process_frame

	var issues: PackedStringArray = PackedStringArray()
	print("SMOKE_START")

	# Bench
	await _flow_seat(m, "长椅", issues)
	# Log
	await _flow_seat(m, "坐木", issues)
	# Hammock
	await _flow_hammock(m, issues)
	# Throw
	await _flow_throw(m, issues)

	if issues.is_empty():
		print("SMOKE_PASS")
		quit(0)
	else:
		for L in issues:
			print(L)
		print("SMOKE_FAIL count=", issues.size())
		quit(1)


func _pick_seat(m, want: String) -> int:
	var best := 0
	var best_d := -1.0
	for i in m.island.seats.size():
		if String(m.island.seats[i]["name"]) != want:
			continue
		if want == "坐木":
			var d: float = (m.island.seats[i]["top"] as Vector3).distance_to(m.island.campfire_pos)
			if d > best_d:
				best_d = d
				best = i
		else:
			return i
	return best


func _cam_clip_check(m, tag: String, issues: PackedStringArray) -> void:
	var pos: Vector3 = m.camera.global_position
	var floor_y: float = maxf(Island.ground_h(pos.x, pos.z), 0.0) + 0.20
	if pos.y < floor_y - 0.05:
		issues.append("CAM_CLIP %s cam_y=%.3f floor=%.3f" % [tag, pos.y, floor_y])
	for ob in m.island.obstacles:
		var c: Vector2 = ob[0]
		if pos.y < float(ob[2]) and pos.y > float(ob[4]) and Vector2(pos.x - c.x, pos.z - c.y).length() < float(ob[1]) * 0.85:
			issues.append("CAM_CLIP %s inside obstacle %s" % [tag, String(ob[3])])
			break


func _foot_y(m) -> float:
	var la: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
	var ra: Vector3 = m.boy.lie_bone_world("mixamorig_RightFoot")
	return 0.5 * (la.y + ra.y)


func _flow_seat(m, seat_name: String, issues: PackedStringArray) -> void:
	var bi := _pick_seat(m, seat_name)
	var st: Dictionary = m.island.seats[bi]
	m.seat_i = bi
	m.seat_ap = st["approach"]
	m.seat_face = st["face"]
	# Walk approach
	m.mode = m.Mode.EXPLORE
	m._place(st["approach"], atan2(-(st["face"] as Vector3).x, -(st["face"] as Vector3).z))
	for _i in 10:
		await process_frame
	var y0: float = m.player.position.y
	m._begin_rest("seat")
	# Allow enter clip to play briefly then snap idle
	m.rest_frozen = true
	m.rest_phase = 1
	m._play_rest_enter_clip()
	var prev_hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	for _i in 20:
		await process_frame
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		if hips.distance_to(prev_hips) > TOL_POP and _i > 2:
			# large single-frame hip jump during enter
			if hips.distance_to(prev_hips) > 0.35:
				issues.append("POP %s enter hips_jump=%.3f" % [seat_name, hips.distance_to(prev_hips)])
		prev_hips = hips
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(2.0)
	m.boy._tick(0.0)
	for _i in 25:
		await process_frame
	_cam_clip_check(m, "sit_"+seat_name, issues)
	# Feet should be near ground for bench/log
	var fy: float = _foot_y(m)
	var gy: float = m.rest_prop_xf.origin.y
	if fy < gy - 0.08 or fy > gy + 0.22:
		issues.append("FOOT %s foot_y=%.3f ground=%.3f" % [seat_name, fy, gy])
	# Exit
	m.rest_phase = 6
	m._play_rest_exit_clip()
	for _i in 25:
		await process_frame
	m._finish_rest_exit()
	for _i in 15:
		await process_frame
	var y1: float = m.player.position.y
	var surf: float = m._surface(m.player.position.x, m.player.position.z)
	if absf(y1 - surf) > TOL_FOOT + 0.05:
		issues.append("FOOT_SLIDE %s after_exit y=%.3f surf=%.3f" % [seat_name, y1, surf])
	_cam_clip_check(m, "exit_"+seat_name, issues)
	print("SMOKE_OK ", seat_name)


func _flow_hammock(m, issues: PackedStringArray) -> void:
	m.mode = m.Mode.EXPLORE
	m._begin_rest("sleep")
	m.rest_frozen = true
	m.rest_phase = 1
	m._play_rest_enter_clip()
	for _i in 30:
		await process_frame
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(3.0)
	m._sync_hammock_cloth_to_boy()
	m.boy._tick(0.0)
	for _i in 30:
		await process_frame
	if not m.island.hammock_use_v25:
		issues.append("ERR hammock_v25 inactive")
	var ah := 0.0
	if m.island.hammock_cloth_mi:
		ah = m.island.hammock_cloth_mi.get_aabb().size.y
	if ah < 0.45:
		issues.append("ERR hammock cloth flat aabb_y=%.3f" % ah)
	_cam_clip_check(m, "hammock_sleep", issues)
	m.rest_phase = 6
	m._play_rest_exit_clip()
	for _i in 25:
		await process_frame
	m._finish_rest_exit()
	for _i in 15:
		await process_frame
	print("SMOKE_OK hammock")


func _flow_throw(m, issues: PackedStringArray) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(0.0, 0, m.island.dock_end_z + 1.55), 0.0)
	for _i in 8:
		await process_frame
	m._enter_throw()
	var t0 := Time.get_ticks_msec()
	while m.throw_walk and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	m.throw_walk = false
	m.player.position = m.throw_spot
	m.player.position.y = Island.DECK_Y + 0.04
	m.boy.global_position = m.player.global_position
	m.aim_yaw = 0.0
	m.cam_aim_yaw = 0.0
	m.aim_pitch = 6.0
	m.aim_tilt = 20.0
	m.power = 0.9
	m.throw_spin = 0.9
	m.aim_src = "script"
	m.state = m.State.READY
	# Validate throw meta path before swing
	var tc = m.boy.clips.get(m.boy._throw_clip(), null)
	if typeof(tc) != TYPE_DICTIONARY:
		issues.append("ERR throw clip meta missing for " + m.boy._throw_clip())
	else:
		m._throw()
		t0 = Time.get_ticks_msec()
		while m.state != m.State.FLYING and Time.get_ticks_msec() - t0 < 4000:
			await process_frame
		if m.state != m.State.FLYING:
			issues.append("ERR throw never released state=%s" % str(m.state))
		else:
			for _i in 80:
				if m.state != m.State.FLYING:
					break
				await process_frame
			if m.skips < 1:
				issues.append("ERR throw no skips (stone may have sunk immediately)")
			print("SMOKE_THROW skips=", m.skips, " dist=", m.throw_dist)
	m.stone.visible = false
	m.state = m.State.READY
	m.mode = m.Mode.EXPLORE
	m.boy.set_idle()
	print("SMOKE_OK throw")
