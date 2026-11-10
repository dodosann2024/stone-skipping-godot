extends SceneTree
## Drives the boy through idle -> walk -> run -> turns -> zig-zags -> stop (dev/gait_probe.gd) and checks
## foot planting.
## godot --path . --fixed-fps 30 -s res://dev/gait_view.gd -- --out=/tmp/gait [--side] [--every=2] [--csv=f] [--nolock]
## Prints the worst planted-foot slide per segment; with --out also saves frames (follow camera, checker
## floor), with --csv the worst slide of every frame.

var probe: GaitProbe
var boy: Boy
var cam: Camera3D
var out_dir := ""
var every := 2
var side_cam := false
var cam_pos := Vector3.ZERO
var csv: FileAccess
var nolock := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--every="):
			every = int(a.substr(8))
		if a == "--side":
			side_cam = true
		if a.begins_with("--csv="):
			csv = FileAccess.open(a.substr(6), FileAccess.WRITE)
			csv.store_line("t,slide,speed,run_k,anim")
		if a == "--nolock":
			nolock = true
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.82, 0.9)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.6, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor.mesh = pm
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.62, 0.5, 0.36)); img.set_pixel(1, 1, Color(0.62, 0.5, 0.36))
	img.set_pixel(1, 0, Color(0.55, 0.43, 0.3)); img.set_pixel(0, 1, Color(0.55, 0.43, 0.3))
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = ImageTexture.create_from_image(img)
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.uv1_scale = Vector3(60, 60, 1)
	floor.material_override = fm
	root.add_child(floor)
	boy = Boy.new()
	root.add_child(boy)
	boy.set("lock_enabled", not nolock)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)

func _process(dt: float) -> bool:
	if probe == null:
		probe = GaitProbe.new(boy)
		probe.log_slides = true
	if not probe.step(dt):
		print("GAIT slide max %.4f m  mean %.4f m over %d planted frames, %d quick steps" % [probe.slide_max,
			probe.slide_sum / maxf(probe.slide_n, 1), probe.slide_n, int(boy.get("steps_taken") if boy.get("steps_taken") != null else 0)])
		print("GAIT footprints %d for %d footsteps, spot drift max %.1f mm" % [probe.prints, probe.steps, probe.print_err * 1000.0])
		for line in probe.report():
			print("GAIT ", line)
		return true
	if csv:
		csv.store_line("%.4f,%.5f,%.3f,%.3f,%s" % [probe.t, probe.worst, probe.speed, boy.run_k, boy.anim])
	var fwd := Basis(Vector3.UP, probe.yaw) * Vector3(0, 0, -1)
	var want: Vector3
	if side_cam:
		want = boy.position + fwd.cross(Vector3.UP) * -2.3 + Vector3(0, 0.7, 0)
	else:
		want = boy.position + Basis(Vector3.UP, probe.yaw + 2.4) * Vector3(0, 0, -2.2) + Vector3(0, 1.7, 0)
	cam_pos = want if probe.frame <= 1 else cam_pos.lerp(want, 1.0 - exp(-dt * 3.0))
	cam.position = cam_pos
	cam.look_at(boy.position + Vector3(0, 0.5, 0), Vector3.UP)
	if out_dir != "" and probe.frame % every == 0:
		var im := get_root().get_texture().get_image()
		if im:
			im.save_png(out_dir.path_join("g_%04d.png" % (probe.frame / every)))
	return false
