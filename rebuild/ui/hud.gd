class_name Hud
extends Control

signal action(name: String)

var title: Label
var hint: Label
var record: Label
var night_btn: Button
var sound_btn: Button
var throw_btn: Button
var sit_btn: Button
var up_btn: Button
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/ui.otf") as Font
	title = _label("海岛打水漂", Vector2(16, 12), 22)
	record = _label("最高纪录：弹跳 0 次 · 最远 0.0 米", Vector2(16, 40), 14)
	hint = _label("左下摇杆走路，推到底就跑 · 拖屏幕转视角\n打水漂要去码头尽头", Vector2(16, 760), 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -78
	hint.offset_bottom = -16
	hint.offset_left = 12
	hint.offset_right = -12
	var names := ["观景", "固定视角", "声音：开", "夜晚"]
	for i in names.size():
		var b := _button(names[i], Vector2(250, 16 + i * 52))
		if names[i] == "夜晚":
			night_btn = b
		elif names[i].begins_with("声音"):
			sound_btn = b
		b.pressed.connect(_on_btn.bind(names[i]))
	throw_btn = _button("打水漂", Vector2(250, 240))
	throw_btn.visible = false
	throw_btn.pressed.connect(_on_btn.bind("打水漂"))
	sit_btn = _button("坐下", Vector2(250, 292))
	sit_btn.visible = false
	sit_btn.pressed.connect(_on_btn.bind("坐下"))
	up_btn = _button("起来", Vector2(250, 344))
	up_btn.visible = false
	up_btn.pressed.connect(_on_btn.bind("起来"))


func _on_btn(name: String) -> void:
	emit_signal("action", name)


func _label(text: String, pos: Vector2, size: int) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.position = pos
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	lab.add_theme_constant_override("shadow_offset_x", 1)
	lab.add_theme_constant_override("shadow_offset_y", 1)
	if _font != null:
		lab.add_theme_font_override("font", _font)
	add_child(lab)
	return lab


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(124, 44)
	b.add_theme_font_size_override("font_size", 16)
	if _font != null:
		b.add_theme_font_override("font", _font)
	add_child(b)
	return b
