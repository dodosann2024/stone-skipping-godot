extends SceneTree
## Quick face smoothness check for flat-eye boy: front + 3/4 idle/smile/cheer; sleep in lie pose.

const OUT := "/workspace/screenshots/v25/after/faces"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(OUT + "/../crops")
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 50:
		await process_frame
	m.demo_mode = true
	m.demo_cam = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 40:
			await process_frame

	print("FLAT_EYE meta=", m.boy.meta.get("flat_eyes"), " bones=", m.boy.skel.get_bone_count() if m.boy.skel else -1)
	print("FACE tex idle=", m.boy._face_alb.get("idle") != null, " sleep=", m.boy._face_alb.get("sleep") != null)
	print("ANIMS=", m.boy.ap.get_animation_list() if m.boy.ap else [])

	m.mode = m.Mode.EXPLORE
	m._place(Vector3(2.0, 0, -6.5), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	m.boy.end_activity()

	for expr in ["idle", "smile", "cheer"]:
		m.boy.set_face_expr(expr)
		m.boy.react_kind = "cheer" if expr == "cheer" else ""
		for _i in 14:
			m.boy._update_face(0.08)
			await process_frame
		m.boy.bake_pose_mesh()
		var tm = m.boy._face_mat if m.boy._face_mat else m.boy._boy_mat
		var tex: Texture2D = tm.albedo_texture if tm else null
		var mean := Vector3.ZERO
		if tex:
			var img: Image = tex.get_image()
			if img:
				var sx := mini(64, img.get_width())
				var sy := mini(64, img.get_height())
				var acc := Vector3.ZERO
				var n := 0
				for yy in sy:
					for xx in sx:
						var c: Color = img.get_pixel(xx * img.get_width() / sx, yy * img.get_height() / sy)
						acc += Vector3(c.r, c.g, c.b)
						n += 1
				mean = acc / float(maxi(n, 1))
		print("FACE_TEX ", expr, " mean=", mean, " same_as_cheer=", tex == m.boy._face_alb.get("cheer"), " same_as_smile=", tex == m.boy._face_alb.get("smile"))
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		m.demo_cam = true
		m.cam_fixed = true
		m.cam_target = head
		m.cam_yaw = PI + 0.05
		m.cam_pitch = -0.02
		m.cam_dist = 0.92
		m.fix_dist = 0.92
		for _r in 5:
			m._apply_camera()
			await process_frame
		_shot(vp, "%s/%s.png" % [OUT, expr])
		_shot(vp, "%s/../crops/face_%s.png" % [OUT, expr])
		m.cam_yaw = PI + 0.55
		m.cam_dist = 1.05
		m.fix_dist = 1.05
		for _r in 4:
			m._apply_camera()
			await process_frame
		_shot(vp, "%s/../crops/face_%s_34.png" % [OUT, expr])
		m.boy.restore_pose_mesh()
	m.boy.react_kind = ""

	# Sleep in actual hammock lie
	m.rest_frozen = false
	m._begin_rest("sleep")
	m.rest_frozen = true
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	m.boy.set_face_expr("sleep")
	for _p in 36:
		var pl: Vector3 = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		m._update_hammock_load()
		m._snap_lie_contact()
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	for _i in 8:
		m.boy._update_face(0.1)
		await process_frame
	m.boy.bake_pose_mesh()
	var head_s: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var hips_s: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var side: Vector3 = m.rest_side.normalized()
	var look: Vector3 = head_s + Vector3(0, 0.02, 0)
	# Elevated open-side view looking down at the face (skyward supine).
	var side_yaw: float = atan2(-side.x, -side.z) + 0.2
	m.demo_cam = true
	m.cam_fixed = true
	m.cam_target = look
	m.cam_yaw = side_yaw
	m.cam_pitch = 0.55
	m.cam_dist = 1.25
	m.fix_dist = 1.25
	print("SLEEP_FACE head=", head_s, " hips=", hips_s, " side=", side, " dist=", m.cam_dist)
	for _r in 8:
		m._apply_camera()
		await process_frame
	_shot(vp, "%s/sleep.png" % OUT)
	_shot(vp, "%s/../crops/face_sleep.png" % OUT)
	m.cam_yaw = side_yaw + 0.45
	m.cam_pitch = 0.62
	m.cam_dist = 1.45
	m.fix_dist = 1.45
	for _r in 6:
		m._apply_camera()
		await process_frame
	_shot(vp, "%s/../crops/face_sleep_34.png" % OUT)
	print("FLAT_EYE_FACE_SHOTS_DONE")
	quit(0)


func _shot(vp, path: String) -> void:
	var tex = vp.get_texture()
	var img: Image = tex.get_image()
	img.save_png(path)
	print("SHOT ", path)
