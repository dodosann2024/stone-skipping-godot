extends SceneTree
## Fast lie contact/hat/penet check — no screenshots.

func _initialize() -> void:
	call_deferred("g")

func g() -> void:
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	for i in 40:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	for kind in ["sun", "sleep"]:
		m._begin_rest(kind)
		m.rest_phase = 4
		m.rest_t = 1.0
		m.set_meta("lie_snapped", false)
		var passes := 28 if kind == "sleep" else 50
		for _p in passes:
			var pl = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			var swing := Transform3D.IDENTITY
			if kind == "sleep":
				swing = m.island.swing_hammock(0.0)
				m._update_hammock_load()
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m._snap_lie_contact()
			pl = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m._plant_lie_feet()
			await process_frame
		m.set_meta("lie_snapped", true)
		if kind == "sleep":
			m._update_hammock_load()
		var face: float = m.boy.lie_face_normal().dot(Vector3.UP)
		var gaps: Dictionary = m.lie_contact_gaps()
		var mesh_p: float = m.lie_mesh_penetration_depth()
		print("KIND ", kind,
			" hat=", m.boy.hat_mode,
			" face_up=", snappedf(face, 0.01),
			" mesh_penet=", snappedf(mesh_p, 0.001),
			" gaps=", gaps)
		for key in ["hips", "spine", "head"]:
			if not gaps.has(key):
				continue
			var g: float = float(gaps[key])
			var ok := g >= -0.01 and g <= 0.02
			print("  ", key, " ", snappedf(g * 100.0, 0.1), "cm ", "OK" if ok else "BAD")
		print("  mesh ", snappedf(mesh_p * 100.0, 0.1), "cm ", "OK" if mesh_p >= -0.01 else "BAD")
		m._wake()
		m.mode = m.Mode.EXPLORE
		await process_frame
	quit()
