extends SceneTree
## Godot-side slope up/down + run sequence with low cam, 7 frames each.
##   DISPLAY=:1 godot --path . --fixed-fps 60 -s res://dev/cdp_slope_godot_v36.gd

const OUT := "screenshots/v36"
var m: Node
var fails := 0


func _initialize() -> void:
	call_deferred("_go")


func _hide_hud() -> void:
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false


func _frame_cam() -> void:
	m.cam_fixed = true
	m.fix_target = m.player.global_position + Vector3(0, 0.36, 0)
	m.fix_yaw = m.face_yaw + PI * 0.5
	m.fix_pitch = 0.09
	m.fix_dist = 2.7
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	m._apply_camera(1.0)


func _check(tag: String) -> void:
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
	m._upload_foot_ao()
	var mids: Array = m.boy.stance_sole_midpoints()
	if mids.is_empty():
		return
	var mid: Vector3 = mids[0]
	if mids.size() > 1:
		mid = (mids[0] as Vector3).lerp(mids[1] as Vector3, 0.5)
	var blob_xz := Vector2.ZERO
	var n := 0
	for d in [m.boy.blob_l, m.boy.blob_r]:
		if d != null and d.visible:
			var p: Vector3 = d.global_position
			blob_xz += Vector2(p.x, p.z)
			n += 1
	# Terrain AO positions aren't MeshInstances — assert discs when visible,
	# else sole height only.
	if n > 0:
		blob_xz /= float(n)
		var dlen := Vector2(blob_xz.x - mid.x, blob_xz.y - mid.z).length()
		if dlen > 0.03:
			fails += 1
			print("SLOPE FAIL ", tag, " blob ", "%.1fcm" % (dlen * 100.0))
	for side in range(2):
		if not m.boy._stance_locked[side]:
			continue
		var fp: Array = m.boy.foot_points(side)
		var heel: Vector3 = fp[0]
		var sy: float = m.island.collision_h(heel.x, heel.z, m.player.position.y, [m.boy.get_rid()])
		var gap: float = (heel.y - m.boy.sole_offset) - sy
		if gap < -0.01 or gap > 0.015:
			fails += 1
			print("SLOPE FAIL ", tag, " heel gap ", "%.1fcm" % (gap * 100.0))


func _burst(prefix: String, stick: Vector2, n: int) -> void:
	if m.joy:
		m.joy.value = stick
	for i in n:
		await process_frame
		_frame_cam()
		await process_frame
		_check("%s_%d" % [prefix, i])
		_hide_hud()
		m._apply_camera(1.0)
		var path := "%s/%s_%d.png" % [OUT, prefix, i]
		m.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	if m.joy:
		m.joy.value = Vector2.ZERO


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(900, 844))
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
	print("SLOPE uphill")
	await _burst("cdp_slope_up", Vector2(0.2, -0.9), 7)
	print("SLOPE downhill")
	await _burst("cdp_slope_dn", Vector2(0.1, 0.9), 7)
	print("SLOPE run")
	await _burst("cdp_run", Vector2(0.35, -1.0), 7)
	print("SLOPE fails=%d" % fails)
	if fails == 0:
		print("SLOPE_SEQ PASS")
		quit(0)
	else:
		print("SLOPE_SEQ FAILED")
		quit(1)
