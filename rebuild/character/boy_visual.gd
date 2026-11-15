class_name BoyVisual
extends Node3D
## Loads the approved boy. One scale. Clips keep their own speed.

const _SideArm = preload("res://character/side_arm.gd")
const _RestPose = preload("res://character/rest_pose.gd")

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
	add_child(model)
	anim = _find_player(model)
	skel = _find_skel(model)
	if skel != null:
		ik = FootIK.new()
		ik.name = "FootIK"
		skel.add_child(ik)
		arm = _SideArm.new()
		arm.name = "SideArm"
		skel.add_child(arm)
		rest = _RestPose.new()
		rest.name = "RestPose"
		skel.add_child(rest)
	if anim != null:
		_pick_names()
		anim.play(clip_idle)


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
		scale = clampf(speed / Constants.RUN_CLIP, 0.85, 1.15)
	elif speed > 0.08:
		clip = clip_walk
		scale = clampf(speed / Constants.WALK_CLIP, 0.85, 1.15)
	if clip != _clip:
		anim.play(clip)
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
