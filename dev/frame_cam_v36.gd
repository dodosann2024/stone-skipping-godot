extends SceneTree
## Headless framing smoke: walk 8 dirs + slope + run; assert head/feet UV in
## central 60% every frame. Also writes low-cam stills for visual check.
##   DISPLAY=:1 godot --path . --fixed-fps 60 -s res://dev/frame_cam_v36.gd

const OUT := "screenshots/v36"
# Central ~60% with a 2% tolerance for tall-phone KEEP_HEIGHT FOV.
const LO := 0.18
const HI := 0.82

var m: Node
var fails := 0
var margin_min := 1e9
var samples := 0


func _initialize() -> void:
	call_deferred("_go")


func _uv(world: Vector3) -> Vector2:
	var cam: Camera3D = m.camera
	if cam.is_position_behind(world):
		return Vector2(-1, -1)
	var screen: Vector2 = cam.unproject_position(world)
	var vp := m.get_viewport().get_visible_rect().size
	return Vector2(screen.x / vp.x, screen.y / vp.y)


func _check(tag: String) -> void:
	samples += 1
	var head_i: int = m.boy.skel.find_bone("mixamorig_Head")
	var head_w: Vector3 = m.player.global_position + Vector3(0, 1.25, 0)
	if head_i >= 0:
		head_w = m.boy.skel.global_transform * m.boy.skel.get_bone_global_pose(head_i).origin
	var foot_w := Vector3(m.player.global_position.x, m.player.global_position.y + 0.04, m.player.global_position.z)
	var acc := Vector3.ZERO
	var n := 0
	for side in range(2):
		if m.boy.anim == "move" and m.boy.move_w > 0.2 and not m.boy._stance_locked[side]:
			continue
		var fp: Array = m.boy.foot_points(side)
		var mid: Vector3 = (fp[0] as Vector3).lerp(fp[1] as Vector3, 0.5)
		var sy: float = m._surface(mid.x, mid.z)
		if mid.y - sy < 0.35:
			acc += Vector3(mid.x, sy + 0.02, mid.z)
			n += 1
	if n > 0:
		foot_w = acc / float(n)
	var huv := _uv(head_w)
	var fuv := _uv(foot_w)
	var ok_h := huv.x >= LO and huv.x <= HI and huv.y >= LO and huv.y <= HI
	var ok_f := fuv.x >= LO and fuv.x <= HI and fuv.y >= LO and fuv.y <= HI
	var marg := 1e9
	for uv in [huv, fuv]:
		marg = minf(marg, uv.x - LO)
		marg = minf(marg, HI - uv.x)
		marg = minf(marg, uv.y - LO)
		marg = minf(marg, HI - uv.y)
	margin_min = minf(margin_min, marg)
	if not ok_h or not ok_f:
		fails += 1
		if fails <= 12 or fails % 40 == 0:
			print("FRAME FAIL ", tag, " head=", huv, " feet=", fuv, " margin=", marg,
				" screen_h=", m.camera.unproject_position(head_w),
				" screen_f=", m.camera.unproject_position(foot_w),
				" vp=", m.get_viewport().get_visible_rect().size)


func _shot(name: String) -> void:
	m.boy._reassert_foot_plants()
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false
	await process_frame
	m.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("SHOT ", name)


func _burst_stick(stick: Vector2, frames: int, prefix: String) -> void:
	if m.joy:
		m.joy.value = stick
	var shot_i := 0
	for i in frames:
		await process_frame
		_check("%s_%d" % [prefix, i])
		if i % 7 == 0 and shot_i < 7:
			await _shot("%s_%d" % [prefix, shot_i])
			shot_i += 1
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 24:
		await process_frame
		_check("%s_after" % prefix)
	await _shot("%s_after" % prefix)
	if shot_i < 7:
		await _shot("%s_%d" % [prefix, mini(shot_i, 6)])


func _go() -> void:
	# Keep project viewport (720²). Stretch+forced 390×844 blew aspect to 720×1558
	# and NaN'd the camera. Framing math now uses phone-length arms even when
	# !_tall(); CDP web still runs at real 390×844.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for _i in 50:
		await process_frame
	print("FRAME vp=", m.get_viewport().get_visible_rect().size, " tall=", m._tall())
	m.demo_mode = false
	m.cam_fixed = false
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
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.40
	m.ex_dist = 4.6
	m._snap_explore_cam(false)
	for _i in 15:
		await process_frame
	m._cam_max_step_cm = 0.0
	m._cam_hill_lift = 0.0
	m._cam_hill_vel = 0.0
	m._cam_pos_vel = Vector3.ZERO

	print("FRAME 8-dir")
	var dirs: Array = [
		["n", Vector2(0, -0.85)],
		["ne", Vector2(0.55, -0.7)],
		["e", Vector2(0.9, 0)],
		["se", Vector2(0.55, 0.7)],
		["s", Vector2(0, 0.85)],
		["sw", Vector2(-0.55, 0.7)],
		["w", Vector2(-0.9, 0)],
		["nw", Vector2(-0.55, -0.7)],
	]
	for d in dirs:
		if m.joy:
			m.joy.value = d[1]
		for _i in 36:
			await process_frame
			_check("dir_%s" % d[0])
		await _shot("cdp_dir_%s" % d[0])
		if m.joy:
			m.joy.value = Vector2.ZERO
		for _i in 18:
			await process_frame
			_check("dir_%s_after" % d[0])

	print("FRAME slope/run")
	await _burst_stick(Vector2(0.2, -0.9), 56, "cdp_slope_up")
	await _burst_stick(Vector2(0.1, 0.9), 56, "cdp_slope_dn")
	await _burst_stick(Vector2(0.35, -1.0), 48, "cdp_run")

	print("FRAME samples=%d fails=%d margin_min=%.3f cam_step_cm=%.1f" % [
		samples, fails, margin_min, m._cam_max_step_cm
	])
	if fails == 0:
		print("FRAME_CAM PASS")
		quit(0)
	else:
		print("FRAME_CAM FAILED")
		quit(1)
