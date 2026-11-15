extends SceneTree
## Assert contact blob stays under rendered stance soles during CDP-style drag.
## Every frame: |blob_xz − stance_sole_mid_xz| < 3 cm, and skinned sole vs
## collision under that point within [-1.0, +1.5] cm (same post-IK frame).
##   godot --path . --headless --fixed-fps 60 -s res://dev/blob_sole_v36.gd

const MAX_BLOB_XZ := 0.030
const MAX_SINK := 0.010
const MAX_FLOAT := 0.015

var m: Node
var fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("BLOB FAIL  ", msg)


func _check(tag: String) -> void:
	m.boy._reassert_foot_plants()
	m.boy._update_blob()
	var late = m.boy.get_node_or_null("FootPlantLate")
	if late and late.has_method("_record_blob"):
		late._record_blob(m.boy)
	var mids: Array = m.boy.stance_sole_midpoints()
	if mids.is_empty():
		_fail("%s no stance sole" % tag)
		return
	# Contact marker = visible per-foot disc under each stance sole (same frame).
	# Discs are hidden while locomoting (sun shadow only) — then blob_d is N/A.
	m.boy._update_blob()
	var any_disc := false
	# Each visible disc must sit under nearest stance sole (< 3 cm).
	for dnode in [m.boy.blob_l, m.boy.blob_r]:
		if dnode == null or not dnode.visible:
			continue
		any_disc = true
		var bp: Vector3 = dnode.global_position
		var best := 1e9
		for mid_v in mids:
			var mid: Vector3 = mid_v
			best = minf(best, Vector2(bp.x, bp.z).distance_to(Vector2(mid.x, mid.z)))
		if best > MAX_BLOB_XZ:
			_fail("%s disc↔sole %.1fcm at (%.2f,%.2f)" % [tag, best * 100.0, bp.x, bp.z])
	# While dragging/moving, discs must stay hidden (no lagging oval).
	var moving: bool = m.boy.anim == "move" and m.boy.move_w > 0.25 and m.boy.move_speed > 0.35
	if moving and any_disc:
		_fail("%s disc visible while locomoting" % tag)
	# Rendered sole height at this same frame (skinned bone soles post-IK).
	var ex: Array = [m.boy.get_rid()]
	for side in range(2):
		if not m.boy._stance_locked[side] and m.boy.anim == "move" and m.boy.move_w > 0.2:
			continue
		var fp: Array = m.boy.foot_points(side)
		var heel: Vector3 = fp[0]
		var ball: Vector3 = fp[1]
		var sy_h: float = m.island.collision_h(heel.x, heel.z, m.player.position.y, ex)
		var sy_b: float = m.island.collision_h(ball.x, ball.z, m.player.position.y, ex)
		var gap_h: float = (heel.y - m.boy.sole_offset) - sy_h
		var gap_b: float = (ball.y - 0.012) - sy_b
		if gap_h < -MAX_SINK or gap_h > MAX_FLOAT:
			_fail("%s heel[%d] gap %.1fcm" % [tag, side, gap_h * 100.0])
		if gap_b < -MAX_SINK or gap_b > MAX_FLOAT:
			_fail("%s ball[%d] gap %.1fcm" % [tag, side, gap_b * 100.0])


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(780, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	for _i in 50:
		await process_frame
	m.demo_mode = false
	m.cam_fixed = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 30:
		await process_frame
	var ds: float = m.island.dock_start_z
	# Slope start (CDP burial spot).
	var y: float = m._surface(2.6, ds + 6.5)
	m.player.position = Vector3(2.6, y, ds + 6.5)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = -0.4
	m.player.rotation.y = -0.4
	m.boy.rotation.y = -0.4
	for _i in 12:
		await process_frame
	print("BLOB CDP slope drag")
	if m.joy:
		m.joy.value = Vector2(0.35, -0.85)
	for i in 120:
		await process_frame
		_check("drag_f%d" % i)
		if fails.size() > 40:
			break
	if m.joy:
		m.joy.value = Vector2.ZERO
	for i in 30:
		await process_frame
		_check("idle_f%d" % i)
	print("BLOB fails=%d" % fails.size())
	if fails.is_empty():
		print("BLOB_SOLE PASS")
		quit(0)
	else:
		print("BLOB_SOLE FAILED")
		for f in fails:
			print("  - ", f)
		quit(1)
