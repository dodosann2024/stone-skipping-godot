class_name DebugHud
extends Control

var on := false
var walk_ms: Array[float] = []
var label: Label
var _font: Font


func _ready() -> void:
	on = OS.get_environment("R42_DEBUG") == "1"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if str(a).contains("debug=1"):
			on = true
	visible = on
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/ui.otf") as Font
	label = Label.new()
	label.position = Vector2(12, 96)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 1, 0.9))
	if _font != null:
		label.add_theme_font_override("font", _font)
	add_child(label)
	var copy := Button.new()
	copy.text = "复制数据"
	copy.position = Vector2(12, 210)
	copy.custom_minimum_size = Vector2(96, 36)
	if _font != null:
		copy.add_theme_font_override("font", _font)
	copy.pressed.connect(_copy)
	add_child(copy)


func note(delta: float, walking: bool) -> void:
	if not on:
		return
	var ms := delta * 1000.0
	if walking:
		walk_ms.append(ms)
		if walk_ms.size() > 1800:
			walk_ms.pop_front()
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var p95 := _pct(0.95)
	label.text = "v42 debug\n帧 %.1f ms\nwalk p95 %.1f ms  n=%d\n图元 %d" % [ms, p95, walk_ms.size(), prims]


func _pct(q: float) -> float:
	if walk_ms.is_empty():
		return 0.0
	var s := walk_ms.duplicate()
	s.sort()
	var i := clampi(int(float(s.size() - 1) * q), 0, s.size() - 1)
	return float(s[i])


func _copy() -> void:
	DisplayServer.clipboard_set(label.text)
