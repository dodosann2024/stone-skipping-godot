class_name Joystick
extends Control
## Floating virtual joystick: touch anywhere inside this control, drag to move.
## value: Vector2 in the unit disc (x right, y down). Light push walks, full push runs.

var value := Vector2.ZERO
var radius := 70.0
var active := false
var touch_id := -2
var center := Vector2.ZERO
var knob := Vector2.ZERO
var rest := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _rest_pos() -> Vector2:
	return Vector2(radius + 34.0, size.y - radius - 34.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and touch_id == -2:
			touch_id = e.index
			_begin(e.position)
		elif not e.pressed and e.index == touch_id:
			_end()
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_id:
			_drag(d.position)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed and touch_id == -2:
				touch_id = -1
				_begin(m.position)
			elif not m.pressed and touch_id == -1:
				_end()
			accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and touch_id == -1:
		_drag((event as InputEventMouseMotion).position)
		accept_event()

func _begin(p: Vector2) -> void:
	active = true
	# the base jumps under the finger (but stays fully on screen)
	center = Vector2(clampf(p.x, radius + 8.0, size.x - radius - 8.0), clampf(p.y, radius + 8.0, size.y - radius - 8.0))
	_drag(p)

func _drag(p: Vector2) -> void:
	var d := p - center
	if d.length() > radius:
		# drag the base along when the finger runs past the rim
		center += d - d.normalized() * radius
		d = p - center
	knob = d
	value = d / radius
	if value.length() < 0.12:
		value = Vector2.ZERO
	queue_redraw()

func _end() -> void:
	active = false
	touch_id = -2
	value = Vector2.ZERO
	knob = Vector2.ZERO
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var c := center if active else _rest_pos()
	var a := 0.85 if active else 0.45
	draw_circle(c, radius, Color(0.02, 0.15, 0.25, 0.28 * a))
	draw_arc(c, radius, 0, TAU, 48, Color(1, 1, 1, 0.75 * a), 4.0, true)
	draw_arc(c, radius * 0.88, 0, TAU, 48, Color(1, 0.85, 0.3, 0.35 * a), 2.0, true)
	draw_circle(c + knob, radius * 0.42, Color(1, 1, 1, 0.8 * a))
	draw_arc(c + knob, radius * 0.42, 0, TAU, 32, Color(0.05, 0.35, 0.55, 0.8 * a), 3.0, true)
