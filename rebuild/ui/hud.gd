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
var lie_btn: Button
var pose_btn: Button
var up_btn: Button
var banner: Label
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/ui.otf") as Font
	title = _label("海岛打水漂", Vector2(16, 12), 22)
	var frame_btn := _button("帧时间", Vector2(16, 68))
	frame_btn.custom_minimum_size = Vector2(88, 32)
	frame_btn.pressed.connect(_on_btn.bind("帧时间"))
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
	throw_btn = _button("打水漂", Vector2(250, 236))
	throw_btn.visible = false
	throw_btn.pressed.connect(_on_btn.bind("打水漂"))
	pose_btn = _button("半蹲", Vector2(250, 288))
	pose_btn.visible = false
	pose_btn.pressed.connect(_on_btn.bind("半蹲"))
	sit_btn = _button("坐下", Vector2(250, 340))
	sit_btn.visible = false
	sit_btn.pressed.connect(_on_btn.bind("坐下"))
	lie_btn = _button("躺下", Vector2(250, 392))
	lie_btn.visible = false
	lie_btn.pressed.connect(_on_btn.bind("躺下"))
	up_btn = _button("起来", Vector2(250, 444))
	up_btn.visible = false
	up_btn.pressed.connect(_on_btn.bind("起来"))
	banner = _label("", Vector2(16, 120), 18)
	banner.size = Vector2(360, 28)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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
	b.add_theme_color_override("font_color", Color(0.12, 0.28, 0.42))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.86, 0.94, 0.98, 0.92)
	box.border_color = Color(0.35, 0.62, 0.82)
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 8
	box.content_margin_right = 8
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.95, 0.98, 1.0)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	if _font != null:
		b.add_theme_font_override("font", _font)
	add_child(b)
	return b
