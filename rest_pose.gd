extends RefCounted
## Sit, lie and hammock rest. Same behaviour as main.gd.

var m

func bind(host) -> void:
	m = host

func _ensure_rest_align() -> void:
	if not m.rest_align.is_empty():
		return
	var path = "res://props/alignment.json"
	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return
	var f = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		m.rest_align = parsed

func _begin_rest(kind: String) -> void:
	m._begin_cam_blend()
	m.mode = m.Mode.REST
	m.rest_kind = kind
	m.rest_phase = 0
	m.rest_t = 0.0
	m.rest_cam_yaw = INF
	m.rest_cam_pitch = 0.2
	m.rest_cam_dist = 2.8
	m.rest_cam_ease = 0.0
	m.rest_exit_cam_t = 0.0
	m.rest_touch_dragged = false
	m.move_vel = Vector3.ZERO
	m.rest_use_clips = false
	m.rest_clip_phase = ""
	m.rest_clip_prop = ""
	m.set_meta("lie_snapped", false)
	m.set_meta("lie_mesh_nudged", false)
	m.set_meta("fix_rest_locked", false)
	_ensure_rest_align()
	# Prefer authored Blender clips for bench / log / hammock.
	if kind == "sleep" and m.boy.ap and m.boy.ap.has_animation("hammock_enter"):
		m.rest_use_clips = true
		m.rest_clip_prop = "hammock"
		_setup_hammock_clip_rest()
	elif kind == "seat" and m.seat_i >= 0 and m.seat_i < m.island.seats.size():
		var st0: Dictionary = m.island.seats[m.seat_i]
		var nm = String(st0.get("name", ""))
		if nm == "长椅" and m.boy.ap and m.boy.ap.has_animation("bench_sit_enter"):
			m.rest_use_clips = true
			m.rest_clip_prop = "bench"
			_setup_seat_clip_rest(st0)
		elif nm == "坐木" and m.boy.ap and m.boy.ap.has_animation("log_sit_enter"):
			m.rest_use_clips = true
			m.rest_clip_prop = "log"
			_setup_seat_clip_rest(st0)
	if m.rest_use_clips:
		m.boy.end_activity()
		m.boy.set_hat_mode("head")
		if kind == "sleep":
			m.island.set_hammock_clip_frame("empty", 0)
		m.player_ctrl.write_yaw(m.face_yaw)
		m._update_ui()
		return
	# Legacy procedural path (lounger / missing clips).
	if kind == "sleep":
		_setup_hammock_rest()
	elif kind == "seat":
		var st: Dictionary = m.island.seats[m.seat_i]
		var face: Vector3 = m.seat_face.normalized()
		m.seat_lying = false
		m.rest_side = face.cross(Vector3.UP).normalized()
		m.rest_sit_b = Basis(Vector3.UP, atan2(-face.x, -face.z))
		m.rest_approach = m.seat_ap
		var pl0 = m.boy.activity("seat", 1.0, 0.0, 0.0)
		var top: Vector3 = st["top"]
		m.rest_seat = top + Vector3(0, pl0.y - Island.SEAT_TOP, 0)
		m.rest_lie = top + Vector3(0, m.LIE_BACK, 0) - m.rest_side * 0.1
		m.rest_lie_b = _lie_basis(m.rest_side)
	else:
		_setup_lounger_rest()
	m.rest_approach.y = m._surface(m.rest_approach.x, m.rest_approach.z)
	var pl = m.boy.activity(kind, 1.0, 0.0, 0.0)
	m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
	if kind == "seat" or kind == "sleep":
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		for _s in 12:
			_snap_sit_contact()
			pl = m.boy.activity(kind, 1.0, 0.0, 0.0)
			m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
	m.boy.end_activity()
	if kind == "sleep":
		m.island.set_hammock_load([] as Array[Vector3])
	m.player_ctrl.write_yaw(m.face_yaw)
	m._update_ui()

func _setup_seat_clip_rest(st: Dictionary) -> void:
	m.seat_lying = false
	var face: Vector3 = m.seat_face.normalized()
	m.rest_side = face.cross(Vector3.UP).normalized()
	m.rest_prop_xf = st.get("prop_xf", Transform3D.IDENTITY)
	if m.rest_prop_xf == Transform3D.IDENTITY:
		m.rest_prop_xf = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z) + PI),
			Vector3(st["top"].x, m._surface(st["top"].x, st["top"].z), st["top"].z))
	m.rest_approach = st["approach"]
	m.rest_approach.y = m._surface(m.rest_approach.x, m.rest_approach.z)
	m.rest_seat = st["top"]
	m.rest_sit_b = m.rest_prop_xf.basis
	# Clip enter starts at root_pos (0,0,-0.5) yaw 0 in prop frame (exact prop Y).
	var clip_key = "bench_sit_enter" if m.rest_clip_prop == "bench" else "log_sit_enter"
	var cinfo: Dictionary = m.rest_align.get("clips", {}).get(clip_key, {})
	var rp: Array = cinfo.get("root_pos_prop", [0, 0, -0.5])
	var local = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	m.rest_root_sit = m.rest_prop_xf * local
	m.rest_approach = m.rest_prop_xf * Vector3(0.0, 0.0, -0.50)
	m.rest_approach.y = m.rest_prop_xf.origin.y

func _setup_hammock_clip_rest() -> void:
	m.rest_prop_xf = m.island.hammock_node.global_transform if m.island.hammock_node else Transform3D.IDENTITY
	hammock_prop_side()
	var cinfo: Dictionary = m.rest_align.get("clips", {}).get("hammock_enter", {})
	var rp: Array = cinfo.get("root_pos_prop", [0, -0.96, 0.63])
	var local = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	m.rest_root_sit = m.rest_prop_xf * local
	# Approach = start of enter (inland side).
	m.rest_approach = m.rest_root_sit
	m.rest_approach.y = m._surface(m.rest_approach.x, m.rest_approach.z)
	m.rest_seat = m.rest_prop_xf * Vector3(0, 0, 0)
	m.rest_sit_b = m.rest_prop_xf.basis
	m.rest_side = (m.rest_prop_xf.basis * Vector3(0, 0, 1)).normalized()

func hammock_prop_side() -> void:
	if m.island.hammock_node:
		m.rest_side = m.island.hammock_node.global_transform.basis.z.normalized()

func _setup_hammock_rest() -> void:
	var hs = m._hammock_spot()
	var along: Vector3 = hs[1]
	var side: Vector3 = hs[2]
	m.rest_side = side
	var bed: Vector3 = m.island.hammock_point(0.5)
	# Head on the upper end, hips mid-pocket — body along the hammock centreline.
	var head_t = 0.72
	var hip_t = 0.48
	var foot_t = 0.24
	var hip_f: Dictionary = m.island.hammock_frame(hip_t)
	var head_f: Dictionary = m.island.hammock_frame(head_t)
	var foot_f: Dictionary = m.island.hammock_frame(foot_t)
	var head_dir: Vector3 = ((head_f["pos"] as Vector3) - (hip_f["pos"] as Vector3))
	if head_dir.length_squared() < 1e-6:
		head_dir = along
	else:
		head_dir = head_dir.normalized()
	if head_dir.dot(along) < 0.0:
		var tmp = head_t
		head_t = foot_t
		foot_t = tmp
		head_f = m.island.hammock_frame(head_t)
		foot_f = m.island.hammock_frame(foot_t)
		head_dir = ((head_f["pos"] as Vector3) - (hip_f["pos"] as Vector3)).normalized()
	# Keep the spine on the centreline (no diagonal twist into the rails).
	var into: Vector3 = (-Vector3.UP).lerp(-(hip_f["normal"] as Vector3).normalized(), 0.25).normalized()
	m.rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Nest ~8 cm into the dish so fabric sides rise above the torso without burying him.
	var hip_pos: Vector3 = hip_f["pos"] as Vector3
	m.rest_lie = hip_pos - (hip_f["normal"] as Vector3) * 0.08
	# Sit facing OUT toward the approach so thighs hang over the near edge to the ground.
	m.rest_sit_b = Basis(Vector3.UP, atan2(-side.x, -side.z))
	var sit_frame: Dictionary = m.island.hammock_frame(0.50)
	var sit_n: Vector3 = (sit_frame["normal"] as Vector3).normalized()
	var sit_side: Vector3 = (sit_frame["side"] as Vector3).normalized()
	if sit_side.dot(side) < 0.0:
		sit_side = -sit_side
	m.rest_seat = (sit_frame["pos"] as Vector3) + sit_side * (m.island.hammock_half_w * 0.90) + sit_n * 0.08
	# Stand on sand beside the hammock, ≥0.6 m from any palm trunk.
	m.rest_approach = _hammock_stand_clear(bed, side)
	m.boy.hat_beside_world = Vector3.ZERO
	m.set_meta("lie_head_t", head_t)
	m.set_meta("lie_hip_t", hip_t)
	m.set_meta("lie_foot_t", foot_t)
	m.set_meta("lie_foot_pos", foot_f["pos"])


