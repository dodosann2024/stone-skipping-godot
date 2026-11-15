class_name Ambience
extends Node

var ocean: AudioStreamPlayer
var steps: Array[AudioStreamPlayer] = []
var splash_player: AudioStreamPlayer
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
	splash_player = AudioStreamPlayer.new()
	splash_player.stream = _splash_wav()
	splash_player.volume_db = -6.0
	add_child(splash_player)


func start() -> void:
	if ocean.stream != null and not ocean.playing and not muted:
		ocean.play()


func splash() -> void:
	if muted or splash_player == null or splash_player.stream == null:
		return
	splash_player.play()


func _splash_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := 4200
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 14.0)
		var s := sin(t * TAU * 380.0) * 0.35 + (rng.randf() * 2.0 - 1.0) * 0.45
		s *= env
		var v := int(clampf(s, -1.0, 1.0) * 28000.0)
		data[i * 2] = v & 255
		data[i * 2 + 1] = (v >> 8) & 255
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


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
