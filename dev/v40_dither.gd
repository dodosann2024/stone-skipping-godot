extends SceneTree
## On/off cutout stills from one camera. Same shaders the game draws.
##   xvfb-run -a godot --path . --fixed-fps 30 -s res://dev/v40_dither.gd

const OUT := "screenshots/v40"


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for _i in 45:
		await process_frame
	m.audio_started = true
	if m.start_overlay:
		m.start_overlay.visible = false
	var xz := Vector2(3.8, m.island.dock_start_z + 6.2)
	var y: float = m._surface(xz.x, xz.y)
	m.player_ctrl.write_body(Vector3(xz.x, y, xz.y), -0.9)
	m.demo_cam = true
	m.demo_nocut = false
	var focus: Vector3 = m.player.global_position + Vector3(0, 0.7, 0)
	var cam_pos := focus + Vector3(-1.8, 1.35, 1.6)
	var off: Vector3 = cam_pos - focus
	m.cam_target = focus
	m.cam_dist = off.length()
	m.cam_yaw = atan2(off.x, off.z)
	m.cam_pitch = asin(clampf(off.y / maxf(m.cam_dist, 0.01), -1.0, 1.0))
	m._cam_arm_k = 1.0
	for _i in 24:
		m.cam_target = m.player.global_position + Vector3(0, 0.7, 0)
		m._cam_arm_k = 1.0
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var on_path := ProjectSettings.globalize_path("res://%s/dither_on.png" % OUT)
	m.get_viewport().get_texture().get_image().save_png(on_path)
	print("DITHER_ON focus=", m._cut_focus)

	m.demo_nocut = true
	for _i in 10:
		m.cam_target = m.player.global_position + Vector3(0, 0.7, 0)
		m._cam_arm_k = 1.0
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var off_path := ProjectSettings.globalize_path("res://%s/dither_off.png" % OUT)
	m.get_viewport().get_texture().get_image().save_png(off_path)
	print("DITHER_OFF")

	var on_img: Image = Image.load_from_file(on_path)
	var off_img: Image = Image.load_from_file(off_path)
	if on_img == null or off_img == null:
		print("DITHER_FAIL missing")
		quit(1)
		return
	var diff_n := 0
	var samp_n := 0
	var hh: int = mini(on_img.get_height(), off_img.get_height())
	var ww: int = mini(on_img.get_width(), off_img.get_width())
	for py in range(0, hh, 4):
		for px in range(0, ww, 4):
			var ca: Color = on_img.get_pixel(px, py)
			var cb: Color = off_img.get_pixel(px, py)
			var d: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			if d > 0.12:
				diff_n += 1
			samp_n += 1
	var pct: float = 100.0 * float(diff_n) / maxf(float(samp_n), 1.0)
	print("DITHER_DIFF pct=%.1f" % pct)
	if pct < 4.0:
		print("DITHER_FAIL weak")
		quit(1)
		return
	print("DITHER_PASS")
	quit(0)