## Pick a stand pose beside the hammock that clears palm trunks by ≥ min_clear metres.

func _hammock_stand_clear(bed: Vector3, side: Vector3, min_clear = 0.6) -> Vector3:
	var candidates: Array[Vector3] = []
	for sgn in [1.0, -1.0]:
		for dist in [0.95, 1.15, 1.40, 1.70]:
			var p: Vector3 = bed + side * sgn * (m.island.hammock_half_w + dist)
			p.y = m._surface(p.x, p.z)
			candidates.append(p)
	var best = candidates[0]
	var best_d = -1.0
	for p in candidates:
		var d = _nearest_trunk_dist(p)
		if d >= min_clear and d > best_d:
			best_d = d
			best = p
	if best_d < min_clear:
		# Nudge the better side away until clear.
		best = candidates[0]
		for _i in 16:
			var d2 = _nearest_trunk_dist(best)
			if d2 >= min_clear:
				break
			var away = _nearest_trunk_away(best)
			best += away * (min_clear - d2 + 0.08)
			best.y = m._surface(best.x, best.z)
		m.rest_side = (best - bed).normalized()
		m.rest_side.y = 0.0
		if m.rest_side.length_squared() < 1e-6:
			m.rest_side = side
		else:
			m.rest_side = m.rest_side.normalized()
	return best

func _nearest_trunk_dist(p: Vector3) -> float:
	var best = 1e9
	for tr in m.island.trunks:
		if tr.is_empty():
			continue
		var base: Vector3 = tr[0]
		best = minf(best, Vector2(p.x - base.x, p.z - base.z).length())
	return best

func _nearest_trunk_away(p: Vector3) -> Vector3:
	var best = 1e9
	var away = Vector3.RIGHT
	for tr in m.island.trunks:
		if tr.is_empty():
			continue
		var base: Vector3 = tr[0]
		var d = Vector2(p.x - base.x, p.z - base.z).length()
		if d < best:
			best = d
			away = Vector3(p.x - base.x, 0.0, p.z - base.z)
	if away.length_squared() < 1e-6:
		return m.rest_side if m.rest_side.length_squared() > 1e-6 else Vector3.RIGHT
	return away.normalized()


## Sunbathing on the chaise: hips in the seat–back crease, spine+head on the ~45° pad,
## heels on the seat cushion. Hat is off (on chest / sand). Snap by skinned mesh only.

func _setup_lounger_rest() -> void:
	# Real chaise: hips on the seat just forward of the crease (butt on cushion, not in the hinge
	# corner), spine along the ~45° pad, head on the pad.
	# Hips just forward of the crease so thighs rest on the seat top (not in the hinge).
	var seat_hip_u = 0.82
	var hip_s = 0.42
	var head_s = 0.82
	var foot_s = 0.10
	var seat_h: Dictionary = m.island.lounger_seat_point(seat_hip_u)
	# Head mid-pad so the skull rests on cushion (reachable, not past the top rail).
	var back_h: Dictionary = m.island.lounger_back_point(0.62)
	var back_mid: Dictionary = m.island.lounger_back_point(0.42)
	var seat_along: Vector3 = (seat_h["along"] as Vector3).normalized()
	var seat_n: Vector3 = (seat_h["normal"] as Vector3).normalized()
	var back_n: Vector3 = (back_mid["normal"] as Vector3).normalized()
	# Head axis = up the backrest pad from the crease (must point toward the head end).
	var to_head: Vector3 = (back_h["pos"] as Vector3) - (seat_h["pos"] as Vector3)
	var head_dir: Vector3 = (back_h["along"] as Vector3).normalized()
	if head_dir.dot(to_head) < 0.0:
		head_dir = -head_dir
	# Prefer the pad along, but keep a little of the crease→head chord so hips stay near the hinge.
	if to_head.length_squared() > 1e-6:
		head_dir = head_dir.lerp(to_head.normalized(), 0.25).normalized()
	var side: Vector3 = seat_along.cross(Vector3.UP).normalized()
	if side.length_squared() < 1e-6:
		side = m.island.lounger_xf.basis.x.normalized()
	m.rest_side = side
	var st_i = -1
	for i in m.island.seats.size():
		if m.island.seats[i]["name"] == "躺椅":
			st_i = i
			break
	if st_i >= 0:
		m.rest_approach = m.island.seats[st_i]["approach"]
		m.rest_seat = m.island.seats[st_i]["top"] + Vector3(0, 0.05, 0)
	else:
		m.rest_seat = (seat_h["pos"] as Vector3) + side * 0.35
		m.rest_approach = m.rest_seat + side * 0.4
	m.rest_sit_b = Basis(Vector3.UP, atan2(-side.x, -side.z))
	# Into: follow the backrest so the torso lies ON the pad (not hunched forward).
	var into: Vector3 = (-back_n * 0.90 - seat_n * 0.10).normalized()
	m.rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Guard: face (= −into after basis) must look skyward.
	if (-m.rest_lie_b.z).dot(Vector3.UP) < 0.50:
		into = (-back_n * 0.96 - seat_n * 0.04).normalized()
		m.rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Start ~14 cm above foam; snap settles the back onto the pad.
	var hip_target: Vector3 = (seat_h["pos"] as Vector3) + seat_n * 0.14
	hip_target += back_n * 0.025
	m.rest_lie = hip_target
	m.set_meta("lie_head_s", head_s)
	m.set_meta("lie_foot_s", foot_s)
	m.set_meta("lie_hip_s", hip_s)
	m.set_meta("lie_seat_hip_u", seat_hip_u)
	m.set_meta("lie_foot_plane_u", 0.12)
	m.set_meta("lie_back_n", back_n)
	m.set_meta("lie_head_target", (back_h["pos"] as Vector3) + back_n * 0.04)
	# Sand beside the chaise — clearly off the body, flat on the ground (no float).
	var sand_hat: Vector3 = (m.island.lounger_xf.origin) + side * 1.25 + seat_along * 0.15
	sand_hat.y = Island.ground_h(sand_hat.x, sand_hat.z) + 0.015
	m.set_meta("lie_hat_sand", sand_hat)
	m.boy.hat_beside_world = sand_hat

## sit -> lie back along the bench / log (the seated boy's「躺下」)

func _lie_down() -> void:
	if m.mode != m.Mode.REST or m.rest_kind != "seat" or m.rest_phase != 4 or m.seat_lying:
		return
	if not m.island.seats[m.seat_i]["can_lie"]:
		return
	m.seat_lying = true
	m.rest_phase = 3
	m.rest_t = 0.0
	m._update_ui()

func _act_kind() -> String:
	return "seatlie" if m.rest_kind == "seat" and m.seat_lying else m.rest_kind

## Lying on the back (supine): local +Y = head_dir, local +Z = into the bed.
## Tripo mesh faces model +Z; with model.rotation.y = PI that maps to boy −Z, so −Z (= −into)
## is the chest/face direction (sky / away from the pad).

func _lie_basis(head_dir: Vector3) -> Basis:
	return _lie_basis_oriented(head_dir, Vector3.DOWN)


## Build a supine basis from an explicit head axis and an into-the-support direction.

