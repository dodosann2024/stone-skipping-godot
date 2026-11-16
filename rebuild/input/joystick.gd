class_name JoyStick
extends Control
## Fixed base so the review drag at (54, 754) is still a run.

var value := Vector2.ZERO
var _finger := -1
var _origin := Vector2(54, 754)
var _releasing := false
var _dirty := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	var origin := Vector2(54, vp.y - 90.0)
	if origin.distance_squared_to(_origin) > 0.25:
		_origin = origin
		_dirty = true
	if _finger < 0 and _releasing:
		var k := 1.0 - exp(-delta / 0.07)
		value = value.lerp(Vector2.ZERO, k)
		_dirty = true
		if value.length() < 0.02:
			value = Vector2.ZERO
			_releasing = false
	if _dirty:
		queue_redraw()
		_dirty = false


func take(event: InputEventScreenTouch) -> bool:
	var vp := get_viewport_rect().size
	_origin = Vector2(54, vp.y - 90.0)
	if event.pressed:
		if _finger >= 0:
			return false
		if event.position.distance_to(_origin) > Constants.STICK_RADIUS + 36.0:
			return false
		_finger = event.index
		_releasing = false
		_apply(event.position)
		return true
	if event.index == _finger:
		_finger = -1
		_releasing = value.length() > 0.02
		return true
	return false


func drag(event: InputEventScreenDrag) -> bool:
	if event.index != _finger:
		return false
	_apply(event.position)
	return true


func _apply(pos: Vector2) -> void:
	var d := pos - _origin
	if d.length() > Constants.STICK_RADIUS:
		d = d.normalized() * Constants.STICK_RADIUS
	value = d / Constants.STICK_RADIUS
	_dirty = true


func _draw() -> void:
	draw_circle(_origin, Constants.STICK_RADIUS, Color(1, 1, 1, 0.16))
	draw_arc(_origin, Constants.STICK_RADIUS, 0, TAU, 24, Color(1, 1, 1, 0.45), 2.0)
	var shown := value
	if shown.length() < Constants.DEADZONE:
		shown = Vector2.ZERO
	var knob := _origin + shown * Constants.STICK_RADIUS
	var hot := shown.length() > 0.72
	draw_circle(knob, 26.0, Color(1, 0.85, 0.45, 0.9) if hot else Color(1, 1, 1, 0.85))
