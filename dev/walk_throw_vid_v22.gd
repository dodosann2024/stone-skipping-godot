extends SceneTree
## Capture a short walk + throw clip at 390x844 for the v22 deliverable.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out_dir := "/tmp/v22/vidframes"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# wipe old frames
	var d := DirAccess.open(out_dir)
	if d:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if n.ends_with(".png"):
				d.remove(n)
			n = d.get_next()

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.90, 0.95)
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.15
	root.add_child(sun)
	var boy := Boy.new()
	root.add_child(boy)
	var cam := Camera3D.new()
	cam.fov = 42
	root.add_child(cam)
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)

	await process_frame
	await process_frame
	if boy.blob:
		boy.blob.visible = false

	var frame := 0
	var t := 0.0
	# walk cycle while camera orbits slightly in front
	boy.set_move(1.2)
	for i in 70:
		t += 1.0 / 30.0
		boy._tick(1.0 / 30.0)
		boy.position.z = t * 0.55
		var look := boy.position + Vector3(0, 0.72, 0)
		cam.position = look + Vector3(0.15, 0.35, -3.2)
		cam.look_at(look, Vector3.UP)
		await process_frame
		if i % 2 == 0:
			vp.get_texture().get_image().save_png("%s/f_%04d.png" % [out_dir, frame])
			frame += 1

	# charge + throw
	boy.set_move(0.0)
	boy.set_idle()
	boy.charge(0.85)
	for i in 25:
		boy._tick(1.0 / 30.0)
		var look2 := boy.position + Vector3(0, 0.72, 0)
		cam.position = look2 + Vector3(0.2, 0.28, -3.0)
		cam.look_at(look2, Vector3.UP)
		await process_frame
		if i % 2 == 0:
			vp.get_texture().get_image().save_png("%s/f_%04d.png" % [out_dir, frame])
			frame += 1
	boy.start_throw(0.9)
	for i in 55:
		boy._tick(1.0 / 30.0)
		var look3 := boy.position + Vector3(0, 0.72, 0)
		cam.position = look3 + Vector3(0.25, 0.25, -2.9)
		cam.look_at(look3, Vector3.UP)
		await process_frame
		if i % 2 == 0:
			vp.get_texture().get_image().save_png("%s/f_%04d.png" % [out_dir, frame])
			frame += 1
	print("FRAMES ", frame)
	quit(0)
