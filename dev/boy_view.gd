extends SceneTree
## Renders the boy's key poses from several angles: godot --path . -s res://dev/boy_view.gd

var boy: Boy
var cam: Camera3D
var shots := []
var i := 0
var wait := 0

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.82, 0.9)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(6, 6)
	floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.62, 0.45, 0.3)
	floor.material_override = fm
	root.add_child(floor)
	boy = Boy.new()
	root.add_child(boy)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	# [name, pose, power, cam yaw (0 = in front of the boy), pitch, dist, target y]
	shots = [
		["face_front", "idle", 0.0, 0.0, 0.04, 0.85, 1.13],
		["face_close", "idle", 0.0, 0.25, -0.08, 0.5, 1.17],
		["face_34", "idle", 0.0, 0.6, 0.05, 0.9, 1.13],
		["face_side", "idle", 0.0, -PI / 2, 0.05, 0.9, 1.13],
		["face_grit", "grit", 0.0, 0.3, 0.04, 0.85, 1.13],
		["face_laugh", "cheer", 0.0, 0.3, 0.04, 1.0, 1.0],
		["front", "idle", 0.0, 0.0, 0.08, 2.6, 0.77],
		["front34", "idle", 0.0, 0.6, 0.12, 2.6, 0.77],
		["side", "idle", 0.0, -PI / 2, 0.08, 2.6, 0.77],
		["back34", "idle", 0.0, PI * 0.8, 0.2, 2.7, 0.77],
		["charge_side", "charge", 1.0, -PI / 2, 0.1, 2.8, 0.70],
		["charge_back", "charge", 1.0, PI * 0.75, 0.15, 2.8, 0.70],
		["release_side", "release", 1.0, -PI / 2, 0.1, 2.8, 0.70],
		["follow_side", "follow", 1.0, -PI / 2, 0.1, 2.9, 0.70],
		["follow_back", "follow", 1.0, PI * 0.72, 0.2, 2.9, 0.70],
		["charge_c_side", "charge_c", 1.0, -PI / 2, 0.1, 2.7, 0.60],
		["charge_c_34", "charge_c", 1.0, 0.9, 0.15, 2.7, 0.60],
		["release_c_side", "release_c", 1.0, -PI / 2, 0.1, 2.7, 0.60],
		["follow_c_side", "follow_c", 1.0, -PI / 2, 0.1, 2.7, 0.60],
		["follow_c_back", "follow_c", 1.0, PI * 0.72, 0.2, 2.8, 0.60],
		["walk0", "walk", 0.0, -PI / 2, 0.08, 2.7, 0.75],
		["walk25", "walk", 0.25, -PI / 2, 0.08, 2.7, 0.75],
		["walk_34", "walk", 0.1, 0.6, 0.12, 2.7, 0.75],
		["run0", "run", 0.0, -PI / 2, 0.08, 2.7, 0.75],
		["run20", "run", 0.2, -PI / 2, 0.08, 2.7, 0.75],
		["run_34", "run", 0.1, 0.6, 0.12, 2.7, 0.75],
		["sit_edge", "sit_edge", 0.0, -PI / 2, 0.08, 2.7, 0.65],
		["sit_ground", "sit_ground", 0.0, -PI / 2, 0.08, 2.7, 0.55],
		["sleep", "sleep", 0.0, -PI / 2, 0.08, 2.7, 0.75],
		["sun", "sun", 0.0, -PI / 2, 0.08, 2.7, 0.75],
		["cheer", "cheer", 1.0, 0.3, 0.1, 2.9, 0.85],
		["oops", "oops", 1.0, 0.3, 0.1, 2.9, 0.85],
	]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--only="):
			var keep := a.substr(7).split(",")
			shots = shots.filter(func(x: Array) -> bool: return String(x[0]) in keep)

var out_dir := "res://screenshots/v6/dev"

func _process(_d: float) -> bool:
	if i >= shots.size():
		return true
	var s: Array = shots[i]
	if wait == 0:
		boy.debug_pose(s[1], s[2], s[2] if String(s[1]) in ["walk", "run"] else 0.3)
		var yaw: float = s[3]
		var pitch: float = s[4]
		var dist: float = s[5]
		var tgt := Vector3(0, s[6], 0)
		# boy faces -Z, so "front" camera sits at -Z
		cam.position = tgt + Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
		cam.look_at(tgt, Vector3.UP)
	wait += 1
	if wait > 3:
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join("dev_%s.png" % s[0]) if out_dir.begins_with("/") else ProjectSettings.globalize_path(out_dir.path_join("dev_%s.png" % s[0])))
		i += 1
		wait = 0
	return false
