extends SceneTree
## v34 grounding verification: close-ups on flat sand, grass slope, dock.
## Default cam + low side cam × idle / walk / run.
## godot --path . --fixed-fps 30 -s res://dev/grounding_v34.gd

const OUT := "screenshots/v34/grounding"

func _initialize() -> void:
	call_deferred("_go")


func _shot(m: Node, name: String) -> void:
	RenderingServer.force_draw()
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	var img: Image = m.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	# Also note sole gaps for the log.
	var mesh: float = m._surface(m.player.global_position.x, m.player.global_position.z)
	var lo := 999.0
	for side in range(2):
		var fp = m.boy.foot_points(side)
		lo = minf(lo, minf(fp[0].y, fp[1].y) - mesh)
	print("SHOT %s bone_min=%.1fcm" % [path, lo * 100.0])


func _place(m: Node, xz: Vector2, yaw: float) -> void:
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m.face_yaw = yaw
	m.player.rotation.y = yaw
	m.ground_y = y
	if m.boy:
		m.boy.has_prev = false


func _cam_default(m: Node) -> void:
	m.ex_yaw = m.face_yaw + PI + 0.45
	m.ex_pitch = 0.22
	m.ex_dist = 3.2
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist


func _cam_low_side(m: Node) -> void:
	# Low side: almost ground-level, profile of feet.
	m.ex_yaw = m.face_yaw + PI * 0.5
	m.ex_pitch = 0.02
	m.ex_dist = 2.4
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist


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


func _suite(m: Node, tag: String, xz: Vector2, yaw: float) -> void:
	_place(m, xz, yaw)
	await _settle(m, 25)
	# Idle
	_cam_default(m)
	await _settle(m, 12)
	await _shot(m, "after_%s_idle_default" % tag)
	_cam_low_side(m)
	await _settle(m, 10)
	await _shot(m, "after_%s_idle_side" % tag)
	# Walk
	_cam_default(m)
	await _drive(m, Vector2(0.0, -0.75), 40)
	await _shot(m, "after_%s_walk_default" % tag)
	_cam_low_side(m)
	await _drive(m, Vector2(0.0, -0.75), 25)
	await _shot(m, "after_%s_walk_side" % tag)
	# Run
	_cam_default(m)
	await _drive(m, Vector2(0.0, -1.0), 35)
	await _shot(m, "after_%s_run_default" % tag)
	_cam_low_side(m)
	await _drive(m, Vector2(0.0, -1.0), 20)
	await _shot(m, "after_%s_run_side" % tag)
	await _settle(m, 15)


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
	# Day + low tier: blob/AO must ground him when sun shadows are off (phone).
	if m.night_on:
		m._toggle_night()
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	# Clear the feet — hide bottom help text for close-ups.
	if m.lbl_hint:
		m.lbl_hint.visible = false
	for _i in 40:
		await process_frame
	# Flat sand near spawn / dock apron.
	var sand := Vector2(1.35, m.island.dock_start_z + 4.0)
	await _suite(m, "sand", sand, -0.35)
	# Gentle grass rise just inland of the beach (avoid cliff/campfire bowls).
	var grass := Vector2(3.2, m.island.dock_start_z + 7.5)
	await _suite(m, "slope", grass, -0.6)
	# Dock deck.
	var dock := Vector2(0.15, m.island.dock_end_z + 2.2)
	await _suite(m, "dock", dock, 0.0)
	print("GROUNDING SHOTS DONE")
	quit(0)