func _lie_basis_oriented(head_dir: Vector3, into_bed: Vector3) -> Basis:
	var y = head_dir.normalized()
	var z = into_bed - y * into_bed.dot(y)
	if z.length_squared() < 1e-8:
		z = Vector3.DOWN - y * Vector3.DOWN.dot(y)
	z = z.normalized()
	# Chest/face (= boy −Z) must have an upward component so selftest face_up passes.
	if (-z).dot(Vector3.UP) < 0.0:
		z = -z
	return Basis(y.cross(z), y, z)


## Direction from the body toward the support surface (boy +Z; chest is −Z).

func _lie_into_bed() -> Vector3:
	return m.rest_lie_b.z.normalized()


## Current hammock swing that maps rest-world → swung-world (identity when not sleeping).

func _lie_swing() -> Transform3D:
	if m.rest_kind == "sleep" and m.island.hammock_node:
		var mid = (m.island.hammock_a + m.island.hammock_b) * 0.5
		return m.island.hammock_node.global_transform * Transform3D(Basis.IDENTITY, -mid)
	return Transform3D.IDENTITY


## Raise/lower the sit root so butt + thigh mesh rests ON the seat top (sky-side positive).
## Uses skinned verts near the hips over the seat footprint — not the hip bone alone.
## Seat top Y comes from the prop entry (mesh AABB / authored surface), never a hardcoded offset alone.

