class_name AngleSlider
extends Control
## Small vertical slider for one throw angle (launch elevation or stone tilt), in the buttons' pastel style:
## title, a glyph that draws the angle, the track (with the sweet-spot band) and the value in degrees.
## Drag anywhere on it (finger or mouse); the value snaps to whole degrees.

signal changed(v: float)

const INK := Color(0.05, 0.35, 0.55)
const EDGE := Color(0.1, 0.45, 0.65)

var title := ""
var kind := "el"   # el: arrow over the water | tilt: the stone tilted on the water
var vmin := 0.0
var vmax := 45.0
var value := 20.0
var band := Vector2(INF, INF)   # highlighted best range (deg)
var font: Font
var dragging := false
var grab_y := 0.0
var grab_v := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_value(v: float) -> void:
	v = clampf(roundf(v), vmin, vmax)
	if v != value:
		value = v
		queue_redraw()


func _track() -> Vector2:
	var top := size.y * 0.36
	return Vector2(top, size.y - 46.0)


func _y_of(v: float) -> float:
	var tr := _track()
	return lerpf(tr.y, tr.x, (v - vmin) / (vmax - vmin))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		dragging = e.pressed
		if e.pressed:
			grab_y = e.position.y
			grab_v = value
			# a tap on the track jumps there; a press on the knob just grabs it
			if absf(e.position.y - _y_of(value)) > 30.0 and e.position.y > _track().x - 20.0:
				_set_from(e.position.y)
				grab_y = e.position.y
				grab_v = value
		accept_event()
	elif e is InputEventMouseMotion and dragging:
		var tr := _track()
		var v: float = grab_v + (grab_y - e.position.y) / (tr.y - tr.x) * (vmax - vmin)
		var old := value
		set_value(v)
		if value != old:
			changed.emit(value)
		accept_event()


func _set_from(y: float) -> void:
	var tr := _track()
	var old := value
	set_value(lerpf(vmin, vmax, clampf((tr.y - y) / (tr.y - tr.x), 0.0, 1.0)))
	if value != old:
		changed.emit(value)


func _text(s: String, at: Vector2, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	if font == null:
		return
	var w := size.x
	var cx := w * 0.5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.62 if dragging else 0.5)
	bg.border_color = Color(EDGE, 0.55)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(int(minf(w * 0.5, 34.0)))
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	_text(title, Vector2(cx, 30), 21, INK)
	# glyph: a water line and the angle drawn true to size
	var gy := size.y * 0.36 - 34.0
	var gl := Vector2(cx - w * 0.32, gy)
	draw_line(gl, gl + Vector2(w * 0.64, 0), Color(0.3, 0.62, 0.72, 0.9), 3.0)
	var a := deg_to_rad(value)
	if kind == "el":
		var o := Vector2(cx - w * 0.28, gy - 4)
		var tip := o + Vector2(cos(a), -sin(a)) * w * 0.5
		draw_line(o, tip, INK, 3.0)
		var d := (tip - o).normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([tip + d * 6, tip - d * 6 + n * 6, tip - d * 6 - n * 6]), INK)
	else:
		var c := Vector2(cx, gy - 9)
		var pts := PackedVector2Array()
		for i in 14:
			var t := TAU * i / 14.0
			pts.append(c + Vector2(cos(t) * w * 0.26, sin(t) * 6.0).rotated(-a))
		draw_colored_polygon(pts, Color(0.5, 0.52, 0.57))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.25, 0.27, 0.3), 1.5)
	# track, sweet-spot band, knob
	var tr := _track()
	draw_line(Vector2(cx, tr.x), Vector2(cx, tr.y), Color(EDGE, 0.28), 10.0)
	if band.x < INF:
		draw_line(Vector2(cx, _y_of(band.y)), Vector2(cx, _y_of(band.x)), Color(0.4, 0.78, 0.5, 0.75), 10.0)
	if vmin < 0.0:
		draw_line(Vector2(cx - 12, _y_of(0.0)), Vector2(cx + 12, _y_of(0.0)), Color(EDGE, 0.5), 2.0)
	var ky := _y_of(value)
	draw_circle(Vector2(cx, ky), 17.0, Color(1.0, 0.82, 0.3))
	draw_arc(Vector2(cx, ky), 17.0, 0.0, TAU, 24, Color(0.55, 0.3, 0.05), 2.5)
	_text("%d°" % roundi(value), Vector2(cx, size.y - 14), 26, INK)
