class_name DebugHud
extends Control

var on := false
var log_pace := false
var walk_ms: Array[float] = []
var label: Label
var copy_btn: Button
var _font: Font
var _log_n := 0
var _p95 := 0.0
var _p95_at := -20


func _ready() -> void:
	on = OS.get_environment("R42_DEBUG") == "1"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if str(a).contains("debug=1"):
			on = true
	visible = on
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _with_cjk(load("res://assets/ui.otf") as Font)
	label = Label.new()
	label.position = Vector2(12, 96)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 1, 0.9))
	if _font != null:
		label.add_theme_font_override("font", _font)
	add_child(label)
	copy_btn = Button.new()
	copy_btn.text = "复制数据"
	copy_btn.position = Vector2(12, 230)
	copy_btn.custom_minimum_size = Vector2(96, 36)
	copy_btn.visible = on
	if _font != null:
		copy_btn.add_theme_font_override("font", _font)
	copy_btn.pressed.connect(_copy)
	add_child(copy_btn)


func note(delta: float, walking: bool) -> void:
	if not on:
		return
	var ms := delta * 1000.0
	if walking:
		walk_ms.append(ms)
		if walk_ms.size() > 1800:
			walk_ms.pop_front()
	var vp := get_viewport().get_viewport_rid()
	var vis_dc := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var vis_pr := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var sh_dc := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var sh_pr := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var p95 := _pct(0.95)
	label.text = "v46\n帧 %.1f ms\nwalk p95 %.1f ms  n=%d\n图元 %d  绘制 %d+%d" % [ms, p95, walk_ms.size(), vis_pr, vis_dc, sh_dc]
	_log_n += 1
	if _log_n == 8 or _log_n == 40 or _log_n == 120:
		print("PROFILE frame_ms=%.2f proc_ms=%.2f phys_ms=%.2f vis_dc=%d vis_prim=%d sh_dc=%d sh_prim=%d" % [ms, proc, phys, vis_dc, vis_pr, sh_dc, sh_pr])
	if log_pace and walking:
		print("PACE %.2f" % ms)


func _pct(q: float) -> float:
	if walk_ms.is_empty():
		return 0.0
	if walk_ms.size() - _p95_at < 12:
		return _p95
	var s: Array[float] = walk_ms.duplicate()
	s.sort()
	var i := clampi(int(float(s.size() - 1) * q), 0, s.size() - 1)
	_p95 = float(s[i])
	_p95_at = walk_ms.size()
	return _p95


func _with_cjk(font: Font) -> Font:
	if font == null or not (font is FontFile):
		return font
	var fb := load("res://assets/cjk_fallback.ttf") as Font
	if fb == null:
		return font
	var ff := font as FontFile
	if not ff.fallbacks.has(fb):
		ff.fallbacks.append(fb)
	return ff


func _copy() -> void:
	DisplayServer.clipboard_set(label.text)
