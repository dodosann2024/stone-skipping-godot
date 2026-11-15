class_name LocomotionAnim
extends RefCounted
## AnimationTree locomotion only. No foot poses — FootIK owns contact
## inside the skeleton update that the renderer uploads.
var b: CharacterBody3D

func setup(p_boy: CharacterBody3D) -> void:
	b = p_boy

func advance(delta: float) -> bool:
	if b == null:
		return false
	_tick(delta)
	return str(b.anim) not in ["activity", "prop_clip"]

func polish(delta: float) -> void:
	_polish_gait(delta)


func _throw_clip() -> String:
	# Meta key in boy_meta.json (has t_charge / t_release). Playback resolves to pitch_baseball.
	return "throw_crouch" if b.stance == "crouch" else "throw_stand"



func _to_idle() -> void:
	b.anim = "idle"
	b.act_target = 0.0
	b.act_rate = 6.0
	b.stopping = false
	b.react_kind = ""
	b.act_kind = ""
	b.act_lie_k = 0.0
	b.model.rotation.x = 0.0
	b.lie_settle = 0.0
	b.model.position = b.model_base
	if b.ap:
		b.ap.active = true
	if b.tree:
		b.tree.active = true



func _resolve_clip(name: String) -> String:
	if b.ap.has_animation(name):
		return name
	# aliases — dig/lift_heavy intentionally omitted (not sleep / stone-pick).
	var map = {
		"stroll": "walk",
		"throw_stand": "pitch_baseball", "throw_crouch": "pitch_baseball",
		"wave": "turn", "oops": "cheer", "standing_relax": "idle", "jump": "idle",
		"sun_sit": "sit", "sun_lie": "sit", "sun_rest": "sit", "sun_up": "sit", "sun_stand": "idle",
		# Authored hammock/bench/log clips — resolve only when present.
		"hammock_sit": "hammock_enter", "hammock_lie": "hammock_sleep",
		"hammock_sleep": "hammock_sleep", "hammock_up": "hammock_exit", "hammock_stand": "idle",
		"seat_sit": "bench_sit_idle", "seat_rest": "bench_sit_idle",
		"seat_lie": "bench_sit_idle", "seat_nap": "bench_sit_idle",
		"seat_up": "bench_sit_exit", "seat_stand": "idle",
	}
	var a: String = map.get(name, "idle")
	if b.ap.has_animation(a):
		return a
	# Fallbacks when a prop clip is missing.
	if b.ap.has_animation("sit"):
		return "sit"
	return "idle" if b.ap.has_animation("idle") else name



func _set_slot(i: int, clip: String, tseek: float) -> void:
	var real = _resolve_clip(clip)
	b.slot_clip[i] = clip
	b.slot_t[i] = tseek
	var node: AnimationNodeAnimation = b.bt.get_node("a" if i == 0 else "b")
	node.animation = real



func _play(clip: String, tseek: float, fade: float, force_slot = false) -> void:
	var same = b.slot_clip[b.cur_slot] == clip and not force_slot
	if same:
		b.slot_t[b.cur_slot] = tseek
		return
	var other = 1 - b.cur_slot
	_set_slot(other, clip, tseek)
	b.cur_slot = other
	if fade <= 0.0:
		b.ab_w = float(b.cur_slot)
	else:
		b.ab_rate = 1.0 / maxf(fade, 0.01)



func _apply_mixer() -> void:
	if b.tree == null:
		return
	var walk: Dictionary = b.clips["walk"]
	var run: Dictionary = b.clips["run"]
	b.tree.set("parameters/idle_s/seek_request", b.t_idle)
	b.tree.set("parameters/walk_s/seek_request", b.phase * float(walk["length"]))
	b.tree.set("parameters/run_s/seek_request", b.phase * float(run["length"]))
	b.tree.set("parameters/stroll_s/seek_request", b.phase * float(b.clips.get("stroll", walk)["length"]))
	b.tree.set("parameters/a_s/seek_request", b.slot_t[0])
	b.tree.set("parameters/b_s/seek_request", b.slot_t[1])
	b.tree.set("parameters/wr/blend_amount", b.run_k)
	b.tree.set("parameters/move/blend_amount", smoothstep(0.0, 1.0, b.move_w))
	b.tree.set("parameters/ab/blend_amount", b.ab_w)
	b.tree.set("parameters/act/blend_amount", b.act_w)
	b.tree.advance(0.0)
	if absf(b.aim_twist) > 1e-4:
		Boy.twist_spine(b.skel, b.aim_twist)


## Per-foot contact discs under RENDERED stance soles (late-plant frame).
## Hip blob stays OFF. While locomoting, discs are hidden — sun cast shadow +
## footprints own the contact read (avoids any shoe-length trail during drag).
## Idle / near-stop: discs sit under stance soles after IK, world-space on the
## scene host so CharacterBody display-interp cannot drag them.