func _snap_sit_contact() -> void:
	if m.seat_lying:
		return
	if m.rest_kind == "sleep":
		_snap_hammock_sit_contact()
		return
	if m.rest_kind != "seat" or m.seat_i < 0 or m.seat_i >= m.island.seats.size():
		return
	var st: Dictionary = m.island.seats[m.seat_i]
	var top: Vector3 = st["top"]
	var face: Vector3 = m.seat_face.normalized()
	# Iterate in-place so one call settles even when process is ticking.
	# Logs (坐木) need a wider contact cloud + more passes: short Tripo butt can
	# miss a tight hip sphere, leaving a 3–4 cm hover or a 2 cm dig from the back.
	var is_log = String(st.get("name", "")) == "坐木"
	var is_bench = String(st.get("name", "")) == "长椅"
	var passes = 12 if is_log else 10
	for _iter in passes:
		# Clear foot overrides before measuring — a prior soft-plant can stretch Tripo
		# shorts through the board and fool the deepest sample into a false dig/float.
		m.boy.clear_foot_plant()
		m.boy.activity("seat", 1.0, 0.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var samples: Array[Vector3] = m.boy.skinned_sample_world(1200)
		var depths: Array[float] = []
		var hip_r = 0.38 if is_log else 0.30
		var lat_max = 0.70 if is_log else 0.50
		for s in samples:
			# Contact cloud: underside of butt + proximal thighs over the board.
			if s.distance_to(hips) > hip_r:
				continue
			if (s - hips).dot(face) > 0.22:
				continue
			if s.y > hips.y + 0.02:
				continue
			# Ignore Tripo shorts spike verts that hang far below the hip — they dig
			# the metric while the visible sit surface still floats.
			if hips.y - s.y > 0.11:
				continue
			var lat: float = (s - top).dot(m.rest_side)
			var along: float = (s - top).dot(-face)
			# Stay over the plank (bench front half); logs allow a little behind.
			if absf(lat) > lat_max or along < (-0.22 if is_log else -0.05) or along > (0.50 if is_log else 0.28):
				continue
			depths.append(s.y - top.y)
		var deepest: float
		if depths.is_empty():
			# Tripo ischia hang ~10–12 cm below the hip bone at the visual sit shell.
			deepest = (hips.y - 0.11) - top.y
		else:
			depths.sort()
			# Low percentile — ignore a few remaining spikes.
			var idx = mini(maxi(int(depths.size() * 0.15), 0), depths.size() - 1)
			deepest = depths[idx]
		# Bench: slight float so Tripo shorts don't bury through the plank; log kisses closer.
		var target = 0.012 if is_bench else 0.003
		var err = target - deepest
		if absf(err) < 0.004:
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			break
		var step = clampf(err, -0.08, 0.08)
		m.rest_root_sit.y += step
		m.rest_seat.y += step
	m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
	# Gentle sole kiss / soft hang — never rubber-hose short Tripo shins through the board.
	if is_bench or is_log:
		var gnd = Vector3(m.rest_root_sit.x, m._surface(m.rest_root_sit.x, m.rest_root_sit.z), m.rest_root_sit.z)
		# Short Tripo shins hang above the sand — allow a longer soft pull toward ground.
		m.boy.plant_feet_soft(gnd, Vector3.UP, 0.02, 0.28)


## Settle butt onto the near-edge hammock fabric while seated (legs hang outside).

func _snap_hammock_sit_contact() -> void:
	if m.rest_kind != "sleep":
		return
	for _iter in 8:
		m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		_update_hammock_load()
		var sit_frame: Dictionary = m.island.hammock_frame(0.50)
		var n: Vector3 = (sit_frame["normal"] as Vector3).normalized()
		if n.y < 0.2:
			n = Vector3.UP
		var sit_side: Vector3 = (sit_frame["side"] as Vector3).normalized()
		if sit_side.dot(m.rest_side) < 0.0:
			sit_side = -sit_side
		# Contact target = near-edge lip (matches rest_seat), not cradle centre.
		var top: Vector3 = (sit_frame["pos"] as Vector3) + sit_side * (m.island.hammock_half_w * 0.92)
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var samples: Array[Vector3] = m.boy.skinned_sample_world(700)
		var deepest = 1e9
		var hit = false
		for s in samples:
			if s.distance_to(hips) > 0.28:
				continue
			if s.y > hips.y + 0.05:
				continue
			# Near-edge samples only (ignore hanging thighs outside the fabric).
			if (s - top).length() > 0.42:
				continue
			hit = true
			deepest = minf(deepest, (s - top).dot(n))
		if not hit:
			deepest = (hips - top).dot(n) - 0.10
		var target = 0.02
		var err = target - deepest
		if absf(err) < 0.004:
			_update_hammock_load()
			return
		var step = clampf(err, -0.05, 0.05)
		m.rest_root_sit += n * step
		m.rest_seat += n * step
	m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
	_update_hammock_load()


## After the lie pose is applied, nudge rest_lie so the skinned mesh sits on the support
## (no poke-through deeper than ~0, no large float). Includes baked hat verts.

func _snap_lie_contact() -> void:
	if m.rest_kind != "sun" and m.rest_kind != "sleep":
		return
	var into_bed: Vector3 = _lie_into_bed()
	# Skin shell toward the bed. Tiny hammock offset — large offsets made the snap
	# "settle" while the visible hip bone still floated above the fabric.
	var mesh_off = 0.04 if m.rest_kind == "sleep" else 0.08
	var pts: Dictionary = m.boy.lie_contact_points(into_bed, mesh_off)
	var swing = _lie_swing()
	# Include baked hat verts for hammock fabric; lounger uses bone snap (hat tip ~kiss).
	var mesh_d = lie_mesh_penetration_depth(true)
	if m.rest_kind == "sleep":
		var hip_f: Dictionary = m.island.hammock_frame(float(m.get_meta("lie_hip_t", 0.48)))
		var head_f0: Dictionary = m.island.hammock_frame(float(m.get_meta("lie_head_t", 0.68)))
		var head_w: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		var hip_p: Vector3 = swing * (hip_f["pos"] as Vector3)
		var head_p0: Vector3 = swing * (head_f0["pos"] as Vector3)
		var hip_side: Vector3 = (swing.basis * (hip_f["side"] as Vector3)).normalized()
		var hn0: Vector3 = (swing.basis * (hip_f["normal"] as Vector3)).normalized()
		var head_n0: Vector3 = (swing.basis * (head_f0["normal"] as Vector3)).normalized()
		if hn0.y < 0.2:
			hn0 = Vector3.UP
		# Keep hips + head on the cradle centreline.
		var hip_lat0: float = (pts["hips"] - hip_p).dot(hip_side)
		var head_lat0: float = (head_w - head_p0).dot(hip_side)
		var corr: float = 0.6 * hip_lat0 + 0.4 * head_lat0
		if absf(corr) > 0.004:
			m.rest_lie -= hip_side * clampf(corr, -0.16, 0.16)
		# Vertical: lift for poke-through (hat brim included); settle light floats.
		var hip_gap = _signed_gap(pts["hips"], hip_p, hn0)
		var spine_gap = _signed_gap(pts["spine"], hip_p, hn0)
		var head_gap = _signed_gap(pts["head"], head_p0, head_n0)
		var sink_gap = minf(hip_gap, minf(spine_gap, head_gap))
		# Only settle down when hips AND spine are both floating — never push a
		# penetrating hip deeper just because the spine still floats a bit.
		var both_float = hip_gap > 0.012 and spine_gap > 0.012
		var float_gap = minf(hip_gap, spine_gap)
		# Nest ~10 cm into the dish so fabric sides rise above the torso.
		const NEST = -0.08
		if sink_gap < NEST - 0.06:
			m.rest_lie += hn0 * minf(-(sink_gap - NEST) * 0.45, 0.08)
		elif hip_gap > NEST + 0.025 or both_float:
			m.rest_lie -= hn0 * minf(hip_gap - NEST, 0.16)
		if head_gap < -0.02 and hip_gap < 0.05:
			m.rest_lie += head_n0 * minf(-head_gap, 0.04) * 0.35
		return
	# Lounger: foam sink OK; fail only on wood-board punch. Settle hips/head onto the pads.
	# Bone snap only — hat tip may kiss foam within 1 cm; over-lifting floats the torso.
	var seat_u: float = float(m.get_meta("lie_seat_hip_u", 0.96))
	var hip_s: Dictionary = m.island.lounger_seat_point(seat_u)
	var mid_b: Dictionary = m.island.lounger_back_point(0.38)
	var head_b: Dictionary = m.island.lounger_back_point(0.62)
	var back_n: Vector3 = (mid_b["normal"] as Vector3).normalized()
	var head_n: Vector3 = (head_b["normal"] as Vector3).normalized()
	var seat_n: Vector3 = (hip_s["normal"] as Vector3).normalized()
	var seat_along: Vector3 = (hip_s["along"] as Vector3).normalized()  # toward hinge
	# Bone gaps with a skin shell. Wide mesh probes at Spine2 falsely "kiss" via butt verts
	# at the crease while the torso floats ~12 cm in front of the pad (#45 hunch look).
	var spine1_w: Vector3 = m.boy.lie_bone_world("mixamorig_Spine1")
	var spine2_w: Vector3 = m.boy.lie_bone_world("mixamorig_Spine2")
	var head_w: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var hips_w: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	# Skin shell so bones settle onto the pad without burying Tripo flesh.
	const SKIN_BACK = 0.045
	const SKIN_HEAD = 0.055
	const SKIN_HIP = 0.08
	var g_s2 = minf(
		_signed_gap(spine1_w, mid_b["pos"], back_n) - SKIN_BACK,
		_signed_gap(spine2_w, mid_b["pos"], back_n) - SKIN_BACK)
	var g_head = _signed_gap(head_w, head_b["pos"], head_n) - SKIN_HEAD
	var g_hip = _signed_gap(hips_w, hip_s["pos"], seat_n) - SKIN_HIP
	var move = Vector3.ZERO
	# Pull the reclined torso onto the pad. -back_n sinks into the seat — compensate.
	if g_s2 > 0.012:
		var pull = minf(g_s2 - 0.006, 0.035)
		move -= back_n * pull
		move += seat_n * pull * 0.45
	elif g_s2 < -0.01:
		move += back_n * minf(-g_s2 - 0.002, 0.04)
	if g_head > 0.012:
		var hpull = minf(g_head - 0.006, 0.035)
		move -= head_n * hpull
		move += seat_n * hpull * 0.35
		move += seat_along * minf(hpull * 0.2, 0.01)
	elif g_head < -0.01:
		move += head_n * minf(-g_head - 0.002, 0.04)
	if g_hip > 0.015:
		move -= seat_n * minf(g_hip - 0.008, 0.022)
	elif g_hip < -0.01:
		move += seat_n * minf(-g_hip - 0.002, 0.03)
	# Cap hat/body dig at ~8 mm: tip may kiss foam, but approach-angle leftovers must clear.
	if mesh_d < -0.01 and move.dot(head_n) < 0.008:
		move += head_n * minf(-mesh_d - 0.005, 0.014)
	if move.length() > 0.05:
		move = move.normalized() * 0.05
	m.rest_lie += move

func _signed_gap(point: Vector3, surface: Vector3, normal: Vector3) -> float:
	# positive ⇒ point is on the outward (sky) side of the surface = floating
	return (point - surface).dot(normal.normalized())


## Gaps for selftest / debug: {hips, spine, head, foot_l, foot_r} in metres (sky-side positive).

func lie_contact_gaps() -> Dictionary:
	if m.rest_kind != "sun" and m.rest_kind != "sleep":
		return {}
	var into_bed: Vector3 = _lie_into_bed()
	# Shell ≈ Tripo skin thickness so gap≈0 when the mesh kisses the support.
	var shell = 0.28 if m.rest_kind == "sleep" else 0.08
	var pts: Dictionary = m.boy.lie_contact_points(into_bed, shell)
	var swing = _lie_swing()
	var out = {}
	if m.rest_kind == "sleep":
		var hip_f: Dictionary = m.island.hammock_frame(float(m.get_meta("lie_hip_t", 0.48)))
		var head_f: Dictionary = m.island.hammock_frame(float(m.get_meta("lie_head_t", 0.68)))
		var foot_f: Dictionary = m.island.hammock_frame(float(m.get_meta("lie_foot_t", 0.28)))
		var hip_p: Vector3 = swing * (hip_f["pos"] as Vector3)
		var hip_n: Vector3 = (swing.basis * (hip_f["normal"] as Vector3)).normalized()
		var head_p: Vector3 = swing * (head_f["pos"] as Vector3)
		var head_n: Vector3 = (swing.basis * (head_f["normal"] as Vector3)).normalized()
		var foot_p: Vector3 = swing * (foot_f["pos"] as Vector3)
		var foot_n: Vector3 = (swing.basis * (foot_f["normal"] as Vector3)).normalized()
		out["hips"] = _signed_gap(pts["hips"], hip_p, hip_n)
		out["spine"] = _signed_gap(pts["spine"], hip_p, hip_n)
		out["head"] = _signed_gap(pts["head"], head_p, head_n)
		out["foot_l"] = _signed_gap(pts["foot_l"], foot_p, foot_n)
		out["foot_r"] = _signed_gap(pts["foot_r"], foot_p, foot_n)
	else:
		var seat_u: float = float(m.get_meta("lie_seat_hip_u", 0.96))
		var hip_s: Dictionary = m.island.lounger_seat_point(seat_u)
		var foot_s: Dictionary = m.island.lounger_seat_point(float(m.get_meta("lie_foot_plane_u", 0.10)))
		var head_s: Dictionary = m.island.lounger_back_point(0.62)
		var mid_s: Dictionary = m.island.lounger_back_point(0.38)
		var back_n: Vector3 = (mid_s["normal"] as Vector3).normalized()
		var head_n: Vector3 = (head_s["normal"] as Vector3).normalized()
		var seat_n: Vector3 = (hip_s["normal"] as Vector3).normalized()
		# Mesh-near-bone gaps: contact ≤2 cm means the skin kisses the pad, not a bone capsule.
		# Bone + skin shell. Tight mesh probes only (r≤0.08) — wide probes read butt as spine.
		out["hips"] = _signed_gap(m.boy.lie_bone_world("mixamorig_Hips"), hip_s["pos"], seat_n) - 0.08
		out["spine"] = minf(
			_signed_gap(m.boy.lie_bone_world("mixamorig_Spine1"), mid_s["pos"], back_n) - 0.045,
			_signed_gap(m.boy.lie_bone_world("mixamorig_Spine2"), mid_s["pos"], back_n) - 0.045)
		out["head"] = _signed_gap(m.boy.lie_bone_world("mixamorig_Head"), head_s["pos"], head_n) - 0.055
		out["foot_l"] = _signed_gap(pts["foot_l"], foot_s["pos"], seat_n)
		out["foot_r"] = _signed_gap(pts["foot_r"], foot_s["pos"], seat_n)
	return out


## Closest skinned sample near a bone, signed along the support normal (sky-side positive).

func _mesh_gap_near(bone_pos: Vector3, surface: Vector3, normal: Vector3, radius: float) -> float:
	var samples: Array[Vector3] = m.boy.skinned_sample_world(500)
	normal = normal.normalized()
	var best = 1e9
	var hit = false
	for s in samples:
		if s.distance_to(bone_pos) > radius:
			continue
		hit = true
		best = minf(best, _signed_gap(s, surface, normal))
	if not hit:
		# Fallback: bone with a small shell.
		return _signed_gap(bone_pos - normal * 0.08, surface, normal)
	return best


## After a lounger hips-pitch, plant heels on the seat plane so they don't punch through.

func _plant_lie_feet() -> void:
	if m.rest_kind != "sun":
		return
	var foot_plane: Dictionary = m.island.lounger_seat_point(float(m.get_meta("lie_foot_plane_u", 0.05)))
	m.boy.lie_foot_plane_point = foot_plane["pos"]
	m.boy.lie_foot_plane_normal = foot_plane["normal"]
	m.boy.lie_foot_plant = true
	# Heels + knees above foam top; hips carry the thighs (no UpLeg override).
	m.boy.lie_foot_plant_gap = 0.015
	m.boy.plant_feet_on_plane(m.boy.lie_foot_plane_point, m.boy.lie_foot_plane_normal, m.boy.lie_foot_plant_gap, true)


## Deepest penetration of lie contact points into the support (negative = into the surface).
## Used by selftest: fail if any sample is deeper than 1 cm.

func lie_penetration_depth() -> float:
	var gaps: Dictionary = lie_contact_gaps()
	if gaps.is_empty():
		return 0.0
	var deepest = 0.0
	for k in gaps.keys():
		deepest = minf(deepest, float(gaps[k]))
	return deepest


## Skinned samples vs the rigid backrest BOARD under the foam. Foam kiss is OK.

func lie_backrest_penetration_depth() -> float:
	if m.rest_kind != "sun":
		return 1.0
	var samples: Array[Vector3] = m.boy.skinned_sample_world(280)
	if samples.is_empty():
		return 1.0
	var back: Dictionary = m.island.lounger_back_point(0.55)
	var back_n: Vector3 = (back["normal"] as Vector3).normalized()
	var foam_h: float = maxf(m.island.lounger_back_half.y * 2.0, 0.08)
	var board_pos: Vector3 = (back["pos"] as Vector3) - back_n * foam_h
	var foot_l: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
	var foot_r: Vector3 = m.boy.lie_bone_world("mixamorig_RightFoot")
	var thigh_l: Vector3 = m.boy.lie_bone_world("mixamorig_LeftUpLeg")
	var thigh_r: Vector3 = m.boy.lie_bone_world("mixamorig_RightUpLeg")
	var hips_p: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var torso: Array[Vector3] = [
		m.boy.lie_bone_world("mixamorig_Spine1"),
		m.boy.lie_bone_world("mixamorig_Spine2"),
		m.boy.lie_bone_world("mixamorig_Head"),
	]
	var deepest = 1e9
	var hit = false
	for s in samples:
		if not m.island.lounger_back_contains(s, 0.04):
			continue
		if s.distance_to(foot_l) < 0.25 or s.distance_to(foot_r) < 0.25:
			continue
		if s.distance_to(thigh_l) < 0.18 or s.distance_to(thigh_r) < 0.18:
			continue
		if s.distance_to(hips_p) < 0.20:
			continue
		var near_torso = false
		for tp in torso:
			if s.distance_to(tp) < 0.28:
				near_torso = true
				break
		if not near_torso:
			continue
		var g = _signed_gap(s, board_pos, back_n)
		if g < -0.25:
			continue
		hit = true
		deepest = minf(deepest, g)
	return deepest if hit else 0.02

func lounger_back_slab_clear() -> float:
	return m.island.lounger_back_half.y * 2.0 + 0.08


## Skinned samples vs the rigid seat BOARD under the foam cushion.
## 2–4 cm foam compress is expected; failing means punching through the wood.

func lie_seat_penetration_depth() -> float:
	if m.rest_kind != "sun":
		return 1.0
	var samples: Array[Vector3] = m.boy.skinned_sample_world(360)
	if samples.is_empty():
		return 1.0
	var seat: Dictionary = m.island.lounger_seat_point(0.5)
	var seat_n: Vector3 = (seat["normal"] as Vector3).normalized()
	var foam_h: float = maxf(m.island.lounger_seat_half.y * 2.0, 0.06)
	var board_pos: Vector3 = (seat["pos"] as Vector3) - seat_n * foam_h
	var deepest = 1e9
	var hit = false
	for s in samples:
		if not m.island.lounger_seat_contains(s, 0.05):
			continue
		if m.island.lounger_back_contains(s, 0.02):
			continue
		var g = _signed_gap(s, board_pos, seat_n)
		# Ignore wrap-around under the thin board.
		if g < -0.25:
			continue
		hit = true
		deepest = minf(deepest, g)
	return deepest if hit else 0.02


## Skinned body (+ baked hat crown/brim verts) vs the support surface.
## Returns the deepest signed gap (negative = into the furniture). Selftest fails below −1 cm.

func lie_mesh_penetration_depth(include_hat = true) -> float:
	if m.rest_kind != "sun" and m.rest_kind != "sleep":
		return 0.0
	var samples: Array[Vector3] = m.boy.skinned_sample_world(450)
	# Include hat samples when the brim is still on the head (chest mode clears fabric).
	if include_hat and m.boy.hat_mode == "head":
		samples.append_array(m.boy.hat_sample_world(140))
	if samples.is_empty():
		return 0.0
	var deepest = 1e9
	var hit = false
	var swing = _lie_swing()
	if m.rest_kind == "sleep":
		var along: Vector3 = (m.island.hammock_b - m.island.hammock_a).normalized()
		var mid: Vector3 = (m.island.hammock_a + m.island.hammock_b) * 0.5
		var ham_len = maxf(m.island.hammock_a.distance_to(m.island.hammock_b), 0.01)
		# Torso contact chain — ignore far limb tips that clip the gathered ends.
		var torso: Array[Vector3] = [
			m.boy.lie_bone_world("mixamorig_Hips"),
			m.boy.lie_bone_world("mixamorig_Spine1"),
			m.boy.lie_bone_world("mixamorig_Spine2"),
			m.boy.lie_bone_world("mixamorig_Head"),
		]
		for s in samples:
			var near_torso = false
			for tp in torso:
				if s.distance_to(tp) < 0.28:
					near_torso = true
					break
			if not near_torso:
				continue
			var t = clampf(0.5 + (s - mid).dot(along) / ham_len, 0.06, 0.94)
			var fr: Dictionary = m.island.hammock_frame(t)
			var fp: Vector3 = swing * (fr["pos"] as Vector3)
			var fn: Vector3 = (swing.basis * (fr["normal"] as Vector3)).normalized()
			var side: Vector3 = (swing.basis * (fr["side"] as Vector3)).normalized()
			if absf((s - fp).dot(side)) > 0.48:
				continue
			hit = true
			deepest = minf(deepest, _signed_gap(s, fp, fn))
	else:
		var seat: Dictionary = m.island.lounger_seat_point(0.5)
		var back: Dictionary = m.island.lounger_back_point(0.45)
		var seat_n: Vector3 = (seat["normal"] as Vector3).normalized()
		var back_n: Vector3 = (back["normal"] as Vector3).normalized()
		var seat_pos: Vector3 = seat["pos"] as Vector3
		var back_pos: Vector3 = back["pos"] as Vector3
		# Planted heels sit on the seat — don't let foot-skin verts keep the lift loop alive.
		var foot_l: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
		var foot_r: Vector3 = m.boy.lie_bone_world("mixamorig_RightFoot")
		var knee_l: Vector3 = m.boy.lie_bone_world("mixamorig_LeftLeg")
		var knee_r: Vector3 = m.boy.lie_bone_world("mixamorig_RightLeg")
		var thigh_l: Vector3 = m.boy.lie_bone_world("mixamorig_LeftUpLeg")
		var thigh_r: Vector3 = m.boy.lie_bone_world("mixamorig_RightUpLeg")
		# Upper-back / head skin only — hinge/hip/leg clips are seat-side geometry.
		var torso: Array[Vector3] = [
			m.boy.lie_bone_world("mixamorig_Spine2"),
			m.boy.lie_bone_world("mixamorig_Neck"),
			m.boy.lie_bone_world("mixamorig_Head"),
		]
		var hips_p: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		for s in samples:
			# Legs are owned by seat plant / thigh pose — don't let them drive pad penet.
			if s.distance_to(foot_l) < 0.25 or s.distance_to(foot_r) < 0.25:
				continue
			if s.distance_to(knee_l) < 0.18 or s.distance_to(knee_r) < 0.18:
				continue
			if s.distance_to(thigh_l) < 0.18 or s.distance_to(thigh_r) < 0.18:
				continue
			if s.distance_to(hips_p) < 0.22:
				continue
			if m.island.lounger_back_contains(s, 0.04):
				var near_torso = false
				for tp in torso:
					if s.distance_to(tp) < 0.16:
						near_torso = true
						break
				if not near_torso:
					continue
				# Foam sink OK — fail only if we punch the wood board under the pad.
				var foam_b = maxf(m.island.lounger_back_half.y * 2.0, 0.08)
				var board_b = back_pos - back_n * foam_b
				var gb = _signed_gap(s, board_b, back_n)
				if gb < -0.25:
					continue
				hit = true
				deepest = minf(deepest, gb)
			elif m.island.lounger_seat_contains(s, 0.04):
				var foam_h = maxf(m.island.lounger_seat_half.y * 2.0, 0.06)
				var board = seat_pos - seat_n * foam_h
				var gs = _signed_gap(s, board, seat_n)
				if gs < -0.25:
					continue
				hit = true
				deepest = minf(deepest, gs)
	if not hit:
		return 0.0
	return deepest

func _wake() -> void:
	if m.mode == m.Mode.REST and m.rest_phase == 4:
		m._begin_cam_blend()
		if m.rest_use_clips:
			m.rest_phase = 6
			m.rest_t = 0.0
			m.rest_clip_phase = "exit"
			_play_rest_exit_clip()
		else:
			m.rest_phase = 6 if m.rest_kind == "seat" and not m.seat_lying else 5
			m.rest_t = 0.0
		m._update_ui()

func _clip_name(phase: String) -> String:
	match m.rest_clip_prop:
		"bench":
			return "bench_sit_%s" % phase
		"log":
			return "log_sit_%s" % phase
		"hammock":
			if phase == "idle":
				return "hammock_sleep"
			return "hammock_%s" % phase
	return ""

func _apply_boy_prop_root(clip_key: String) -> void:
	var cinfo: Dictionary = m.rest_align.get("clips", {}).get(clip_key, {})
	var rp: Array = cinfo.get("root_pos_prop", [0, 0, -0.5])
	var yaw_deg = float(cinfo.get("root_yaw_deg", 0.0))
	var local = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	# Prop-frame placement exactly as authored (do NOT re-snap Y to terrain — slope was
	# burying the boy ~10–15 cm into the seat). player == boy, so never overwrite after.
	var pos = m.rest_prop_xf * local
	# alignment.json yaw 0 => faces +Z; boy.gd model.rotation.y = PI flips Mixamo +Z to game −Z,
	# so add PI when placing the boy node to match authored facing.
	var yaw = m.rest_prop_xf.basis.get_euler().y + deg_to_rad(yaw_deg) + PI
	m.boy.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	m.face_yaw = yaw
	m.ground_y = pos.y

func _play_rest_enter_clip() -> void:
	var clip = _clip_name("enter")
	m.rest_clip_phase = "enter"
	_apply_boy_prop_root(clip)
	m.boy.play_prop_clip(clip, false, 0.15)
	if m.rest_clip_prop == "hammock":
		m.island.set_hammock_clip_frame("hammock_enter", 0)
		m.boy.set_face_expr("idle")

func _play_rest_idle_clip() -> void:
	var clip = _clip_name("idle")
	m.rest_clip_phase = "idle"
	_apply_boy_prop_root(_clip_name("enter"))  # same root as enter
	m.boy.play_prop_clip(clip, true, 0.12)
	if m.rest_clip_prop == "hammock":
		m.island.set_hammock_clip_frame("hammock_sleep", 0)
		m.boy.set_face_expr("sleep")
	else:
		m.boy.set_face_expr("smile")

func _play_rest_exit_clip() -> void:
	var clip = _clip_name("exit")
	m.rest_clip_phase = "exit"
	_apply_boy_prop_root(_clip_name("enter"))
	m.boy.play_prop_clip(clip, false, 0.12)
	if m.rest_clip_prop == "hammock":
		m.island.set_hammock_clip_frame("hammock_exit", 0)
		m.boy.set_face_expr("idle")

func _finish_rest_exit() -> void:
	var clip = _clip_name("exit")
	var cinfo: Dictionary = m.rest_align.get("clips", {}).get(clip, {})
	var after: Dictionary = cinfo.get("after_exit", {})
	if after.has("new_root_pos_prop"):
		var np: Array = after["new_root_pos_prop"]
		var local = Vector3(float(np[0]), float(np[1]), float(np[2]))
		var pos = m.rest_prop_xf * local
		var yaw = m.rest_prop_xf.basis.get_euler().y + deg_to_rad(float(after.get("new_yaw_deg", 180.0))) + PI
		m.boy.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		m.face_yaw = yaw
		m.ground_y = pos.y
		m.rest_approach = Vector3(pos.x, m._surface(pos.x, pos.z), pos.z)
	else:
		# Fallback: end_root_shift in prop XZ (shift is [x,z]).
		var sh: Array = cinfo.get("end_root_shift_prop", [0, 0])
		var yaw_d = deg_to_rad(float(cinfo.get("end_yaw_delta_deg", 180.0)))
		var enter_key = _clip_name("enter")
		var einfo: Dictionary = m.rest_align.get("clips", {}).get(enter_key, {})
		var rp0: Array = einfo.get("root_pos_prop", [0, 0, -0.5])
		var local0 = Vector3(float(rp0[0]), float(rp0[1]), float(rp0[2]))
		var base = m.rest_prop_xf * local0
		var shift = m.rest_prop_xf.basis * Vector3(float(sh[0]), 0.0, float(sh[1]))
		var pos2 = base + shift
		# After exit: stand on terrain at the new XZ (authored pad should be flat).
		pos2.y = m._surface(pos2.x, pos2.z)
		var yaw0 = m.rest_prop_xf.basis.get_euler().y + deg_to_rad(float(einfo.get("root_yaw_deg", 0.0))) + PI
		var yaw2 = yaw0 + yaw_d
		m.boy.global_transform = Transform3D(Basis(Vector3.UP, yaw2), pos2)
		m.face_yaw = yaw2
		m.ground_y = pos2.y
	m.boy.end_prop_clip(0.2)
	if m.rest_clip_prop == "hammock":
		m.island.set_hammock_clip_frame("empty", 0)
	m.island.set_hammock_load([] as Array[Vector3])
	m.move_vel = Vector3.ZERO
	m.ground_y = m._surface(m.player.position.x, m.player.position.z)
	m.mode = m.Mode.EXPLORE
	# Ease back to follow from the last sit framing (don't snap behind).
	m.ex_yaw = m.cam_yaw
	m.ex_pitch = m.cam_pitch
	m.ex_dist = m.cam_dist
	m.rest_exit_cam_t = 0.8
	m.rest_use_clips = false
	m.rest_clip_phase = ""
	m._update_action_kind()
	m._update_ui()

func _sync_hammock_cloth_to_boy() -> void:
	if m.rest_clip_prop != "hammock":
		return
	var clip = m.boy.prop_clip
	if clip == "":
		return
	m.island.set_hammock_clip_frame(clip, m.boy.prop_clip_frame(24.0))

func _rest_tick_clips(delta: float) -> void:
	m.rest_t += delta
	match m.rest_phase:
		0:
			# Walk to the prop marker (approach).
			var d = m.rest_approach - m.player.position
			d.y = 0.0
			if d.length() < 0.08 or m.rest_t > 8.0:
				m.player_ctrl.write_position(Vector3(m.rest_approach.x, m.player.position.y, m.rest_approach.z))
				m.move_vel = Vector3.ZERO
				m.boy.set_move(0.0)
				m.boy.set_idle()
				m.rest_phase = 1
				m.rest_t = 0.0
				_play_rest_enter_clip()
			else:
				var spd = minf(1.0, d.length() * 3.0 + 0.3)
				m.move_vel = m.move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
				m.face_yaw = lerp_angle(m.face_yaw, atan2(-d.x, -d.z), 1.0 - exp(-delta * 10.0))
				var to = m._try_move(m.player.position, m.move_vel * delta)
				if to.distance_to(m.player.position) < m.move_vel.length() * delta * 0.2 and m.rest_t > 0.5:
					# Stuck — snap ahead.
					m.player_ctrl.write_position(Vector3(m.rest_approach.x, m.player.position.y, m.rest_approach.z))
				else:
					m.player_ctrl.write_position(to)
				m.player_ctrl.write_position(Vector3(m.player.position.x, m._surface(m.player.position.x, m.player.position.z), m.player.position.z))
				m.player_ctrl.write_yaw(m.face_yaw)
				m.boy.set_move(m.move_vel.length())
		1, 2, 3:
			# Enter clip playing (root fixed; hips carry root-motion).
			_sync_hammock_cloth_to_boy()
			if m.boy.prop_clip_finished() or m.rest_t > m.boy.prop_clip_length() + 0.3:
				m.rest_phase = 4
				m.rest_t = 0.0
				_play_rest_idle_clip()
			m.zzz.visible = false
		4:
			# Idle / sleep loop.
			_sync_hammock_cloth_to_boy()
			m.zzz.visible = m.rest_kind == "sleep"
			if m.zzz.visible:
				var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
				var cyc = fmod(m.rest_t * 0.5, 1.0)
				m.zzz.text = ["z", "z Z", "z Z z", "z Z z"][int(cyc * 4.0) % 4]
				m.zzz.global_position = head + Vector3(0, 0.38 + cyc * 0.12, 0) + m.rest_side * 0.1
				m.zzz.modulate.a = 1.0 - smoothstep(0.75, 1.0, cyc)
		5, 6:
			# Exit clip.
			m.zzz.visible = false
			_sync_hammock_cloth_to_boy()
			if m.boy.prop_clip_finished() or m.rest_t > m.boy.prop_clip_length() + 0.35:
				_finish_rest_exit()
		_:
			pass
	m._update_ui()

func _rest_tick(delta: float) -> void:
	if m.rest_frozen:
		# Shot / selftest hold: keep hammock sag + Zzz, do not advance phases.
		if m.rest_kind == "sleep" and m.rest_phase in [2, 3, 4, 5, 6]:
			if m.rest_use_clips:
				_sync_hammock_cloth_to_boy()
			else:
				_update_hammock_load()
			if m.rest_phase == 4:
				m.zzz.visible = true
				var head_z: Vector3 = (m.boy.parts["head"] as Node3D).global_position
				m.zzz.global_position = head_z + Vector3(0, 0.42, 0) + m.rest_side * 0.1
				m.zzz.modulate.a = 0.85
			else:
				m.zzz.visible = false
		return
	if m.rest_use_clips:
		_rest_tick_clips(delta)
		return
	m.rest_t += delta
	var sleep = m.rest_kind == "sleep"
	var swing = Transform3D.IDENTITY
	match m.rest_phase:
		0:
			# walk to the spot next to the bed
			var d = m.rest_approach - m.player.position
			d.y = 0.0
			if d.length() < 0.06 or m.rest_t > 7.0:
				m.player_ctrl.write_position(Vector3(m.rest_approach.x, m.player.position.y, m.rest_approach.z))
				m.move_vel = Vector3.ZERO
				m.boy.set_move(0.0)
				m.boy.set_idle()
				m.rest_phase = 1
				m.rest_t = 0.0
			else:
				var spd = minf(1.0, d.length() * 3.0 + 0.3)
				m.move_vel = m.move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
				m.face_yaw = lerp_angle(m.face_yaw, atan2(-d.x, -d.z), 1.0 - exp(-delta * 10.0))
				var to = m._try_move(m.player.position, m.move_vel * delta)
				if to.distance_to(m.player.position) < m.move_vel.length() * delta * 0.2 and m.rest_t > 0.5:
					to = m.player.position + m.move_vel * delta   # wedged: the spot is right there, just go
				var h = m._surface(to.x, to.z)
				m.ground_y = lerpf(m.ground_y, h, 1.0 - exp(-delta * 18.0))
				to.y = m.ground_y
				m.player_ctrl.write_position(to)
				m.player_ctrl.write_yaw(m.face_yaw)
				m.boy.set_move(m.move_vel.length())
		1:
			# turn around: back to the bed (hammock) / face the sea (towel)
			var want = m.rest_sit_b.get_euler().y
			m.face_yaw = lerp_angle(m.face_yaw, want, 1.0 - exp(-delta * 9.0))
			m.player_ctrl.write_yaw(m.face_yaw)
			if m.rest_t > 0.55:
				m.face_yaw = want
				m.rest_phase = 2
				m.rest_t = 0.0
		2, 6:
			var dur = 1.05
			var k = clampf(m.rest_t / dur, 0.0, 1.0)
			if m.rest_phase == 6:
				k = 1.0 - k
			var ks = smoothstep(0.0, 1.0, k)
			var pl = m.boy.activity(m.rest_kind, k, 0.0, m.gt)
			var root: Vector3
			if sleep:
				# Side perch → settle onto mid fabric; lift clears the rail.
				var edge = m.rest_approach.lerp(m.rest_root_sit, 0.55)
				edge.y = maxf(edge.y, m.rest_root_sit.y + 0.06)
				root = m.rest_approach.lerp(edge, clampf(ks * 1.35, 0.0, 1.0)).lerp(m.rest_root_sit, smoothstep(0.45, 1.0, ks))
				root.y += 0.16 * sin(PI * ks)
			else:
				root = m.rest_approach.lerp(m.rest_root_sit, ks)
				# Clear the seat board mid-lerp; settle by snap near the end.
				var is_log_exit = m.rest_kind == "seat" and m.seat_i >= 0 and m.seat_i < m.island.seats.size() \
					and String(m.island.seats[m.seat_i].get("name", "")) == "坐木"
				root.y += (0.24 if is_log_exit else 0.17) * sin(PI * ks)
				if m.rest_phase == 6:
					# Hold seat-height Y until the sit clip has mostly stood up.
					var stand_u = smoothstep(0.06, 0.62, 1.0 - ks)
					var y_pad = 0.16 if is_log_exit else 0.07
					var y_hold = lerpf(m.rest_root_sit.y + y_pad, m.rest_approach.y, stand_u)
					root.y = maxf(root.y, y_hold)
					# Slide further off the seat so standing legs don't clip the log volume.
					var away: Vector3 = m.rest_approach - m.rest_seat
					away.y = 0.0
					if away.length() > 0.05:
						root += away.normalized() * ((0.32 if is_log_exit else 0.16) * (1.0 - ks))
			swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3)) if sleep else Transform3D.IDENTITY
			m.boy.global_transform = swing * Transform3D(m.rest_sit_b, root)
			# Seat exit: live mesh clearance against the seat top footprint.
			if m.rest_kind == "seat" and m.rest_phase == 6 and m.seat_i >= 0 and m.seat_i < m.island.seats.size():
				var st_ex: Dictionary = m.island.seats[m.seat_i]
				var top_ex: Vector3 = st_ex["top"]
				var face_ex: Vector3 = m.seat_face.normalized()
				var side_ex: Vector3 = m.rest_side.normalized() if m.rest_side.length() > 0.1 else face_ex.cross(Vector3.UP).normalized()
				var hips_ex: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
				var dig_ex = 1e9
				var hit_ex = false
				for s_ex in m.boy.skinned_sample_world(500):
					if s_ex.distance_to(hips_ex) > 0.38:
						continue
					if s_ex.y > hips_ex.y + 0.05:
						continue
					var lat_ex: float = (s_ex - top_ex).dot(side_ex)
					var along_ex: float = (s_ex - top_ex).dot(-face_ex)
					if absf(lat_ex) > 0.70 or along_ex < -0.22 or along_ex > 0.45:
						continue
					hit_ex = true
					dig_ex = minf(dig_ex, s_ex.y - top_ex.y)
				if hit_ex and dig_ex < -0.008:
					root.y += minf(-dig_ex + 0.02, 0.16)
					var away2: Vector3 = m.rest_approach - m.rest_seat
					away2.y = 0.0
					if away2.length() > 0.05:
						root += away2.normalized() * minf(-dig_ex, 0.10)
					m.boy.global_transform = Transform3D(m.rest_sit_b, root)
			if m.rest_kind == "seat" and m.rest_phase == 2 and ks > 0.72:
				_snap_sit_contact()
				pl = m.boy.activity("seat", 1.0, 0.0, m.gt)
				m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
				var settled = m.rest_approach.lerp(m.rest_root_sit, ks)
				settled.y += 0.08 * sin(PI * ks)
				m.boy.global_transform = Transform3D(m.rest_sit_b, settled)
			if sleep and m.rest_phase == 2 and ks > 0.70:
				_snap_sit_contact()
				pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
				m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
				m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
				_update_hammock_load()
			if m.rest_t >= dur:
				m.rest_t = 0.0
				if m.rest_phase == 2:
					if m.rest_kind == "seat":
						_snap_sit_contact()
						pl = m.boy.activity("seat", 1.0, 0.0, m.gt)
						m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
					elif sleep:
						_snap_sit_contact()
						pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
						m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
						_update_hammock_load()
					m.rest_phase = 4 if m.rest_kind == "seat" else 3
					m._update_ui()
				else:
					m.boy.end_activity()
					if sleep:
						m.island.set_hammock_load([] as Array[Vector3])
					m.player_ctrl.write_position(m._blocked_by(m.rest_approach))
					m.player_ctrl.write_yaw(m.face_yaw)
					m.ground_y = m._surface(m.player.position.x, m.player.position.z)
					m.move_vel = Vector3.ZERO
					m.mode = m.Mode.EXPLORE
					m.ex_yaw = m.cam_yaw
					m.ex_pitch = m.cam_pitch
					m.ex_dist = m.cam_dist
					m.rest_exit_cam_t = 0.8
					m._update_action_kind()
					m._update_ui()
		3, 5:
			var dur2 = m.SEAT_LIE_DUR if m.rest_kind == "seat" else m.LIE_BLEND_DUR
			var k2 = clampf(m.rest_t / dur2, 0.0, 1.0)
			if m.rest_phase == 5:
				k2 = 1.0 - k2
			var ks2 = smoothstep(0.0, 1.0, k2)
			var pl2 = m.boy.activity(_act_kind(), 1.0, k2, m.gt)
			var b = m.rest_sit_b.slerp(m.rest_lie_b, ks2)
			var w = m.rest_seat.lerp(m.rest_lie, ks2) + Vector3(0, 0.10 * sin(PI * k2), 0)
			if m.rest_kind == "sun":
				# Keep butt/back/hat clear of lounger foam during tip-back AND tip-up (exit).
				# Prior lifts still dug ~11 cm into the pad mid-exit — clear the foam fully.
				w.y += 0.24 * sin(PI * k2)
				var back_n: Vector3 = (-m.rest_lie_b.z).normalized()
				if back_n.y < 0.15:
					back_n = Vector3.UP
				w += back_n * (0.14 * sin(PI * k2))
			if m.rest_kind == "seat" and m.island.seats[m.seat_i]["name"] == "长椅":
				# shuffles forward on the seat as he turns to lie back: head (and hat) clear of the backrest
				w += m.seat_face * 0.18 * sin(PI * k2)
			if sleep:
				# Stay above the fabric while tipping into/out of the cradle; snap settles at phase 4.
				var ham_n: Vector3 = (m.island.hammock_frame(0.5)["normal"] as Vector3).normalized()
				w += ham_n * (0.20 * sin(PI * k2))
				m.swing_amp = lerpf(m.swing_amp, 0.06 * ks2 + 0.01, 1.0 - exp(-delta * 2.0))
				swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
				_update_hammock_load()
			m.boy.global_transform = swing * Transform3D(b, w - b * pl2)
			# Lounger tip (enter+exit): if mid-blend still penetrates, lift fully clear.
			if m.rest_kind == "sun" and m.rest_phase in [3, 5] and m.rest_t > 0.15:
				var dig: float = lie_mesh_penetration_depth(true)
				if dig < -0.008:
					w += Vector3.UP * minf(-dig + 0.01, 0.14)
					m.boy.global_transform = Transform3D(b, w - b * pl2)
			if m.rest_t >= dur2:
				if sleep and m.rest_phase == 5:
					m.island.set_hammock_load([] as Array[Vector3])
				m.rest_t = 0.0
				m.rest_phase = 4 if m.rest_phase == 3 else 6
				if m.rest_phase == 6 and m.rest_kind == "seat":
					m.seat_lying = false
				m._update_ui()
		4 when m.rest_kind == "seat" and not m.seat_lying:
			# lie_k must stay 0 — lie_k=1 switches the pelvis local offset and digs the butt into the board.
			m.boy.activity("seat", 1.0, 0.0, m.rest_t)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			# Keep butt on the seat if the sit clip drifts.
			if fmod(m.rest_t, 0.35) < delta:
				_snap_sit_contact()
				var pl_s = m.boy.activity("seat", 1.0, 0.0, m.gt)
				m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl_s
				m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		4:
			# Drop prior foot overrides before posing — planted knees while hips float
			# stretch Tripo thighs through the cushion.
			if m.rest_kind == "sun":
				m.boy.clear_foot_plant()
			var pl3 = m.boy.activity(_act_kind(), 1.0, 1.0, m.gt)
			if sleep:
				m.swing_amp = lerpf(m.swing_amp, 0.07, 1.0 - exp(-delta * 1.0))
				swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
			# contact snap so skinned mesh sits on the support (few passes — over-iterating walks off the pad)
			if m.rest_t > 0.05 and (not m.get_meta("lie_snapped", false) or fmod(m.rest_t, 1.5) < delta):
				var passes = 6 if not m.get_meta("lie_snapped", false) else 2
				for _pass in passes:
					_snap_lie_contact()
					pl3 = m.boy.activity(_act_kind(), 1.0, 1.0, m.gt)
					m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
				m.set_meta("lie_snapped", true)
			if sleep:
				_update_hammock_load()
			_plant_lie_feet()
	# floating Zzz above the sleeping head
	m.zzz.visible = sleep and m.rest_phase == 4
	if m.zzz.visible:
		var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
		var cyc = fmod(m.rest_t * 0.5, 1.0)
		m.zzz.text = ["z", "z Z", "z Z z", "z Z z"][int(cyc * 4.0) % 4]
		m.zzz.global_position = head + Vector3(0, 0.38 + cyc * 0.12, 0) + m.rest_side * 0.1
		m.zzz.modulate.a = 1.0 - smoothstep(0.75, 1.0, cyc)

func _idle_hammock(delta: float) -> void:
	if m.mode == m.Mode.REST and m.rest_kind == "sleep":
		return
	m.swing_amp = lerpf(m.swing_amp, 0.015, 1.0 - exp(-delta * 1.0))
	m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.1))
	# Empty hammock: light resting sag.
	if m.island.hammock_occupied:
		m.island.set_hammock_load([] as Array[Vector3])


## Push hip / shoulder / heel samples into the deformable hammock so the fabric takes his weight.

func _update_hammock_load() -> void:
	var pts: Array[Vector3] = []
	pts.append(m.boy.lie_bone_world("mixamorig_Hips"))
	pts.append(m.boy.lie_bone_world("mixamorig_Spine1"))
	pts.append(m.boy.lie_bone_world("mixamorig_Spine2"))
	pts.append(m.boy.lie_bone_world("mixamorig_Head"))
	pts.append(m.boy.lie_bone_world("mixamorig_LeftFoot"))
	pts.append(m.boy.lie_bone_world("mixamorig_RightFoot"))
	m.island.set_hammock_load(pts)


# ------------------------------------------------------------------ input

