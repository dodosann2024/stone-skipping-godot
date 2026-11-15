extends SceneTree
## Godot-side CDP drag stills: hold stick, low rear/side cam, feet + ground.
## Asserts discs stay hidden while locomoting and sole gaps stay in bar.
##   DISPLAY=:1 godot --path . --fixed-fps 60 -s res://dev/cdp_drag_godot_v36.gd

const OUT := "screenshots/v36"
var m: Node
var fails := 0


func _initialize() -> void:
	call_deferred("_go")


func _hide_hud() -> void:
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false


func _frame_cam(rear: bool) -> void:
	m.cam_fixed = true
	m.fix_target = m.player.global_position + Vector3(0, 0.28, 0)
	m.fix_yaw = m.face_yaw + (PI * 0.85 if rear else PI * 0.55)
	m.fix_pitch = 0.12
	m.fix_dist = 3.0
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	m._apply_camera(1.0)


func _check(tag: String) -> void:
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
	var any_disc := false
	for d in [m.boy.blob_l, m.boy.blob_r]:
		if d != null and d.visible:
			any_disc = true
			break
	var moving: bool = m.boy.anim == "move" and m.boy.move_w > 0.25 and m.boy.move_speed > 0.35
	if moving and any_disc:
		fails += 1
		print("DRAG FAIL ", tag, " disc visible while locomoting")
	# Each visible disc must sit under its nearest stance sole (< 3 cm).
	if any_disc:
		var mids: Array = m.boy.stance_sole_midpoints()
		for d2 in [m.boy.blob_l, m.boy.blob_r]:
			if d2 == null or not d2.visible:
				continue
			var bp: Vector3 = d2.global_position
			var best := 1e9
			for mid_v in mids:
				var mid: Vector3 = mid_v
				best = minf(best, Vector2(bp.x, bp.z).distance_to(Vector2(mid.x, mid.z)))
			if best > 0.03:
				fails += 1
				print("DRAG FAIL ", tag, " disc↔sole %.1fcm" % (best * 100.0))
	for side in range(2):
		if not m.boy._stance_locked[side]:
			continue
		var fp: Array = m.boy.foot_points(side)
		var heel: Vector3 = fp[0]
		var sy: float = m.island.collision_h(heel.x, heel.z, m.player.position.y, [m.boy.get_rid()])
		var gap: float = (heel.y - m.boy.sole_offset) - sy
		if gap < -0.01 or gap > 0.015:
			fails += 1
			print("DRAG FAIL ", tag, " heel gap %.1fcm" % (gap * 100.0))


func _shot(name: String, rear: bool) -> void:
	_hide_hud()
	_frame_cam(rear)
	for _i in 3:
		await process_frame
		_frame_cam(rear)
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
	_check(name)
	m._apply_camera(1.0)
	var path := "%s/%s.png" % [OUT, name]
	m.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(780, 844))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for _i in 45:
		await process_frame
	m.demo_mode = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 20:
		await process_frame
	var ds: float = m.island.dock_start_z
	var y: float = m._surface(2.6, ds + 6.5)
	m.player.position = Vector3(2.6, y, ds + 6.5)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = -0.4
	m.player.rotation.y = -0.4
	m.boy.rotation.y = -0.4
	for _i in 12:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.35, -0.85)
	# ~0.6 s into drag
	for _i in 36:
		await process_frame
	await _shot("cdp_drag_0p6", true)
	# hold longer
	for _i in 48:
		await process_frame
	await _shot("cdp_drag_hold", true)
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 40:
		await process_frame
	await _shot("cdp_after_release", false)
	print("DRAG fails=%d" % fails)
	if fails == 0:
		print("CDP_DRAG_GODOT PASS")
		quit(0)
	else:
		print("CDP_DRAG_GODOT FAILED")
		quit(1)
