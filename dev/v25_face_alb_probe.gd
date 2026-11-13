extends SceneTree
## Quick upright faces probe after albedo swap (no opaque plate).
func _initialize(): call_deferred("g")
func g():
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport(); vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate(); root.add_child(m)
	for i in 50: await process_frame
	m.demo_mode = true; m.demo_cam = true
	if m.start_overlay: m.start_overlay.queue_free()
	m.ui_root.visible = false
	m._place(Vector3(2, 0, -6.5), 0.0)
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	print("HAS_PLATE=", m.boy._face_decal != null, " ALB=", m.boy._face_alb.keys())
	DirAccess.make_dir_recursive_absolute("/workspace/screenshots/v25/probe")
	for expr in ["idle", "smile", "cheer", "sleep"]:
		m.boy.set_face_expr(expr)
		m.boy.react_kind = "cheer" if expr == "cheer" else ""
		m.boy.act_kind = "sleep" if expr == "sleep" else ""
		m.boy.act_lie_k = 1.0 if expr == "sleep" else 0.0
		for _i in 14: m.boy._update_face(0.08); await process_frame
		m.boy.bake_pose_mesh()
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		m.cam_fixed = true; m.demo_cam = true
		m.cam_target = head; m.cam_yaw = PI; m.cam_pitch = -0.02; m.cam_dist = 0.85; m.fix_dist = 0.85
		for _r in 6: m._apply_camera(); await process_frame
		vp.get_texture().get_image().save_png("/workspace/screenshots/v25/probe/alb_%s.png" % expr)
		print("SHOT ", expr, " sunk=", m.boy._eye_shells_sunk, " plate=", m.boy._face_decal != null)
		m.boy.restore_pose_mesh()
	print("ALB_PROBE_OK"); quit(0)
