extends SceneTree
## Headless island route: long walk+run covering dock, beach, and grass slopes.
## Pass = ≥70 m travel, no XZ snaps, no float/sink beyond 2 cm, smooth motion.
##   godot --headless --path . --fixed-fps 60 -s res://dev/route_walk_v32.gd

const MAX_GND_ERR := 0.02
const MAX_STEP_XZ := 0.12
const MAX_STEP_Y := 0.10
const MIN_MOVE := 70.0
const SMOOTH_RATIO := 2.8

var m: Node
var fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("ROUTE FAIL  ", msg)


func _drive(stick: Vector2, frames: int, steps_xz: Array, stats: Dictionary) -> void:
	if m.joy:
		m.joy.value = stick
	var prev: Vector3 = m.player.position
	for _i in frames:
		await process_frame
		var cur: Vector3 = m.player.position
		var dxz: float = Vector2(cur.x - prev.x, cur.z - prev.z).length()
		var dy: float = absf(cur.y - prev.y)
		stats["travel"] = float(stats["travel"]) + dxz
		stats["max_xz"] = maxf(float(stats["max_xz"]), dxz)
		stats["max_y"] = maxf(float(stats["max_y"]), dy)
		stats["samples"] = int(stats["samples"]) + 1
		if dxz > 0.004:
			steps_xz.append(dxz)
		var err: float = absf(cur.y - m._surface(cur.x, cur.z))
		stats["max_gnd"] = maxf(float(stats["max_gnd"]), err)
		if dxz > MAX_STEP_XZ:
			_fail("xz snap %.3f m at (%.2f,%.2f)" % [dxz, cur.x, cur.z])
		if dy > MAX_STEP_Y:
			_fail("y snap %.3f m at (%.2f,%.2f)" % [dy, cur.x, cur.z])
		prev = cur
	if m.joy:
		m.joy.value = Vector2.ZERO


func _place(xz: Vector2, yaw: float) -> void:
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = yaw
	m.player.rotation.y = yaw


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
	for _i in 30:
		await process_frame

	var ds: float = m.island.dock_start_z
	var de: float = m.island.dock_end_z
	var steps_xz: Array[float] = []
	var stats := {"travel": 0.0, "max_xz": 0.0, "max_y": 0.0, "max_gnd": 0.0, "samples": 0}

	# Segmented open-path drives (no seek-into-wall). Covers dock, sand, slopes.
	# Each segment: [xz, yaw, stick, frames]. Stick Y=-1 is full run forward.
	# ~4500 frames × ~1.6 m/s ≈ 70 m+ across dock / sand / slopes.
	var segments: Array = [
		[Vector2(0.2, de + 1.8), 0.0, Vector2(0.0, -1.0), 200],
		[Vector2(0.0, lerpf(ds, de, 0.45)), PI, Vector2(0.0, -1.0), 220],
		[Vector2(1.4, ds + 3.5), -0.3, Vector2(0.2, -1.0), 240],
		[Vector2(2.8, ds + 5.5), -0.5, Vector2(0.25, -1.0), 260],
		[Vector2(3.5, ds + 6.5), -0.6, Vector2(0.15, -1.0), 280],
		[Vector2(4.0, ds + 5.2), 0.9, Vector2(0.1, -1.0), 240],
		[Vector2(-2.8, ds + 5.8), 0.5, Vector2(-0.15, -1.0), 280],
		[Vector2(-3.0, ds + 4.0), -0.2, Vector2(0.1, -1.0), 240],
		[Vector2(0.5, ds + 3.0), 0.1, Vector2(0.0, -1.0), 240],
		[Vector2(3.0, ds + 6.0), -0.5, Vector2(0.2, -1.0), 300],
		[Vector2(-2.5, ds + 6.2), 0.6, Vector2(-0.2, -1.0), 300],
		[Vector2(1.0, ds + 4.0), 0.0, Vector2(0.1, -1.0), 280],
		[Vector2(0.2, de + 2.2), 0.0, Vector2(0.0, -1.0), 200],
		[Vector2(2.5, ds + 5.0), -0.4, Vector2(0.2, -1.0), 260],
		[Vector2(-2.0, ds + 5.5), 0.4, Vector2(-0.15, -1.0), 260],
	]

	for seg in segments:
		var xz: Vector2 = seg[0]
		var yaw: float = float(seg[1])
		var stick: Vector2 = seg[2]
		var frames: int = int(seg[3])
		_place(xz, yaw)
		for _j in 8:
			await process_frame
		# Face stick relative to current ex_yaw: convert world-ish stick to camera-relative
		# by temporarily aligning ex_yaw with face so stick Y = forward.
		m.ex_yaw = m.face_yaw + PI
		await _drive(stick, frames, steps_xz, stats)
		for _j in 6:
			await process_frame

	var median := 0.0
	var ratio := 0.0
	if steps_xz.size() >= 8:
		steps_xz.sort()
		median = steps_xz[steps_xz.size() >> 1]
		ratio = float(stats["max_xz"]) / maxf(median, 1e-4)

	print("ROUTE travel=%.2f m samples=%d max_gnd=%.4f max_xz=%.4f max_y=%.4f med_xz=%.4f ratio=%.2f" % [
		float(stats["travel"]), int(stats["samples"]), float(stats["max_gnd"]),
		float(stats["max_xz"]), float(stats["max_y"]), median, ratio])

	if float(stats["travel"]) < MIN_MOVE:
		_fail("travel too short %.2f m (need %.1f)" % [float(stats["travel"]), MIN_MOVE])
	if float(stats["max_gnd"]) > MAX_GND_ERR:
		_fail("ground err %.4f m > %.3f" % [float(stats["max_gnd"]), MAX_GND_ERR])
	if float(stats["max_xz"]) > MAX_STEP_XZ:
		_fail("max xz step %.4f > %.3f" % [float(stats["max_xz"]), MAX_STEP_XZ])
	if float(stats["max_y"]) > MAX_STEP_Y:
		_fail("max y step %.4f > %.3f" % [float(stats["max_y"]), MAX_STEP_Y])
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
