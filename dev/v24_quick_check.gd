extends SceneTree
## Fast v24 rejection checks: sit ergonomics on all seats + hammock sit elev.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	var fails: PackedStringArray = []
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		if st["name"] == "躺椅":
			continue
		m.seat_i = i
		m.seat_ap = st["approach"]
		m.seat_face = st["face"]
		m._begin_rest("seat")
		m.set_process(false)
		m.boy.set_process(false)
		m.rest_phase = 4
		m.seat_lying = false
		for _p in 12:
			m.boy.activity("seat", 1.0, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			m._snap_sit_contact()
			await process_frame
		var elev: float = m.boy.sit_thigh_elev_deg()
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var knee: Vector3 = m.boy.lie_bone_world("mixamorig_LeftLeg")
		var ankle: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
		var shin := ankle - knee
		var shin_elev := 90.0
		if shin.length_squared() > 1e-8:
			shin_elev = rad_to_deg(asin(clampf(shin.normalized().dot(Vector3.UP), -1.0, 1.0)))
		var top: Vector3 = st["top"]
		print("QUICK seat%d elev=%.1f shin=%.1f hips-top=%.3f" % [i, elev, shin_elev, hips.y - top.y])
		if absf(elev) > 30.0:
			fails.append("seat%d thigh elev %.1f" % [i, elev])
		if shin_elev > -50.0:
			fails.append("seat%d shin elev %.1f" % [i, shin_elev])
		m.set_process(true)
		m.boy.set_process(true)
		m._wake()
		m.mode = m.Mode.EXPLORE
		m.boy.end_activity()
	# Hammock sit
	m._begin_rest("sleep")
	m.set_process(false)
	m.boy.set_process(false)
	for _p in 12:
		var pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	var he: float = m.boy.sit_thigh_elev_deg()
	print("QUICK hammock_sit elev=%.1f" % he)
	if absf(he) > 35.0:
		fails.append("hammock sit elev %.1f" % he)
	print("QUICK %s" % ("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
