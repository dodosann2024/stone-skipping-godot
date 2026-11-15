class_name InputJoystick
extends Joystick
## Move intent. Stick value plus keyboard. Nothing else reads the pointer for walking.

var keys_run := false


func read_move(demo_mode: bool, demo_input: Vector2) -> Vector2:
	if demo_mode:
		keys_run = false
		return demo_input
	var v := value
	var k := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"))
	if Input.is_physical_key_pressed(KEY_A):
		k.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		k.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		k.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		k.y += 1.0
	keys_run = Input.is_physical_key_pressed(KEY_SHIFT)
	if k.length() > 0.1:
		v = k.normalized() * (1.0 if keys_run else 0.7)
	return v.limit_length(1.0)
