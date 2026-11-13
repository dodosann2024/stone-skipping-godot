extends SceneTree
## Nap-pose face plates: head turned away + forearm over open eyes. No blink.
## Usage: xvfb-run -a godot --path . --fixed-fps 30 --script res://dev/v24_nap_face_shots.gd

const OUT := "/workspace/screenshots/v24"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(900, 1200))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(900, 1200)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for _i in 50:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	m.demo_cam = true
	m.demo_track = []
	m.cam_fixed = true

	# ---- Hammock sleep ----
	m._begin_rest("sleep")
	m.rest_frozen = true
	var side: Vector3 = m.rest_side.normalized()
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	for _p in 40:
		var pl = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		m._update_hammock_load()
		m._snap_lie_contact()
		m.boy.set_face_expr("sleep")
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	for _i in 10:
		m.boy.activity("sleep", 1.0, 1.0, m.gt)
		m.boy._update_face(0.05)
		await process_frame
	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var hand: Vector3 = m.boy.lie_bone_world("mixamorig_RightHand")
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var face: Vector3 = m.boy.model.global_transform.basis.z.normalized()
	print("ham hand_head", hand.distance_to(head), "hand_into", (hand - head).dot(face))
	# Close-ups from above the face (along face normal) so the forearm occludes the eyes.
	await _cam(m, vp, "face_sleep_front", head, head + face * 0.85 + side * (-0.15) + Vector3(0, 0.02, 0))
	await _cam(m, vp, "face_sleep_34", head, head + face * 0.55 + side * (-0.55) + Vector3(0, 0.08, 0))
	var hold_look: Vector3 = hips.lerp(head, 0.45)
	# Hold: prefer the turned-away side so eyes aren't camera-front.
	await _cam(m, vp, "hammock_hold", hold_look, hold_look + side * (-2.8) + Vector3(0, 1.2, 0) + face * 0.4)

	# ---- Lounger sun nap ----
	m.island.set_hammock_load([] as Array[Vector3])
	m.rest_frozen = false
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()
	m.boy.clear_foot_plant()
	var td: Vector3 = m.island.towel_dir
	var sd: Vector3 = td.cross(Vector3.UP).normalized()
	m._place(m.island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
	m._begin_rest("sun")
	m.rest_frozen = true
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	for _p in 36:
		var pl2 = m.boy.activity("sun", 1.0, 1.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl2)
		m._snap_lie_contact()
		m.boy.set_face_expr("sleep")
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	for _i in 8:
		m.boy.activity("sun", 1.0, 1.0, m.gt)
		m.boy._update_face(0.05)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	hand = m.boy.lie_bone_world("mixamorig_RightHand")
	face = m.boy.model.global_transform.basis.z.normalized()
	print("sun hand_head", hand.distance_to(head), "hand_into", (hand - head).dot(face))
	# Prefer the side where the forearm sits between camera and eyes.
	var cover_side: Vector3 = m.boy.global_transform.basis.x.normalized()
	await _cam(m, vp, "face_sleep_lounger_front", head, head + face * 0.95 + cover_side * 0.15 + Vector3(0, 0.05, 0))
	await _cam(m, vp, "face_sleep_lounger_34", head, head + face * 0.55 + cover_side * 0.65 + Vector3(0, 0.08, 0))

	# ---- Standing smile / cheer / open (eyes open, no blink) ----
	m.rest_frozen = false
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()
	m.boy.clear_foot_plant()
	m._place(Vector3(1.5, 0, -5.5), PI)
	m.boy.set_idle()
	m.boy.set_face_expr("smile")
	if m.island:
		m.island.visible = false
	for _i in 12:
		m.boy._update_face(0.05)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	var fwd: Vector3 = -m.boy.global_transform.basis.z.normalized()
	await _cam(m, vp, "face_smile", head, head + fwd * 0.70 + Vector3(0, 0.04, 0))
	m.boy.set_face_expr("cheer")
	m.boy.react_kind = "cheer"
	for _i in 10:
		m.boy._update_face(0.05)
		await process_frame
	await _cam(m, vp, "face_cheer", head, head + fwd * 0.70 + Vector3(0, 0.04, 0))
	m.boy.react_kind = ""
	m.boy.set_face_expr("smile")
	await _cam(m, vp, "face_open_front", head, head + fwd * 0.62 + Vector3(0, 0.03, 0))

	print("NAP_FACE_SHOTS_DONE")
	quit(0)


func _cam(m, vp: Viewport, name: String, look: Vector3, eye: Vector3) -> void:
	m.cam_target = look
	var d: Vector3 = eye - look
	m.cam_dist = d.length()
	m.cam_yaw = atan2(d.x, d.z)
	m.cam_pitch = asin(clampf(d.y / maxf(d.length(), 1e-4), -0.95, 0.95))
	m._apply_camera()
	for _i in 6:
		if m.boy.act_kind in ["sleep", "sun"] and m.boy.act_lie_k > 0.5:
			m.boy.activity(m.boy.act_kind, 1.0, 1.0, m.gt)
			m.boy.set_face_expr("sleep")
		m.boy._update_face(0.05)
		m._apply_camera()
		await process_frame
	m.boy.bake_pose_mesh()
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	m.boy.restore_pose_mesh()
	print("SHOT", name)
