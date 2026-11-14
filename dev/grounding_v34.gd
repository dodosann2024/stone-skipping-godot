extends SceneTree
## v34 grounding verification: close-ups on flat sand, grass slope, dock.
## Default follow cam + true low SIDE-ON (demo_cam, skips prop blockers) × idle / walk / run.
## godot --path . --fixed-fps 30 -s res://dev/grounding_v34.gd

const OUT := "screenshots/v34/grounding"

func _initialize() -> void:
	call_deferred("_go")


func _shot(m: Node, name: String) -> void:
	RenderingServer.force_draw()
	await m.get_tree().process_frame
	RenderingServer.force_draw()
	await m.get_tree().process_frame
	var img: Image = m.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	var mesh: float = m._surface(m.player.global_position.x, m.player.global_position.z)
	var lo := 999.0
	for side in range(2):
		var fp = m.boy.foot_points(side)
		lo = minf(lo, minf(fp[0].y, fp[1].y) - mesh)
	print("SHOT %s bone_min=%.1fcm pos=(%.2f,%.2f,%.2f)" % [
		path, lo * 100.0, m.player.global_position.x, m.player.global_position.y, m.player.global_position.z])


func _place(m: Node, xz: Vector2, yaw: float) -> void:
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.face_yaw = yaw
	m.player.rotation.y = yaw
	m.ground_y = y
	if m.boy:
		m.boy.has_prev = false
		m.boy.rotation.y = yaw


func _cam_default(m: Node) -> void:
	m.demo_cam = false
	m.cam_fixed = false
	m.ex_yaw = m.face_yaw + PI + 0.45
	m.ex_pitch = 0.22
	m.ex_dist = 3.2
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist


## True low side-on profile. demo_cam + empty track skips cam_blockers so barrels/foliage
## stay between lens and boy (cutout must open them — proof, not a dodge).
func _cam_low_side(m: Node) -> void:
	m.cam_fixed = false
	m.demo_cam = true
	m.demo_track.clear()
	var feet: Vector3 = m.player.global_position + Vector3(0.0, 0.12, 0.0)
	var yaw: float = m.face_yaw
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var cam_pos: Vector3 = feet + right * 1.95 + Vector3(0.0, 0.28, 0.0)
	var look: Vector3 = feet + Vector3(0.0, 0.18, 0.0)
	var off: Vector3 = cam_pos - look
	m.cam_target = look
	m.cam_dist = off.length()
	m.cam_yaw = atan2(off.x, off.z)
	m.cam_pitch = asin(clampf(off.y / maxf(m.cam_dist, 0.01), -1.0, 1.0))
	m.fix_target = look
	m.fix_yaw = m.cam_yaw
	m.fix_pitch = m.cam_pitch
	m.fix_dist = m.cam_dist


func _retarget_side(m: Node) -> void:
	_cam_low_side(m)


func _settle(m: Node, n: int = 20) -> void:
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in n:
		await process_frame


func _drive(m: Node, stick: Vector2, frames: int) -> void:
	if m.joy:
		m.joy.value = stick
	for _i in frames:
		await process_frame


func _drive_side(m: Node, stick: Vector2, frames: int, hold_yaw: float) -> void:
	if m.joy:
		m.joy.value = stick
	for _i in frames:
		m.face_yaw = hold_yaw
		m.player.rotation.y = hold_yaw
		_retarget_side(m)
		await process_frame


