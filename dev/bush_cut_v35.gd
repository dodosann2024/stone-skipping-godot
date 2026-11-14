extends SceneTree
## Walk the boy into a bush with the camera behind a leaf wall; save stills proving dither.
##   godot --path . --fixed-fps 30 -s res://dev/bush_cut_v35.gd

const OUT := "screenshots/v35"


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 40:
		await process_frame

	# Spot near dense foliage east of path.
	var xz := Vector2(3.8, m.island.dock_start_z + 6.2)
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = -0.9
	m.player.rotation.y = -0.9
	m.demo_cam = true
	m.demo_track.clear()
	# Camera past the bush looking at the boy (force cutout path) — keep high enough
	# that slope silhouette does not fake-bury the legs.
	var focus: Vector3 = m.player.global_position + Vector3(0, 0.7, 0)
	var cam_pos := focus + Vector3(-1.8, 1.35, 1.6)
	var off: Vector3 = cam_pos - focus
	m.cam_target = focus
	m.cam_dist = off.length()
	m.cam_yaw = atan2(off.x, off.z)
	m.cam_pitch = asin(clampf(off.y / maxf(m.cam_dist, 0.01), -1.0, 1.0))
	m._cam_arm_k = 1.0
	m.demo_nocut = false
	for _i in 20:
		m.cam_target = m.player.global_position + Vector3(0, 0.7, 0)
		m._cam_arm_k = 1.0
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png("%s/bush_cut_on.png" % OUT)
	print("SHOT bush_cut_on focus=", m._cut_focus, " cr_f=", m._cut_cr_f)

	m.demo_nocut = true
	for _i in 8:
		m.cam_target = m.player.global_position + Vector3(0, 0.7, 0)
		m._cam_arm_k = 1.0
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png("%s/bush_cut_off.png" % OUT)
	print("SHOT bush_cut_off")

	# Walk into bush under follow cam.
	m.demo_nocut = false
	m.demo_cam = false
	m.cam_fixed = false
	if m.joy:
		m.joy.value = Vector2(0.2, -0.7)
	for _i in 40:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png("%s/bush_walk_follow.png" % OUT)
	print("SHOT bush_walk_follow")

	# Assert cutout actually changes pixels (web-visible dither / open cone).
	var on_img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://%s/bush_cut_on.png" % OUT))
	var off_img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://%s/bush_cut_off.png" % OUT))
	if on_img == null or off_img == null:
		print("BUSH_CUT FAIL missing stills")
		quit(1)
	var diff_n := 0
	var samp_n := 0
	var step := 4
	var hh: int = mini(on_img.get_height(), off_img.get_height())
	var ww: int = mini(on_img.get_width(), off_img.get_width())
	for py in range(0, hh, step):
		for px in range(0, ww, step):
			var ca: Color = on_img.get_pixel(px, py)
			var cb: Color = off_img.get_pixel(px, py)
			var d: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			if d > 0.12:
				diff_n += 1
			samp_n += 1
	var pct: float = 100.0 * float(diff_n) / maxf(float(samp_n), 1.0)
	print("BUSH_CUT diff_pct=%.1f" % pct)
	if pct < 4.0:
		print("BUSH_CUT FAIL dither too weak (%.1f%% < 4%%)" % pct)
		quit(1)
	print("BUSH_CUT PASS")
	quit(0)
