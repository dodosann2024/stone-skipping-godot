extends Node
## Frame order:
## 1. Physics (60 Hz): stick → PlayerBody.move_and_slide on Ground. One root writer.
## 2. Render: AnimationPlayer → FootIK (skeleton space) → camera arm → occluder fade.
## Nothing else samples the ground to move the body.

var ground: Ground
var player: PlayerBody
var rig: CameraRig
var fader: OccluderFader
var joy: JoyStick
var hud: Hud
var dbg: DebugHud
var amb: Ambience
var props: Props
var live := false
var night := false
var sun: DirectionalLight3D
var water_mat: ShaderMaterial
var _orbit := -1
var _best_skips := 0
var _best_dist := 0.0
var _sitting := false


func _ready() -> void:
	_world()
	_player()
	_camera()
	_ui()
	_audio()
	var q := _query()
	if q.contains("debug=1"):
		dbg.on = true
		dbg.visible = true
	if q.contains("occ=0"):
		fader.enabled = false
	if OS.get_environment("R42_ROUTE") == "1" or OS.get_environment("R42_SHOT") == "1" or DisplayServer.get_name() == "headless":
		_begin()
	else:
		_start_gate()


func _world() -> void:
	var envn := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.82, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.8)
	env.ambient_light_energy = 0.85
	envn.environment = env
	add_child(envn)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)
	ground = Ground.new()
	add_child(ground)
	props = Props.new()
	add_child(props)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	water.mesh = plane
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water.material_override = water_mat
	water.position.y = 0.02
	add_child(water)


func _player() -> void:
	player = PlayerBody.new()
	var ends := IslandData.dock_ends()
	player.position = Vector3(0.0, Constants.DECK_Y + 0.05, ends.y + 1.3)
	player.face_yaw = PI
	player.rotation.y = PI
	player.cam_basis = Basis(Vector3.UP, PI)
	add_child(player)
	player.ground = ground
	await get_tree().process_frame
	if player.boy != null:
		player.boy.bind_ground(ground)
	player.stepped.connect(_on_step)


func _camera() -> void:
	rig = CameraRig.new()
	rig.player = player
	rig.yaw = player.face_yaw
	add_child(rig)
	fader = OccluderFader.new()
	fader.camera = rig.cam
	fader.player = player
	fader.props = props
	add_child(fader)


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.action.connect(_on_action)
	dbg = DebugHud.new()
	layer.add_child(dbg)
	joy = JoyStick.new()
	layer.add_child(joy)


func _audio() -> void:
	amb = Ambience.new()
	add_child(amb)


func _start_gate() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Start"
	layer.layer = 10
	add_child(layer)
	var b := Button.new()
	b.text = "点击开始"
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	var font := load("res://assets/ui.otf") as Font
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 28)
	layer.add_child(b)
	b.pressed.connect(func() -> void:
		layer.queue_free()
		_begin()
	)


func _begin() -> void:
	live = true
	amb.start()


func _process(delta: float) -> void:
	if water_mat != null:
		water_mat.set_shader_parameter("game_time", Time.get_ticks_msec() / 1000.0)
	if not live:
		return
	player.stick = joy.value
	_prompts()
	if dbg != null:
		dbg.note(delta, player.speed > 0.12)


func _unhandled_input(event: InputEvent) -> void:
	if not live or _sitting:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if joy.take(touch):
			player.stick = joy.value
			return
		if touch.pressed:
			_orbit = touch.index
		elif touch.index == _orbit:
			_orbit = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if joy.drag(drag):
			player.stick = joy.value
			return
		if drag.index == _orbit:
			rig.yaw -= drag.relative.x * 0.006
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_W:
			joy.value = Vector2(0, -1)
		elif k.keycode == KEY_S:
			joy.value = Vector2(0, 1)


func _prompts() -> void:
	var p := player.global_position
	var ends := IslandData.dock_ends()
	var on_tee := absf(p.x) < 3.2 and p.z < ends.y + 4.2 and p.z > ends.y - 1.0
	hud.throw_btn.visible = on_tee and not _sitting
	var near_bench := false
	for item in props.items:
		if item.name == "Bench" and item.global_position.distance_to(p) < 1.8:
			near_bench = true
	hud.sit_btn.visible = near_bench and not _sitting
	hud.up_btn.visible = _sitting


func _on_action(name: String) -> void:
	if name == "夜晚" or name == "白天":
		night = not night
		sun.light_energy = 0.28 if night else 1.15
		sun.light_color = Color(0.65, 0.75, 1.0) if night else Color(1, 0.97, 0.9)
		hud.night_btn.text = "白天" if night else "夜晚"
		_save()
	elif name == "声音：开" or name == "声音：关":
		amb.muted = not amb.muted
		hud.sound_btn.text = "声音：关" if amb.muted else "声音：开"
		if amb.muted:
			amb.ocean.stop()
		else:
			amb.start()
	elif name == "打水漂":
		_throw()
	elif name == "观景":
		rig.pitch = deg_to_rad(50.0)
	elif name == "固定视角":
		pass
	elif name == "坐下":
		_sitting = true
		joy.value = Vector2.ZERO
		player.speed = 0.0
	elif name == "起来":
		_sitting = false


func _throw() -> void:
	var stone := SkipStone.new()
	add_child(stone)
	var from := player.global_position + Vector3(0, 1.1, 0)
	var fwd := Vector3(-sin(player.face_yaw), 0.18, -cos(player.face_yaw))
	stone.launch(from, fwd.normalized() * 9.0)
	await get_tree().create_timer(2.4).timeout
	if not is_instance_valid(stone):
		return
	var dist := stone.global_position.distance_to(from)
	if stone.skips > _best_skips or dist > _best_dist:
		_best_skips = maxi(_best_skips, stone.skips)
		_best_dist = maxf(_best_dist, dist)
		hud.record.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [_best_skips, _best_dist]


func _on_step(kind: String) -> void:
	amb.foot(kind)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "night", night)
	cf.save("user://settings.cfg")


func _query() -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("window.location.search", true)
		return str(v)
	var acc := ""
	for a in OS.get_cmdline_user_args():
		acc += str(a)
	return acc
