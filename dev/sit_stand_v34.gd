extends SceneTree
## Sit / stand: enter REST, settle, stand back to EXPLORE without deep dig.
## godot --headless --path . --fixed-fps 30 -s res://dev/sit_stand_v34.gd

var m: Node
var fails: Array[String] = []


func _fail(msg: String) -> void:
	fails.append(msg)
	print("SIT FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	for _i in 4:
		await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	for _i in 40:
		await process_frame

	var kinds: Array[String] = []
	if m.island.seats.size() > 0:
		kinds.append("seat")
	kinds.append("sun")

	for kind in kinds:
		await _run_kind(kind)

	if fails.is_empty():
		print("SIT_STAND PASS")
		quit(0)
	else:
		print("SIT_STAND FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)


func _run_kind(kind: String) -> void:
	print("SIT try ", kind)
	if m.mode == m.Mode.REST and m.has_method("_finish_rest_exit"):
		m._finish_rest_exit()
		for _i in 25:
			await process_frame
	m.mode = m.Mode.EXPLORE
	m._sync_body_pose(true)

	if kind == "seat":
		m.seat_i = 0
		var st: Dictionary = m.island.seats[0]
		var ap: Vector3 = st.get("approach", st["top"])
		m._place(ap, m.face_yaw)
	else:
		var ap2: Vector3 = m.island.towel_pos - m.island.towel_dir * 0.7
		m._place(ap2, atan2(-m.island.towel_dir.x, -m.island.towel_dir.z))
	for _i in 8:
		await process_frame

	m._begin_rest(kind)
	var saw := false
	var settled := false
	var max_dig := 0.0
	var min_face := 1e9
	# Authored bench enter clips are ~5.6s — wait long enough at 30/60 fixed-fps.
	for _i in 420:
		await process_frame
		if m.mode == m.Mode.REST:
			saw = true
		if m.mode == m.Mode.REST and m.rest_phase >= 2:
			if m.boy.has_method("lie_bone_world"):
				var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
				var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
				var up := (head - hips).normalized().y
				min_face = minf(min_face, up)
			if kind == "seat" and m.seat_i >= 0 and m.seat_i < m.island.seats.size():
				var top: Vector3 = m.island.seats[m.seat_i]["top"]
				# Hips / thighs vs seat top — feet hang below the board by design.
				if m.boy.skel:
					for bn in ["mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]:
						var bi: int = m.boy.skel.find_bone(bn)
						if bi < 0:
							continue
						var s: Vector3 = m.boy.skel.global_transform * m.boy.skel.get_bone_global_pose(bi).origin
						if Vector2(s.x - top.x, s.z - top.z).length() < 0.45:
							max_dig = maxf(max_dig, top.y - s.y)
		if m.mode == m.Mode.REST and m.rest_phase == 4 and m.rest_t > 0.35:
			settled = true
			break

	if not saw:
		_fail("%s never entered REST" % kind)
		return
	if not settled:
		_fail("%s never settled (phase=%s)" % [kind, str(m.rest_phase)])

	# Stand up via 「起来」 / _wake.
	if m.has_method("_wake"):
		m._wake()
	elif m.has_method("_on_action"):
		m._on_action()

	var back := false
	for _j in 180:
		await process_frame
		if m.mode == m.Mode.EXPLORE:
			back = true
			break
	if not back:
		_fail("%s did not return to EXPLORE" % kind)
		if m.has_method("_finish_rest_exit"):
			m._finish_rest_exit()
		m.mode = m.Mode.EXPLORE

	if max_dig > 0.08:
		_fail("%s dig %.3f m" % [kind, max_dig])
	if min_face < -0.6:
		_fail("%s face buried (%.2f)" % [kind, min_face])
	print("SIT ok %s dig=%.3f face_min=%.2f" % [kind, max_dig, min_face])
