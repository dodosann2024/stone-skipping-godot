extends SceneTree
## Low side-on close-ups — BOTH feet + ground contact must be in frame.
##   DISPLAY=:1 godot --path . --fixed-fps 60 -s res://dev/gik_shots_only_v36.gd

const OUT := "screenshots/v36"
var m: Node


func _initialize() -> void:
	call_deferred("_go")


func _hide_hud() -> void:
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false


func _shot(name: String, yaw_off: float, pitch: float, dist: float) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	_hide_hud()
	m.cam_fixed = true
	m.demo_mode = false
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
	# Aim just above the soles — both feet + ground contact must stay in frame.
	m.fix_target = m.player.global_position + Vector3(0, 0.22, 0)
	m.fix_yaw = m.face_yaw + yaw_off
	m.fix_pitch = pitch
	m.fix_dist = dist
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	for _i in 6:
		m._apply_camera(1.0)
		await process_frame
		m.fix_target = m.player.global_position + Vector3(0, 0.22, 0)
		m.cam_target = m.fix_target
		m._apply_camera(1.0)
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
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
	m.boy._update_blob()


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(900, 844))
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

	# Uphill — idle double-support so both feet plant, then low side-on.
	_place(Vector2(2.6, ds + 6.5), -0.4)
	for _i in 8:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.9)
	for _i in 40:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 30:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_uphill", PI * 0.5, 0.06, 3.2)

	# Downhill
	if m.joy:
		m.joy.value = Vector2(0.0, 0.9)
	for _i in 50:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 30:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_downhill", PI * 0.5, 0.06, 3.2)

	# Cross-slope — face along contour, camera from downhill side; full body + feet.
	_place(Vector2(3.0, ds + 5.8), 0.0)
	for _i in 8:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.85, 0.1)
	for _i in 35:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 30:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_cross", PI * 0.52, 0.05, 3.6)

	# Dock lip — centered on planks, both feet + deck contact, low side-on.
	_place(Vector2(0.0, ds - 0.6), PI)
	for _i in 20:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.25)
	for _i in 20:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 35:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_dock_lip", PI * 0.55, 0.08, 3.4)

	print("GIK_SHOTS_DONE")
	quit(0)
