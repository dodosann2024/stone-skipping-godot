class_name Ambience
extends Node

var ocean: AudioStreamPlayer
var steps: Array[AudioStreamPlayer] = []
var muted := false


func _ready() -> void:
	ocean = AudioStreamPlayer.new()
	ocean.stream = load("res://assets/audio/ocean_loop.ogg")
	ocean.volume_db = -14.0
	if ocean.stream != null:
		ocean.stream.loop = true
	add_child(ocean)
	for n in ["step_sand_0", "step_grass_0", "step_wood_0", "step_water_0"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.ogg" % n)
		p.volume_db = -8.0
		add_child(p)
		steps.append(p)


func start() -> void:
	if ocean.stream != null and not ocean.playing and not muted:
		ocean.play()


func foot(kind: String) -> void:
	if muted:
		return
	var i := 0
	if kind == "grass":
		i = 1
	elif kind == "wood":
		i = 2
	elif kind == "water":
		i = 3
	if i < steps.size() and steps[i].stream != null:
		steps[i].play()
