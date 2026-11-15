extends SceneTree
## Low side-on close-ups via the game's fixed-cam pipeline (so explore follow can't yank).
##   DISPLAY=:1 godot --path . --fixed-fps 60 -s res://dev/gik_shots_only_v36.gd

const OUT := "screenshots/v36"
var m: Node


func _initialize() -> void:
	call_deferred("_go")


func _hide_hud() -> void:
	for n in ["HUD", "TitleLabel", "HintLabel", "Banner", "RecordLabel"]:
		var node = m.find_child(n, true, false)
		if node and node is CanvasItem:
			(node as CanvasItem).visible = false
	if m.joy:
		m.joy.visible = false
		if m.joy.get_parent() and m.joy.get_parent() is CanvasItem:
			(m.joy.get_parent() as CanvasItem).visible = false
	# Walk common UI roots.
	for c in m.get_children():
		if c is CanvasLayer:
			for ch in c.get_children():
				if ch is Control and ch != m.joy:
					var t := str(ch.name).to_lower()
					if "btn" in t or "title" in t or "hint" in t or "record" in t or "banner" in t:
						ch.visible = false


func _shot(name: String, side_sign: float) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	_hide_hud()
	m.cam_fixed = true
	m.demo_mode = false
	# Side-on: yaw = face ± 90°, nearly horizontal pitch, close dolly.
	m.fix_target = m.player.global_position + Vector3(0, 0.48, 0)
	m.fix_yaw = m.face_yaw + PI * 0.5 * side_sign
	m.fix_pitch = 0.10
	m.fix_dist = 2.6
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	m._apply_camera(1.0)
	for _i in 3:
		await process_frame
		# Re-assert framing each frame (orbit decay shouldn't drift).
		m.fix_target = m.player.global_position + Vector3(0, 0.48, 0)
		m.cam_target = m.fix_target
		m.cam_yaw = m.fix_yaw
		m.cam_pitch = m.fix_pitch
		m.cam_dist = m.fix_dist
		m._apply_camera(1.0)
	m.boy._reassert_foot_plants()
	await process_frame
	m._apply_camera(1.0)
	var path := "%s/%s.png" % [OUT, name]
	m.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path, " cam=", m.camera.global_position, " boy=", m.player.global_position)


func _place(xz: Vector2, yaw: float) -> void:
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = yaw
	m.player.rotation.y = yaw
	m.boy.rotation.y = yaw
	m.boy._pelvis_drop = 0.0
	m.boy._pelvis_drop_s = 0.0
	if m.boy.model:
		m.boy.model.position = m.boy.model_base
	m.boy._reassert_foot_plants()


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(780, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	for _i in 40:
		await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	m.cam_fixed = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 25:
		await process_frame
	var ds: float = m.island.dock_start_z

	_place(Vector2(2.6, ds + 6.5), -0.4)
	for _i in 8:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.9)
	for _i in 50:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_uphill", 1.0)

	if m.joy:
		m.joy.value = Vector2(0.0, 0.9)
	for _i in 55:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_downhill", 1.0)

	_place(Vector2(2.8, ds + 6.0), 0.0)
	for _i in 8:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.9, 0.0)
	for _i in 45:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_cross", 1.0)

	_place(Vector2(0.25, ds - 0.5), PI)
	for _i in 12:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.4)
	for _i in 35:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 10:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_dock_lip", 1.0)

	print("GIK_SHOTS_DONE")
	quit(0)
