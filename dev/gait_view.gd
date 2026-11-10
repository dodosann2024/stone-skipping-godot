extends SceneTree
## Drives the boy through idle -> walk -> run -> turns -> stop and checks foot planting.
## godot --path . --fixed-fps 30 -s res://dev/gait_view.gd -- --out=/tmp/gait [--side] [--every=2]
## Prints the worst planted-foot slide; with --out also saves frames (follow camera, checker floor).

var boy: Boy
var cam: Camera3D
var out_dir := ""
var every := 2
var side_cam := false
var t := 0.0
var frame := 0
var speed := 0.0
var yaw := 0.0
var prev_ankle: Array = [Vector3.ZERO, Vector3.ZERO]
var prev_plant: Array = [0.0, 0.0]
var prev_sgn: Array = [true, true]
var slide_max := 0.0
var slide_sum := 0.0
var slide_n := 0
var cam_pos := Vector3.ZERO

# [until t, target speed, yaw rate]
const PROFILE := [
	[1.0, 0.0, 0.0],
	[4.0, 1.15, 0.0],
	[5.5, 0.5, 0.0],
	[8.0, 2.7, 0.0],
	[10.5, 2.7, 1.3],
	[12.0, 1.15, -1.6],
	[13.5, 0.0, 0.0],
	[14.5, 0.0, 0.0],
]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--every="):
			every = int(a.substr(8))
		if a == "--side":
			side_cam = true
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
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)

func _target(tt: float) -> Array:
	for s in PROFILE:
		if tt < float(s[0]):
			return [float(s[1]), float(s[2])]
	return [-1.0, 0.0]

func _process(dt: float) -> bool:
	t += dt
	var tg := _target(t)
	if tg[0] < 0.0:
		print("GAIT slide max %.4f m  mean %.4f m over %d planted frames" % [slide_max, slide_sum / maxf(slide_n, 1), slide_n])
		return true
	# measure the rendered ankles while the foot claims to be planted
	for i in 2:
		var key := "foot_l" if i == 0 else "foot_r"
		var piv := Vector3(0, -Boy.ANKLE_H, -0.075) if float(boy.foot_pitch[i]) >= 0.0 else Vector3(0, -Boy.ANKLE_H, 0.06)
		var an: Vector3 = (boy.parts[key] as Node3D).global_transform * piv
		var sgn := float(boy.foot_pitch[i]) >= 0.0
		if float(boy.plant[i]) >= 1.0 and float(prev_plant[i]) >= 1.0 and frame > 3 and sgn == prev_sgn[i]:
			var d := Vector2(an.x - prev_ankle[i].x, an.z - prev_ankle[i].z).length()
			if d > 0.008:
				print("  slide t=%.2f foot=%d d=%.3f anim=%s spd=%.2f fw=%s pitch=%.2f" % [t, i, d, boy.anim, speed, boy.fw[i], boy.foot_pitch[i]])
			slide_max = maxf(slide_max, d)
			slide_sum += d
			slide_n += 1
		prev_ankle[i] = an
		prev_plant[i] = boy.plant[i]
		prev_sgn[i] = sgn
	var acc := 6.0 if tg[0] > speed else 9.0
	speed = move_toward(speed, tg[0], acc * dt)
	yaw += float(tg[1]) * dt * minf(speed / 1.0, 1.0)
	boy.rotation.y = yaw
	boy.position += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	if speed > 0.05:
		boy.set_move(speed)
	else:
		boy.set_move(0.0)
		boy.set_idle()
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var want: Vector3
	if side_cam:
		want = boy.position + fwd.cross(Vector3.UP) * -2.3 + Vector3(0, 0.7, 0)
	else:
		want = boy.position + Basis(Vector3.UP, yaw + 2.4) * Vector3(0, 0, -2.2) + Vector3(0, 1.7, 0)
	cam_pos = want if frame == 0 else cam_pos.lerp(want, 1.0 - exp(-dt * 3.0))
	cam.position = cam_pos
	cam.look_at(boy.position + Vector3(0, 0.5, 0), Vector3.UP)
	if out_dir != "" and frame % every == 0:
		var im := get_root().get_texture().get_image()
		if im:
			im.save_png(out_dir.path_join("g_%04d.png" % (frame / every)))
	frame += 1
	return false
