extends SceneTree
func _initialize() -> void:
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 0.95)
	e.ambient_light_energy = 0.85
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(-0.9, 0.4, 0); sun.light_energy = 1.25; root.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation = Vector3(-0.3, -2.2, 0); fill.light_energy = 0.35; root.add_child(fill)
	var boy := Boy.new(); root.add_child(boy)
	var cam := Camera3D.new(); cam.fov = 36; root.add_child(cam)
	var out := "/tmp/v22/faces"
	DirAccess.make_dir_recursive_absolute(out)
	# yaw 0 = -Z side in front of facing boy (model yaw PI)
	var shots := [
		["front", 0.0, 0.08, 2.35, 0.58],
		["34", 0.55, 0.10, 2.35, 0.58],
		["side", PI * 0.5, 0.08, 2.35, 0.58],
		["face_front", 0.0, 0.02, 0.85, 0.88],
		["face_close", 0.12, -0.02, 0.52, 0.90],
		["face_smile", 0.18, 0.0, 0.75, 0.88],
		["face_blink", 0.18, 0.0, 0.75, 0.88],
		["face_laugh", 0.2, 0.02, 0.9, 0.86],
		["face_oops", 0.2, 0.02, 0.9, 0.86],
		["game_like", 0.12, 0.28, 4.2, 0.72],
	]
	call_deferred("_go", boy, cam, shots, out)

func _go(boy, cam, shots, out) -> void:
	await process_frame
	await process_frame
	print("boy height-ish ", boy.meta.get("height", -1), " rest head ", boy.meta.get("rest", {}).get("head", []))
	for s in shots:
		boy.set_idle()
		boy._tick(0.05)
		match String(s[0]):
			"face_smile": boy.expr = "smile"
			"face_blink": boy.expr = "blink"
			"face_laugh": boy.expr = "laugh"
			"face_oops": boy.expr = "oops"
			_: boy.expr = "smile"
		boy._update_face(0.05)
		var yaw: float = float(s[1]); var pitch: float = float(s[2]); var dist: float = float(s[3]); var ty: float = float(s[4])
		var t := Vector3(0, ty, 0)
		# place camera in front of the boy (he faces -Z after model rotation PI)
		cam.position = t + Vector3(sin(yaw), pitch, -cos(yaw)) * dist
		cam.look_at(t, Vector3.UP)
		for _i in 3:
			await process_frame
		get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
		print("SHOT ", s[0], " cam ", cam.position)
	quit(0)
