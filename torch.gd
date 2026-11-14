class_name Torch
extends Node3D
## A tiki torch's live parts, sitting on the oil-soaked cloth wick: three flame tongues (the campfire's
## flame shader, smaller and quicker), a few rising embers, a thin smoke wisp, a heat glow and a warm
## flickering light that is subtle by day and carries the camp at night. At night the flame also lights its own
## pole, cup and lashing all the way round (island.gd's torch_wood material, `wood_mat`).

var light: OmniLight3D
var glow: ShaderMaterial
var flames: Array[MeshInstance3D] = []
var t := 0.0
var phase := 0.0
var night := 0.0
var wood_mat: ShaderMaterial
var slot := 0
static var flame_data: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]
const SELF_LIT := 2.2

func build(seed_: float) -> void:
	phase = seed_ * 5.3
	var flame_sh: Shader = load("res://shaders/flame.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	# [offset, width, height, seed, speed, strength, tint]
	var layers := [
		[Vector3(0.0, -0.03, 0.0), 0.2, 0.36, 11.0 + seed_, 2.2, 0.45, Color(1.0, 0.62, 0.45)],
		[Vector3(0.015, -0.02, 0.01), 0.14, 0.27, 13.7 + seed_, 2.6, 0.6, Color(1.0, 0.85, 0.72)],
		[Vector3(-0.01, -0.01, -0.01), 0.085, 0.16, 17.3 + seed_, 3.0, 0.8, Color(1.0, 1.0, 0.88)],
	]
	for l: Array in layers:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = flame_sh
		mat.set_shader_parameter("seed", l[3])
		mat.set_shader_parameter("speed", l[4])
		mat.set_shader_parameter("strength", l[5])
		mat.set_shader_parameter("tint", l[6])
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = l[0]
		mi.scale = Vector3(l[1], l[2], 1.0)
		mi.extra_cull_margin = 0.5
		add_child(mi)
		flames.append(mi)
	var hq := QuadMesh.new()
	hq.size = Vector2(1, 1)
	glow = ShaderMaterial.new()
	glow.shader = load("res://shaders/halo.gdshader")
	glow.set_shader_parameter("color", Color(1.0, 0.6, 0.28))
	var h := MeshInstance3D.new()
	h.mesh = hq
	h.material_override = glow
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.position = Vector3(0, 0.1, 0)
	h.scale = Vector3.ONE * 0.8
	h.layers = 1 | 16
	add_child(h)
	_embers()
	_smoke()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0, 0.16, 0)
	add_child(light)
	_process(0.0)

func _particle_mat(additive: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/particle_add.gdshader" if additive else "res://shaders/particle.gdshader")
	return m

func _embers() -> void:
	var p := CPUParticles3D.new()
	p.amount = 7
	p.lifetime = 1.3
	p.randomness = 0.6
	p.lifetime_randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.05, 0.35, 0.02)
	p.damping_min = 0.3
	p.damping_max = 0.8
	p.tangential_accel_min = -0.5
	p.tangential_accel_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	q.material = _particle_mat(true)
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.78, 0.35, 1.0), Color(1.0, 0.42, 0.08, 0.9), Color(0.5, 0.08, 0.0, 0.0)])
	p.color_ramp = g
	p.position = Vector3(0, 0.08, 0)
	p.local_coords = false
	p.layers = 1 | 16
	add_child(p)

func _smoke() -> void:
	var p := CPUParticles3D.new()
	p.amount = 6
	p.lifetime = 3.2
	p.lifetime_randomness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.03
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.1, 0.04, 0.04)
	p.damping_min = 0.05
	p.damping_max = 0.1
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	q.material = _particle_mat(false)
	q.material.set_shader_parameter("grow", Vector2(0.3, 1.5))
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.3, 0.28, 0.27, 0.0), Color(0.38, 0.36, 0.35, 0.16), Color(0.62, 0.62, 0.62, 0.07), Color(0.8, 0.8, 0.8, 0.0)])
	p.color_ramp = g
	p.position = Vector3(0, 0.32, 0)
	p.local_coords = false
	p.layers = 1 | 16
	add_child(p)

func _noise1(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	var a := fposmod(sin(i * 91.7 + phase * 13.0) * 43758.5453, 1.0)
	var b := fposmod(sin((i + 1.0) * 91.7 + phase * 13.0) * 43758.5453, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(a, b, f) * 2.0 - 1.0


func _process(delta: float) -> void:
	t += delta
	var s := t + phase
	var f := 0.5 * _noise1(s * 4.2) + 0.3 * _noise1(s * 9.1 + 3.0) + 0.2 * _noise1(s * 15.0 + 8.0)
	var dip := smoothstep(0.82, 1.0, _noise1(s * 0.55 + 2.0))
	var k := 1.0 + 0.22 * f - 0.22 * dip
	# Small-radius warm omnis — falloff keeps moonlight dominant away from the torch.
	light.light_energy = k * lerpf(0.45, 1.35, night)
	light.omni_range = lerpf(2.4, 4.2, night)
	light.omni_attenuation = lerpf(1.1, 1.5, night)
	light.position = Vector3(0.012 * _noise1(s * 3.1), 0.12 + 0.018 * f, 0.012 * _noise1(s * 2.4 + 5.0))
	glow.set_shader_parameter("k", k * lerpf(0.18, 0.55, night))
	if wood_mat and slot < flame_data.size():
		var fp := global_position + Vector3(0, 0.06, 0)
		flame_data[slot] = Vector4(fp.x, fp.y, fp.z, k * night * SELF_LIT)
		wood_mat.set_shader_parameter("flames", flame_data)
	for i in flames.size():
		var fl := flames[i]
		fl.position.x = (0.015 if i == 1 else -0.01 * i) + 0.006 * sin(s * (4.0 + i))
