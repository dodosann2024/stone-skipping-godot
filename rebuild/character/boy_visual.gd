class_name BoyVisual
extends Node3D
## Loads the approved boy. One scale. Clips keep their own speed.

const _SideArm = preload("res://character/side_arm.gd")
const _RestPose = preload("res://character/rest_pose.gd")
const _ClipAuthor = preload("res://character/clip_author.gd")

var anim: AnimationPlayer
var skel: Skeleton3D
var ik: FootIK
var arm
var rest
var model: Node3D
var clip_idle := "idle"
var clip_walk := "walk"
var clip_run := "run"
var _clip := ""
var holding := false


func _ready() -> void:
	var packed := load("res://assets/boy.glb") as PackedScene
	if packed == null:
		push_error("boy glb missing")
		return
	model = packed.instantiate()
	model.scale = Vector3.ONE * Constants.MODEL_SCALE
	model.rotation.y = PI
	# Capsule bottom is this far above the body origin. The mesh feet sit on that contact.
	model.position.y = Constants.CAPSULE_BOTTOM
	_keep_full_lod(model)
	add_child(model)
	anim = _find_player(model)
	skel = _find_skel(model)
	_shadow_proxy()
	if skel != null:
		_pebble(skel)
		ik = FootIK.new()
		ik.name = "FootIK"
		skel.add_child(ik)
		arm = _SideArm.new()
		arm.name = "SideArm"
		skel.add_child(arm)
		skel.move_child(arm, 0)
		rest = _RestPose.new()
		rest.name = "RestPose"
		skel.add_child(rest)
	if anim != null:
		_pick_names()
		_ClipAuthor.build(anim)
		anim.play(clip_idle)


var pebble: MeshInstance3D


func _pebble(skel: Skeleton3D) -> void:
	var grip := BoneAttachment3D.new()
	grip.name = "PebbleGrip"
	grip.bone_name = "mixamorig_RightHand"
	grip.bone_idx = skel.find_bone("mixamorig_RightHand")
	skel.add_child(grip)
	pebble = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.028
	mesh.height = 0.056
	pebble.mesh = mesh
	# 5–6 cm across, flat, sitting in the palm along the finger axis (+Y).
	pebble.scale = Vector3(1.05, 0.38, 0.85)
	pebble.position = Vector3(0.0, 0.042, 0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.51, 0.48)
	mat.roughness = 0.38
	mat.metallic = 0.06
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.45
	mat.clearcoat_roughness = 0.22
	pebble.material_override = mat
	pebble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pebble.visible = false
	grip.add_child(pebble)


func _process(_delta: float) -> void:
	if pebble == null or arm == null:
		return
	pebble.visible = arm.playing and arm.phase < 0.52
	if not pebble.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var grip := pebble.get_parent() as Node3D
	if cam == null or grip == null:
		return
	var to_cam := (grip.global_transform.affine_inverse() * cam.global_position)
	if to_cam.length_squared() < 1e-6:
		return
	# A centimetre and a half toward the lens, so the pebble shows between the fingers.
	pebble.position = Vector3(0.0, 0.04, 0.012) + to_cam.normalized() * 0.015


func bind_ground(ground: Ground) -> void:
	if ik != null:
		ik.ground = ground


func hold_speed() -> void:
	pass


func set_speed(speed: float) -> void:
	if anim == null or holding:
		return
	var clip := clip_idle
	var scale := 1.0
	if speed > 1.35:
		clip = clip_run
		scale = clampf(speed / Constants.RUN_CLIP, 0.7, 1.15)
	elif speed > 0.08:
		clip = clip_walk
		scale = clampf(speed / Constants.WALK_CLIP, 0.62, 1.15)
	if clip != _clip:
		var blend := 0.2 if clip == clip_idle or _clip == clip_idle else 0.16
		anim.play(clip, blend)
		_clip = clip
	anim.speed_scale = scale


func find_clip(suffix: String) -> String:
	if anim == null:
		return ""
	for n in anim.get_animation_list():
		var s := str(n)
		if s == suffix or s.ends_with("/" + suffix):
			return s
	return ""


func play_clip(suffix: String, blend: float) -> String:
	var name := find_clip(suffix)
	if name == "" or anim == null:
		return ""
	var clip := anim.get_animation(name)
	if clip != null:
		var once := suffix.ends_with("enter") or suffix.ends_with("exit")
		if once:
			clip.loop_mode = Animation.LOOP_NONE
		else:
			clip.loop_mode = Animation.LOOP_LINEAR
	holding = true
	if ik != null:
		ik.paused = true
	anim.play(name, blend)
	anim.speed_scale = 1.0
	_clip = name
	return name


func clear_hold() -> void:
	holding = false
	if rest != null:
		rest.mode = ""
	if model != null:
		model.rotation = Vector3(0, PI, 0)
		model.position = Vector3(0, Constants.CAPSULE_BOTTOM, 0)
	if ik != null:
		ik.paused = false
	if anim != null:
		anim.play(clip_idle, 0.2)
		_clip = clip_idle


func lay_flat(kind: String) -> void:
	holding = true
	if ik != null:
		ik.paused = true
	if rest != null:
		rest.mode = ""
	if anim != null:
		anim.play(clip_idle, 0.15)
	if model == null:
		return
	if kind == "lounger":
		model.rotation = Vector3(deg_to_rad(-58.0), PI, 0)
		model.position = Vector3(0, 0.34, -0.05)
	else:
		model.rotation = Vector3(deg_to_rad(-80.0), PI, 0)
		model.position = Vector3(0, 0.20, 0.02)


func _keep_full_lod(node: Node) -> void:
	if node is GeometryInstance3D:
		var geo := node as GeometryInstance3D
		geo.lod_bias = 16.0
		# Colour pass keeps the full mesh. The shadow is the 5k proxy.
		geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_keep_full_lod(c)


func _shadow_proxy() -> void:
	if skel == null:
		return
	var packed := load("res://assets/boy_shadow.glb") as PackedScene
	if packed == null:
		push_error("boy shadow proxy missing")
		return
	var inst := packed.instantiate()
	var src := _find_mesh(inst)
	if src == null or src.mesh == null or src.skin == null:
		inst.free()
		push_error("boy shadow proxy has no skin")
		return
	var proxy := MeshInstance3D.new()
	proxy.name = "ShadowProxy"
	proxy.mesh = src.mesh
	proxy.skin = src.skin
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var caster := StandardMaterial3D.new()
	caster.albedo_color = Color(0.15, 0.15, 0.15)
	proxy.material_override = caster
	skel.add_child(proxy)
	proxy.skeleton = proxy.get_path_to(skel)
	inst.free()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


func _pick_names() -> void:
	var names := anim.get_animation_list()
	for n in names:
		var s := str(n)
		if s == "idle" or s.ends_with("/idle"):
			clip_idle = s
		elif s == "walk" or s.ends_with("/walk"):
			clip_walk = s
		elif s == "run" or s.ends_with("/run"):
			clip_run = s
	print("BOY_CLIPS idle=%s walk=%s run=%s n=%d" % [clip_idle, clip_walk, clip_run, names.size()])


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skel(c)
		if found != null:
			return found
	return null
