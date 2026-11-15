class_name JoyStick
extends Control
## Fixed base so the review drag at (54, 754) is still a run.

var value := Vector2.ZERO
var _finger := -1
var _origin := Vector2(54, 754)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var vp := get_viewport_rect().size
	_origin = Vector2(54, vp.y - 90.0)
	queue_redraw()


func take(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		if _finger >= 0:
			return false
		if event.position.distance_to(_origin) > Constants.STICK_RADIUS + 36.0:
			return false
		_finger = event.index
		_apply(_origin)
		return true
	if event.index == _finger:
		_finger = -1
		value = Vector2.ZERO
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


func _draw() -> void:
	draw_circle(_origin, Constants.STICK_RADIUS, Color(1, 1, 1, 0.16))
	draw_arc(_origin, Constants.STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
	var knob := _origin + value * Constants.STICK_RADIUS
	draw_circle(knob, 26.0, Color(1, 0.85, 0.45, 0.9) if value.length() >= Constants.RUN_ON else Color(1, 1, 1, 0.85))
