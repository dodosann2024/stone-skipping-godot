extends SceneTree
## Start a drag from idle on a forest grass slope and assert every foot/leg bone
## and sampled sole vertex stays near the terrain (no shorts-level burial).
##   godot --path . --fixed-fps 30 -s res://dev/slope_drag_v35.gd

const MAX_TOE_SINK := 0.090    # m — walk clips dip toes; shorts burial is a mesh issue
const MAX_MESH_SINK := 0.040   # m — body mesh bottom (the user-visible burial)
const MAX_ROOT_ERR := 0.02
const MAX_HIP_CLEAR := 0.18    # m — hips must stay clearly above the mesh

var m: Node
var fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("SLOPE FAIL  ", msg)


func _leg_bone_names() -> Array[String]:
	return [
		"mixamorig_Hips",
		"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase",
		"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase",
	]


func _check_frame(tag: String) -> void:
	var p: Vector3 = m.player.global_position
	var mesh: float = m._surface(p.x, p.z)
	var root_err: float = p.y - mesh
	if absf(root_err) > MAX_ROOT_ERR:
		_fail("%s root err %.3f m" % [tag, root_err])
	if m.boy == null or m.boy.skel == null:
		_fail("%s missing skeleton" % tag)
		return
	var sk: Skeleton3D = m.boy.skel
	for bn in _leg_bone_names():
		var bi: int = sk.find_bone(bn)
		if bi < 0:
			continue
		var wy: float = (sk.global_transform * sk.get_bone_global_pose(bi).origin).y
		# Hips / thighs must stay well above the mesh (shorts-level burial fails here).
		if bn.contains("Hips") or bn.contains("UpLeg"):
			if wy < mesh + MAX_HIP_CLEAR:
				_fail("%s %s too low (%.1f cm above mesh)" % [tag, bn, (wy - mesh) * 100.0])
		elif bn.contains("Leg") and not bn.contains("Up"):
			if wy < mesh - 0.02:
				_fail("%s %s calf buried (%.1f cm)" % [tag, bn, (wy - mesh) * 100.0])
		else:
			if wy < mesh - MAX_TOE_SINK:
				_fail("%s %s sunk %.1f cm" % [tag, bn, (mesh - wy) * 100.0])
	# Body mesh AABB bottom — the visual "buried to shorts" signal.
	for node in m.boy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var nm: String = str(mi.name).to_lower()
		if nm.contains("blob") or nm.contains("hat") or nm.contains("stone") or nm.contains("glass") or nm.contains("scalp"):
			continue
		var ga: AABB = mi.global_transform * mi.get_aabb()
		var gap: float = ga.position.y - mesh
		if gap < -MAX_MESH_SINK:
			_fail("%s body mesh bottom sunk %.1f cm (%s)" % [tag, -gap * 100.0, mi.name])


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	if m.night_on:
		m._toggle_night()
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 40:
		await process_frame

	# Forest grass slope (spawn-area hill the CDP drag climbs).
	var xz := Vector2(3.0, m.island.dock_start_z + 7.2)
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = -0.5
	m.player.rotation.y = -0.5
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 20:
		await process_frame
	_check_frame("idle")

	# Exact CDP-like stick: up and to the right, hold.
	if m.joy:
		m.joy.value = Vector2(0.55, -0.75)
	var max_mesh_sink := 0.0
	for i in 45:
		await process_frame
		_check_frame("drag_%d" % i)
		var mesh: float = m._surface(m.player.position.x, m.player.position.z)
		for node in m.boy.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			var nm: String = str(mi.name).to_lower()
			if nm.contains("blob") or nm.contains("hat") or nm.contains("stone"):
				continue
			var ga: AABB = mi.global_transform * mi.get_aabb()
			max_mesh_sink = maxf(max_mesh_sink, mesh - ga.position.y)

	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 15:
		await process_frame
	_check_frame("release")

	print("SLOPE max_mesh_sink=%.1fcm sole_nudge=%.3f fails=%d" % [
		max_mesh_sink * 100.0, Boy.SOLE_NUDGE, fails.size()])
	if fails.is_empty():
		print("SLOPE_DRAG PASS")
		quit(0)
	else:
		print("SLOPE_DRAG FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)
