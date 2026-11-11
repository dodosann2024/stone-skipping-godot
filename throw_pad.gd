class_name ThrowPad
extends Control
## Throw-mode overlay (draws only, never takes input): the stone to swipe from, and while aiming the swipe
## arrow with a power ring round where the finger went down. Pastel like the buttons; the arrow turns
## coral when the swipe points back towards the kid (letting go there cancels).

const INK := Color(0.05, 0.35, 0.55)
const EDGE := Color(0.1, 0.45, 0.65)
const GOLD := Color(1.0, 0.8, 0.25)
const CORAL := Color(1.0, 0.5, 0.42)

var font: Font
var pad_c := Vector2.ZERO
var pad_r := 58.0
var show_pad := false
var pad_text := ""
var aiming := false
var from := Vector2.ZERO
var to := Vector2.ZERO
var power := 0.0
var cancel := false
var tip_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _text(s: String, at: Vector2, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.04, 0.18, 0.32, 0.75))
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _stone(c: Vector2, r: float, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var t := TAU * i / 16.0
		pts.append(c + Vector2(cos(t) * r, sin(t) * r * 0.42).rotated(a))
	draw_colored_polygon(pts, Color(0.55, 0.57, 0.62))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.32, 0.36), 2.0)


func _draw() -> void:
	if font == null:
		return
	if show_pad and not aiming:
		draw_circle(pad_c, pad_r, Color(1, 1, 1, 0.42))
		draw_arc(pad_c, pad_r, 0.0, TAU, 40, Color(EDGE, 0.75), 3.0)
		_stone(pad_c, pad_r * 0.5, -0.12)
		# chevrons: swipe up, towards the sea
		for k in 2:
			var y := pad_c.y - pad_r - 16.0 - k * 16.0
			var al := 0.75 - k * 0.3
			draw_polyline(PackedVector2Array([Vector2(pad_c.x - 16, y + 8), Vector2(pad_c.x, y - 4), Vector2(pad_c.x + 16, y + 8)]), Color(1, 1, 1, al), 4.0)
		if pad_text != "":
			_text(pad_text, pad_c + Vector2(0, pad_r + 30), 21, Color(1, 1, 1, 0.95))
	if not aiming:
		return
	var col := CORAL if cancel else Color(1, 1, 1, 0.92)
	draw_circle(from, 40.0, Color(1, 1, 1, 0.22))
	draw_arc(from, 40.0, 0.0, TAU, 40, Color(EDGE, 0.6), 2.0)
	if power > 0.0:
		draw_arc(from, 40.0, -PI * 0.5, -PI * 0.5 + TAU * power, 48, GOLD, 8.0)
	_stone(from, 18.0, -0.12)
	var d := to - from
	if d.length() > 46.0:
		var u := d.normalized()
		var a := from + u * 46.0
		var b := to
		# dashed shaft and a head
		var n := int((b - a).length() / 22.0)
		for i in n:
			draw_line(a + u * (i * 22.0), a + u * (i * 22.0 + 13.0), col, 6.0)
		var nn := Vector2(-u.y, u.x)
		draw_colored_polygon(PackedVector2Array([b + u * 14.0, b - u * 12.0 + nn * 13.0, b - u * 12.0 - nn * 13.0]), col)
	if tip_text != "":
		var at := to + Vector2(0, -34) if d.y < -10.0 else from + Vector2(0, -60)
		_text(tip_text, at, 26, CORAL if cancel else Color(1, 0.95, 0.6))