func _polish_gait(delta: float) -> void:
	if b.skel == null or b.model == null:
		return
	if b._settle_left > 0.0:
		b._settle_left = maxf(0.0, b._settle_left - delta)
	var moving = b.anim == "move" and b.move_w > 0.25 and not b.pivoting
	var sway = 0.0
	if moving:
		var amp = lerpf(0.35, 0.55, b.run_k) * b.move_w
		var upright = 0.035 + 0.05 * b.run_k + absf(b.turn_lean) * 0.10
		b._pose_add("mixamorig_Spine", Vector3(-upright * 0.4, b.turn_lean * 0.14, b.turn_lean * 0.20), b.move_w * 0.55)
		b._pose_add("mixamorig_Spine1", Vector3(-upright * 0.28, b.turn_lean * 0.10, 0.0), b.move_w * 0.5)
		var look_y = clampf(b.turn_ahead, -0.35, 0.35) * 0.4
		b._pose_add("mixamorig_Head", Vector3(upright * 0.15, look_y, 0.0), b.move_w * 0.4)
		var s = sin(b.phase * TAU)
		var c = cos(b.phase * TAU)
		var swing = s * lerpf(0.30, 0.45, b.run_k) * amp
		b._pose_add("mixamorig_LeftArm", Vector3(swing * 0.55, -swing * 0.08, -swing * 0.18), 0.6)
		b._pose_add("mixamorig_RightArm", Vector3(-swing * 0.55, swing * 0.08, swing * 0.18), 0.6)
		b._pose_add("mixamorig_LeftForeArm", Vector3(-absf(swing) * 0.28, 0.0, 0.0), 0.5)
		b._pose_add("mixamorig_RightForeArm", Vector3(-absf(swing) * 0.28, 0.0, 0.0), 0.5)
		sway = -c * lerpf(0.010, 0.016, b.run_k) * b.move_w
		b.hip_shift = b.hip_shift.lerp(Vector3(sway, 0, 0), 1.0 - exp(-delta * 8.0))
	else:
		b.hip_shift = b.hip_shift.lerp(Vector3.ZERO, 1.0 - exp(-delta * 6.0))
	b._walk_bob = lerpf(b._walk_bob, 0.0, 1.0 - exp(-delta * 10.0))
	# Model Y: hip sway only — FootIK owns contact (no contact_lift / pelvis drop).
	b.model.position = b.model_base + Vector3(b.hip_shift.x, 0.0, 0.0)



