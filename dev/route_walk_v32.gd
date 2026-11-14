extends SceneTree
## Headless island route: walk + run a loop covering dock, beach, path climb, campfire.
## Pass = no XZ snaps, no float/sink beyond 2 cm, smooth per-frame motion.
##   godot --headless --path . --fixed-fps 60 -s res://dev/route_walk_v32.gd

const MAX_GND_ERR := 0.02          # m — float/sink budget
const MAX_STEP_XZ := 0.12          # m per render frame at 60 Hz (~run*2 + slack)
const MAX_STEP_Y := 0.08           # m per render frame (no Y teleport)
const MIN_MOVE := 8.0              # m total travel required
const SMOOTH_RATIO := 2.6          # max/median frame Δxz while moving (walk↔run ramp)

var m: Node
var fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("ROUTE FAIL  ", msg)


func _go() -> void:
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	m.cam_fixed = false
	# Settle on spawn.
	for _i in 30:
		await process_frame

	var waypoints: Array[Vector3] = [
		m.player.position,
		m.island.player_spot + Vector3(0, 0, -4.0),   # down the dock
		Vector3(4.0, 0, 6.0),                          # beach / path
		Vector3(-2.0, 0, 8.0),                         # climb
		m.island.campfire_pos + Vector3(2.5, 0, 2.5),  # campfire pad skirt
		Vector3(6.0, 0, -4.0),                         # far beach
		m.island.player_spot + Vector3(0, 0, -1.0),    # back near dock
	]

	var steps_xz: Array[float] = []
	var max_gnd := 0.0
	var max_step_xz := 0.0
	var max_step_y := 0.0
	var travel := 0.0
	var prev: Vector3 = m.player.position
	var samples := 0

	for wi in range(1, waypoints.size()):
		var target: Vector3 = waypoints[wi]
		var running := (wi % 2 == 0)  # alternate walk / run legs
		var deadline := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < deadline:
			var p: Vector3 = m.player.position
			var to := Vector2(target.x - p.x, target.z - p.z)
			if to.length() < 0.55:
				break
			var dir: Vector2 = to.normalized()
			# Camera-relative stick: joy x = right, y = forward (−screen).
			var fwd := Vector2(-sin(m.ex_yaw), -cos(m.ex_yaw))
			var right := Vector2(cos(m.ex_yaw), -sin(m.ex_yaw))
			var local := Vector2(dir.dot(right), dir.dot(fwd))
			var mag := 1.0 if running else 0.72
			if m.joy:
				m.joy.value = local.normalized() * mag
			await process_frame
			var cur: Vector3 = m.player.position
			var dxz: float = Vector2(cur.x - prev.x, cur.z - prev.z).length()
			var dy: float = absf(cur.y - prev.y)
			travel += dxz
			max_step_xz = maxf(max_step_xz, dxz)
			max_step_y = maxf(max_step_y, dy)
			if dxz > 0.004:
				steps_xz.append(dxz)
			# Ground error vs walkable `_surface` (includes soft dock-lip ramp).
			var err: float = absf(cur.y - m._surface(cur.x, cur.z))
			max_gnd = maxf(max_gnd, err)
			if dxz > MAX_STEP_XZ:
				_fail("xz snap %.3f m at (%.2f,%.2f) leg %d" % [dxz, cur.x, cur.z, wi])
			if dy > MAX_STEP_Y:
				_fail("y snap %.3f m at (%.2f,%.2f) leg %d" % [dy, cur.x, cur.z, wi])
			prev = cur
			samples += 1
		if m.joy:
			m.joy.value = Vector2.ZERO
		# Brief settle between legs.
		for _j in 12:
			await process_frame
			prev = m.player.position

	# Smoothness: while moving, max/median of frame Δxz.
	var median := 0.0
	var ratio := 0.0
	if steps_xz.size() >= 8:
		steps_xz.sort()
		median = steps_xz[steps_xz.size() >> 1]
		ratio = max_step_xz / maxf(median, 1e-4)

	print("ROUTE travel=%.2f m samples=%d max_gnd=%.4f max_xz=%.4f max_y=%.4f med_xz=%.4f ratio=%.2f" % [
		travel, samples, max_gnd, max_step_xz, max_step_y, median, ratio])

	if travel < MIN_MOVE:
		_fail("travel too short %.2f m (need %.1f)" % [travel, MIN_MOVE])
	if max_gnd > MAX_GND_ERR:
		_fail("ground err %.4f m > %.3f" % [max_gnd, MAX_GND_ERR])
	if max_step_xz > MAX_STEP_XZ:
		_fail("max xz step %.4f > %.3f" % [max_step_xz, MAX_STEP_XZ])
	if max_step_y > MAX_STEP_Y:
		_fail("max y step %.4f > %.3f" % [max_step_y, MAX_STEP_Y])
	if median > 0.0 and ratio > SMOOTH_RATIO:
		_fail("motion not smooth max/med=%.2f > %.1f" % [ratio, SMOOTH_RATIO])

	if fails.is_empty():
		print("ROUTE PASS")
		quit(0)
	else:
		print("ROUTE FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)
