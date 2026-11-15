class_name BoyVisual
extends Node3D
## Loads the approved boy. One scale. Clips keep their own speed.

var anim: AnimationPlayer
var skel: Skeleton3D
var ik: FootIK
var clip_idle := "idle"
var clip_walk := "walk"
var clip_run := "run"
var _clip := ""


func _ready() -> void:
	var packed := load("res://assets/boy.glb") as PackedScene
	if packed == null:
		push_error("boy glb missing")
		return
	var model := packed.instantiate()
	model.scale = Vector3.ONE * Constants.MODEL_SCALE
	model.rotation.y = PI
	add_child(model)
	anim = _find_player(model)
	skel = _find_skel(model)
	if skel != null:
		ik = FootIK.new()
		ik.name = "FootIK"
		skel.add_child(ik)
	if anim != null:
		_pick_names()
		anim.play(clip_idle)


func bind_ground(ground: Ground) -> void:
	if ik != null:
		ik.ground = ground


func set_speed(speed: float) -> void:
	if anim == null:
		return
	var clip := clip_idle
	var scale := 1.0
	if speed > 1.55:
		clip = clip_run
		scale = clampf(speed / 2.3, 0.85, 1.4)
	elif speed > 0.12:
		clip = clip_walk
		scale = clampf(speed / 0.64, 0.85, 2.0)
	if clip != _clip:
		anim.play(clip)
		_clip = clip
	anim.speed_scale = scale


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
