extends SceneTree
## renders the campfire alone (dev check): godot --path . -s dev/firetest.gd
func _init() -> void:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.85)
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 3.2
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.85
	e.adjustment_contrast = 0.92
	e.fog_enabled = true
	e.fog_light_color = Color(0.80, 0.86, 0.88)
	e.fog_density = 0.0045
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.55, 0.2)
	ground.material_override = gm
	root3.add_child(ground)
	var f := Campfire.new()
	root3.add_child(f)
	f.build()
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 3.4), Vector3(0, 0.9, 0))
	var dist := float(OS.get_environment("FIRE_DIST")) if OS.has_environment("FIRE_DIST") else 3.4
	cam.look_at_from_position(Vector3(0, 0.35 + dist * 0.25, dist), Vector3(0, 0.5, 0))
	await create_timer(3.0).timeout
	for k in 3:
		get_root().get_texture().get_image().save_png("/tmp/v8/fire_test_%d.png" % k)
		await create_timer(0.27).timeout
	quit()
