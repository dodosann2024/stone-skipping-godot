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
		["front", "idle", 0.0, 0.0, 0.08, 2.1, 0.68],
		["face", "idle", 0.0, 0.25, 0.05, 1.0, 1.0],
		["side", "idle", 0.0, -PI / 2, 0.08, 2.1, 0.68],
		["back34", "idle", 0.0, PI * 0.8, 0.2, 2.2, 0.68],
		["charge_side", "charge", 1.0, -PI / 2, 0.1, 2.3, 0.6],
		["charge_back", "charge", 1.0, PI * 0.75, 0.15, 2.3, 0.6],
		["charge_front", "charge", 1.0, 0.3, 0.1, 2.3, 0.6],
		["charge_low", "charge", 0.2, -PI / 2, 0.1, 2.3, 0.6],
		["release_side", "release", 1.0, -PI / 2, 0.1, 2.3, 0.6],
		["release_top", "release", 1.0, PI * 0.75, 0.9, 2.4, 0.6],
		["follow_side", "follow", 1.0, -PI / 2, 0.1, 2.4, 0.6],
		["follow_back", "follow", 1.0, PI * 0.72, 0.2, 2.4, 0.6],
		["follow_low", "follow", 0.3, -PI / 2, 0.1, 2.4, 0.6],
		["cheer", "cheer", 1.0, 0.3, 0.1, 2.4, 0.7],
		["oops", "oops", 1.0, 0.3, 0.1, 2.4, 0.7],
	]

func _process(_d: float) -> bool:
	if i >= shots.size():
		return true
	var s: Array = shots[i]
	if wait == 0:
		boy.debug_pose(s[1], s[2])
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
		img.save_png(ProjectSettings.globalize_path("res://screenshots/v3/dev_%02d_%s.png" % [i, s[0]]))
		i += 1
		wait = 0
	return false