func _tick(delta: float) -> void:
	b.lead_dt = delta
	b.act_frames += 1
	b.t += delta
	b.anim_t += delta
	b.act_w = move_toward(b.act_w, b.act_target, delta * b.act_rate)
	b.ab_w = move_toward(b.ab_w, float(b.cur_slot), delta * b.ab_rate)

	# spot-turn footfalls: 2–3 alternating steps (open / turn / close), no steps_taken
	if b.pivoting and not b.was_pivoting:
		b.spot_clock = 0.0
		b.spot_emitted = 0
		if b.anim != "move":
			b.anim = "move"
			b.act_target = 0.0
			b.move_w = maxf(b.move_w, 0.6)
	if b.pivoting:
		b.pivot_grace = 0.35
		b.spot_clock += delta
		# timed so a ~180° flick lands 2–3 spot steps before the heading settles
		var marks = [0.10, 0.38, 0.66]
		while b.spot_emitted < marks.size() and b.spot_clock >= float(marks[b.spot_emitted]):
			b.spot_steps += 1
			b.footstep.emit(b.spot_emitted % 2, false)
			b.foot_flat.emit(b.spot_emitted % 2)
			b.spot_emitted += 1
	else:
		b.pivot_grace = maxf(0.0, b.pivot_grace - delta)
	b.was_pivoting = b.pivoting

	# locomotion blends
	if b.anim == "move":
		# Frame-rate independent speed smoothing — avoids walk↔run blend pops on hitch/ProMotion.
		b.speed_s = lerpf(b.speed_s, b.move_speed, 1.0 - exp(-delta * 12.0))
		b.run_k = 0.0 if b.pivoting else smoothstep(Boy.RUN_FROM, Boy.RUN_TO, b.speed_s)
		# Light stick → stroll (soft), then walk. Keep walk_k for mix amount.
		b.walk_k = clampf(smoothstep(0.35, 1.05, b.speed_s), 0.0, 1.0)
		b.move_w = move_toward(b.move_w, 1.0, delta * 4.0)
		var dist = 0.0
		if b.has_prev:
			dist = Vector3(b.global_position.x - b.prev_pos.x, 0, b.global_position.z - b.prev_pos.z).length()
		b.prev_pos = b.global_position
		b.has_prev = true
		# Blend stride with run_k so walk→run doesn't jump the phase rate at 0.5.
		var stride = lerpf(float(b.clips["walk"]["stride"]), float(b.clips["run"]["stride"]), b.run_k)
		# Drive phase from smoothed speed (matches anim to locomotion). Position delta
		# only clamps hitch overshoot — never leads, so interp/display lag can't skate.
		var dphase: float
		if b.pivoting or b.speed_s < 0.04:
			dphase = delta / maxf(float(b.clips["walk"]["length"]), 0.2)
		else:
			dphase = (b.speed_s * delta) / maxf(stride, 0.05)
			if dist > 1e-5:
				dphase = minf(dphase, dist / maxf(stride, 0.05) * 1.15)
		dphase = minf(dphase, 0.18)
		b.phase = fposmod(b.phase + dphase, 1.0)
		# walking footfalls only when translating after the spot-turn grace window
		if not b.pivoting and b.pivot_grace <= 0.0:
			var side = 0 if b.phase < 0.5 else 1
			if side != b._prev_phase_side and b.move_w > 0.5 and dist > 0.001:
				b.footstep.emit(side, b.run_k > 0.5)
				b.foot_flat.emit(side)
				b.steps_taken += 1
			b._prev_phase_side = side
		elif b.pivoting or b.pivot_grace > 0.0:
			b._prev_phase_side = -1
		b.t_idle = 0.0
	else:
		b.move_w = move_toward(b.move_w, 0.0, delta * 5.0)
		b.t_idle = fposmod(b.t_idle + delta, float(b.clips["idle"]["length"]))
		b.has_prev = false
		b._prev_phase_side = -1

	# advance action slot times
	for i in 2:
		if b.slot_clip[i] != "":
			var real = _resolve_clip(b.slot_clip[i])
			var L = float(b.clips.get(b.slot_clip[i], b.clips.get(real, {"length": 1.0}))["length"])
			if b.anim in ["charge"]:
				# hold near start of throw (wind-up) based on power
				b.slot_t[i] = clampf(b.power, 0.0, 1.0) * float(b.clips[_throw_clip()].get("t_charge", 0.35))
			elif b.anim == "throw":
				var tc = float(b.clips[_throw_clip()].get("t_charge", 0.35))
				b.slot_t[i] = minf(tc + b.anim_t, L)
				var tr = float(b.clips[_throw_clip()].get("t_release", Boy.T_RELEASE))
				if not b.did_release and b.anim_t >= maxf(0.0, tr - tc):
					b.did_release = true
					b.show_stone(false)
					b.released.emit()
				if tc + b.anim_t >= L:
					_to_idle()
					b.show_stone(true)
			elif b.anim == "react":
				b.slot_t[i] = minf(b.anim_t, L)
				if b.anim_t >= L:
					_to_idle()
			elif b.anim == "activity":
				# keep seek set by _play
				pass
			else:
				b.slot_t[i] = fposmod(b.slot_t[i] + delta, maxf(L, 0.01)) if b.clips.get(b.slot_clip[i], {}).get("loop", false) else minf(b.slot_t[i] + delta, L)

	if b.anim == "prop_clip" or b.prop_clip != "":
		# Authored bench/log/hammock clips: AnimationPlayer only, no tree/pose stack.
		if b.tree:
			b.tree.active = false
		if b.ap and not b.ap.active:
			b.ap.active = true
		b._update_blob()
		b._update_face(delta)
		return
	if b.anim == "activity" and b.act_lie_k > 0.45 and b.act_kind in ["sun", "sleep", "seatlie"]:
		b._seed_lie_from_sit()
		b._apply_lie_pose(b.act_kind, b.act_lie_k, b.act_tt)
		# Idle seek clears global pose overrides — re-plant so thighs stay ON the cushion.
		if b.lie_foot_plant and b.act_kind == "sun":
			b.plant_feet_on_plane(b.lie_foot_plane_point, b.lie_foot_plane_normal, b.lie_foot_plant_gap, true)
	elif b.anim == "activity" and b.act_lie_k < 0.45 and b.act_kind in ["seat", "sleep", "sun"] and b.act_w > 0.5:
		# Re-seed every tick — pose_add is relative; stacking without reset bends sideways.
		b._seed_lie_from_sit()
		b._apply_ergonomic_sit(clampf(b.act_w, 0.0, 1.0) * (1.0 - b.act_lie_k))
	else:
		if b.ap and not b.ap.active:
			b.ap.active = true
		if b.tree and not b.tree.active:
			b.tree.active = true
		_apply_mixer()
	if b.loco != null:
		b.loco.polish(delta)
	else:
		_polish_gait(delta)
	# Single plant: drawable local poses after mixer (Compatibility skins these).
	b._update_face(delta)


## Soft child gait on Mixamo: light limb boost, hip sway, bob, turn lean.
## Keep amps small — v24 overdrive made a conveyor/skating read next to AC.
## Legs are owned by FootIK — polish never writes UpLeg/Leg/Foot.
