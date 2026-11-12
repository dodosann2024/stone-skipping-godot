extends SceneTree
func _initialize() -> void:
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.78, 0.80, 0.82)  # concept-like grey
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.90, 0.92, 0.95)
	e.ambient_light_energy = 0.95
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(-0.85, 0.35, 0); sun.light_energy = 1.15; root.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation = Vector3(-0.25, -2.1, 0); fill.light_energy = 0.45; root.add_child(fill)
	var boy := Boy.new(); root.add_child(boy)
	var cam := Camera3D.new(); cam.fov = 32; root.add_child(cam)
	var out := "/tmp/v22/faces"
	DirAccess.make_dir_recursive_absolute(out)
	# Target face/eye line (~0.78) — never the hair crown. Same framing language as concept sheet.
	# [name, yaw, pitch_offset, dist, look_y]
	var shots := [
		["front", 0.0, 0.06, 2.55, 0.58],
		["34", 0.55, 0.08, 2.55, 0.58],
		["side", PI * 0.5, 0.06, 2.55, 0.58],
		["face_front", 0.0, 0.04, 0.95, 0.78],
		["face_close", 0.08, 0.02, 0.62, 0.78],
		["face_smile", 0.12, 0.03, 0.85, 0.78],
		["face_blink", 0.12, 0.03, 0.85, 0.78],
		["face_laugh", 0.15, 0.04, 0.95, 0.78],
		["face_oops", 0.15, 0.04, 0.95, 0.78],
		["game_like", 0.10, 0.22, 4.0, 0.70],
	]
	call_deferred("_go", boy, cam, shots, out)

func _go(boy, cam, shots, out) -> void:
	await process_frame
	await process_frame
	print("boy height-ish ", boy.meta.get("height", -1), " rest head ", boy.meta.get("rest", {}).get("head", []))
	if boy.blob:
		boy.blob.visible = false
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
		# camera in front of boy (model faces -Z after yaw PI)
		cam.position = t + Vector3(sin(yaw), pitch, -cos(yaw)) * dist
		cam.look_at(t, Vector3.UP)
		for _i in 4:
			await process_frame
		get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
		print("SHOT ", s[0], " cam ", cam.position, " look ", t)
	quit(0)