func _suite(m: Node, tag: String, xz: Vector2, yaw: float) -> void:
	_place(m, xz, yaw)
	await _settle(m, 22)
	# Idle default
	_cam_default(m)
	await _settle(m, 14)
	await _shot(m, "after_%s_idle_default" % tag)
	# Idle true side-on at feet
	_place(m, Vector2(m.player.position.x, m.player.position.z), yaw)
	_cam_low_side(m)
	await _settle(m, 16)
	await _shot(m, "after_%s_idle_side" % tag)
	# Walk default
	_cam_default(m)
	await _drive(m, Vector2(0.0, -0.75), 40)
	await _shot(m, "after_%s_walk_default" % tag)
	# Walk true side-on: short stride under forced profile cam
	var walk_yaw: float = yaw
	if m.joy:
		m.joy.value = Vector2.ZERO
	await _settle(m, 4)
	_place(m, Vector2(m.player.position.x, m.player.position.z), walk_yaw)
	_cam_low_side(m)
	await _drive_side(m, Vector2(0.0, -0.55), 22, walk_yaw)
	m.face_yaw = walk_yaw
	m.player.rotation.y = walk_yaw
	_retarget_side(m)
	await _settle(m, 3)
	await _shot(m, "after_%s_walk_side" % tag)
	if m.joy:
		m.joy.value = Vector2.ZERO
	# Run default
	_cam_default(m)
	await _drive(m, Vector2(0.0, -1.0), 32)
	await _shot(m, "after_%s_run_default" % tag)
	# Run true side-on
	var run_yaw: float = yaw
	if m.joy:
		m.joy.value = Vector2.ZERO
	await _settle(m, 4)
	_place(m, Vector2(m.player.position.x, m.player.position.z), run_yaw)
	_cam_low_side(m)
	await _drive_side(m, Vector2(0.0, -0.9), 16, run_yaw)
	m.face_yaw = run_yaw
	m.player.rotation.y = run_yaw
	_retarget_side(m)
	await _settle(m, 3)
	await _shot(m, "after_%s_run_side" % tag)
	if m.joy:
		m.joy.value = Vector2.ZERO
	m.demo_cam = false
	m.cam_fixed = false
	await _settle(m, 8)


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var ps := load("res://main.tscn") as PackedScene
	var m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	if m.night_on:
		m._toggle_night()
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	if m.lbl_hint:
		m.lbl_hint.visible = false
	for _i in 40:
		await process_frame
	# Open sand near shore path — clear of bush walls for foot contact proof.
	var sand := Vector2(0.15, m.island.dock_start_z + 3.2)
	await _suite(m, "sand", sand, 0.0)
	# Gentle slope on open grass (east of path), not buried in leaf sprays.
	var grass := Vector2(4.6, m.island.dock_start_z + 6.0)
	await _suite(m, "slope", grass, -0.4)
	# Dock: boy near barrels.
	var dock := Vector2(0.35, m.island.dock_end_z + 2.55)
	await _suite(m, "dock", dock, 0.0)
	# Forced occlusion — camera past barrels looking at boy; cutout must dither them open.
	# Empty demo_track skips cam_blockers so the lens stays behind the barrels (the proof case).
	_place(m, Vector2(0.2, m.island.dock_end_z + 2.55), 0.0)
	m.demo_cam = true
	m.demo_track.clear()
	m.cam_fixed = false
	m.demo_nocut = false
	var focus: Vector3 = m.player.global_position + Vector3(0.0, 0.55, 0.0)
	var cam_pos := Vector3(3.6, Island.DECK_Y + 1.05, m.island.dock_end_z + 2.55)
	var off: Vector3 = cam_pos - focus
	var dist: float = off.length()
	var yaw: float = atan2(off.x, off.z)
	var pitch: float = asin(clampf(off.y / maxf(dist, 0.01), -1.0, 1.0))
	for _i in 22:
		m.cam_target = focus
		m.cam_dist = dist
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m._cam_arm_k = 1.0
		m._cam_arm_want = 1.0
		m._cam_slide = 0.0
		await process_frame
	await _shot(m, "after_dock_occlude_barrel")
	# Same framing with cut disabled — barrels must fully hide him (control).
	m.demo_nocut = true
	for _i in 8:
		m.cam_target = focus
		m.cam_dist = dist
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m._cam_arm_k = 1.0
		await process_frame
	await _shot(m, "after_dock_occlude_barrel_nocut")
	m.demo_nocut = false
	print("GROUNDING SHOTS DONE")
	quit(0)
