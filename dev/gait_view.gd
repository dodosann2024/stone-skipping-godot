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
# ground contacts: heel (under the back of the foot bone) and the ball / toe pad (under the toe bone)
const POINTS := ["heel_l", "toe_l", "heel_r", "toe_r"]
var contact := {}     # point -> [bone index, offset in the bone's rest frame]
var rest_h: Array = []
var prev_pt: Array = []
var prev_down: Array = []
var slide_max := 0.0
var slide_sum := 0.0
var slide_n := 0
# [from, to, label]: per-segment planted-contact drift (worst per frame, total per planted stretch)
const SEGS := [[1.5, 4.0, "walk straight"], [6.3, 8.0, "run straight"], [8.0, 10.5, "run turning 1.3 rad/s"],
	[10.5, 11.0, "run -> walk"], [11.0, 12.0, "walk turning -1.6 rad/s"], [12.0, 14.5, "stop -> idle"]]
var seg_max := {}
var seg_sum := {}
var seg_n := {}
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
		for sg in SEGS:
			var lb: String = sg[2]
			print("GAIT %-24s max %.1f mm/frame  mean %.2f mm/frame  (%d planted frames)" % [lb, float(seg_max.get(lb, 0.0)) * 1000.0,
				float(seg_sum.get(lb, 0.0)) / maxf(float(seg_n.get(lb, 0)), 1.0) * 1000.0, int(seg_n.get(lb, 0))])
		return true
	# a heel / toe contact counts as planted while it sits at its standing height; measure its drift
	if contact.is_empty():
		var sk := boy.skel
		for s in ["l", "r"]:
			var fb := sk.find_bone("foot_" + s)
			var bb := sk.find_bone("ball_" + s)
			var fr := sk.get_bone_global_rest(fb)
			var br := sk.get_bone_global_rest(bb)
			var g := float(boy.meta["ground"])
			contact["heel_" + s] = [fb, fr.affine_inverse() * Vector3(fr.origin.x, g, fr.origin.z - 0.035)]
			contact["toe_" + s] = [bb, br.affine_inverse() * Vector3(br.origin.x, g, br.origin.z + 0.02)]
	boy.tree.advance(0.0)
	for i in POINTS.size():
		var c: Array = contact[POINTS[i]]
		var pt: Vector3 = boy.skel.global_transform * (boy.skel.get_bone_global_pose(c[0]) * (c[1] as Vector3))
		if rest_h.size() < POINTS.size():
			rest_h.append(pt.y); prev_pt.append(pt); prev_down.append(false)
			continue
		var down: bool = pt.y < float(rest_h[i]) + 0.004
		if down and prev_down[i] and frame > 3:
			var d := Vector2(pt.x - prev_pt[i].x, pt.z - prev_pt[i].z).length()
			if d > 0.004:
				print("  slide t=%.2f %s d=%.3f anim=%s spd=%.2f" % [t, POINTS[i], d, boy.anim, speed])
			slide_max = maxf(slide_max, d)
			for sg in SEGS:
				if t >= float(sg[0]) and t < float(sg[1]):
					var lb: String = sg[2]
					seg_max[lb] = maxf(float(seg_max.get(lb, 0.0)), d)
					seg_sum[lb] = float(seg_sum.get(lb, 0.0)) + d
					seg_n[lb] = int(seg_n.get(lb, 0)) + 1
			slide_sum += d
			slide_n += 1
		prev_pt[i] = pt
		prev_down[i] = down
	var acc := 6.0 if tg[0] > speed else 9.0
	var want_spd: float = tg[0]
	if want_spd < 0.05 and boy.settling():
		want_spd = 0.5     # as main.gd: finish the step before stopping
	speed = move_toward(speed, want_spd, acc * dt)
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
