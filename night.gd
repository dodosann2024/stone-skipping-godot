class_name NightFx
extends Node3D
## The night-only extras (main.gd fades them in with `apply(k, ...)`): stars and the moon on a dome
## around the camera, lamp lights and glows, the lighthouse's turning beams and fireflies near the
## campfire. Lights stay few (the Compatibility renderer lights each mesh with a handful at most).

var dome_mat: ShaderMaterial
var dome: MeshInstance3D
var lamp_lights: Array[OmniLight3D] = []
var lamp_energy: Array[float] = []
var lamp_kinds: Array[String] = []
var halos: Array[ShaderMaterial] = []
var halo_kinds: Array[String] = []
var beam_pivot: Node3D
var beam_mat: ShaderMaterial
var beacon_light: OmniLight3D
var fly_mat: ShaderMaterial
var flies: MultiMeshInstance3D
var t := 0.0

func build(island: Island) -> void:
	var sm := SphereMesh.new()
	sm.radius = 400.0
	sm.height = 800.0
	sm.radial_segments = 32
	sm.rings = 16
	dome_mat = ShaderMaterial.new()
	dome_mat.shader = load("res://shaders/night_sky.gdshader")
	dome_mat.render_priority = -100
	dome = _mi(sm, dome_mat)
	var halo_sh: Shader = load("res://shaders/halo.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	for l: Array in island.lamps:
		var p: Vector3 = l[0]
		var kind: String = l[1]
		var hm := ShaderMaterial.new()
		hm.shader = halo_sh
		var h := _mi(quad, hm)
		h.position = p
		hm.set_shader_parameter("color", Color(1.0, 0.78, 0.42))
		# Soft bloom — path lamps use the hanging glass + tiny GB flame (no halo billboard).
		h.scale = Vector3.ONE * (2.4 if kind == "porch" else (1.8 if kind == "dock" else 0.01))
		h.visible = kind != "path"
		halos.append(hm)
		halo_kinds.append(kind)
		# Real omni for every lamp. Path: short warm pool that falls off fast.
		var ol := OmniLight3D.new()
		if kind == "dock":
			ol.light_color = Color(1.0, 0.64, 0.30)
			ol.omni_range = 2.4
			ol.omni_attenuation = 1.6
			ol.light_specular = 0.12
			lamp_energy.append(0.85)
		elif kind == "path":
			# Hanging cage key + short warm pool (ground still mostly shader emission).
			ol.light_color = Color(1.0, 0.76, 0.48)
			ol.omni_range = 2.6
			ol.omni_attenuation = 1.55
			ol.light_specular = 0.0
			lamp_energy.append(0.85)
		else:
			ol.light_color = Color(1.0, 0.72, 0.38)
			ol.omni_range = 4.2
			ol.omni_attenuation = 1.0
			ol.light_specular = 0.25
			lamp_energy.append(2.1)
		ol.shadow_enabled = false
		# Path: keep Omni near the cage (boy key); do not drop it onto the ground.
		ol.position = p + (Vector3(0, -0.08, 0) if kind == "path" else Vector3(0, -0.05, 0))
		ol.visible = false
		add_child(ol)
		lamp_lights.append(ol)
		lamp_kinds.append(kind)
	# lighthouse: glow, a local light on the tower top and two opposite beams sweeping round
	var bh := ShaderMaterial.new()
	bh.shader = halo_sh
	bh.set_shader_parameter("color", Color(1.0, 0.88, 0.6))
	var bq := _mi(quad, bh)
	bq.position = island.beacon_pos
	bq.scale = Vector3.ONE * 3.2
	halos.append(bh)
	halo_kinds.append("beacon")
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.85, 0.55)
	beacon_light.omni_range = 4.5
	beacon_light.omni_attenuation = 1.2
	beacon_light.position = island.beacon_pos + Vector3(0, 0.6, 0)
	beacon_light.visible = false
	add_child(beacon_light)
	lamp_lights.append(beacon_light)
	lamp_energy.append(0.9)
	beam_pivot = Node3D.new()
	beam_pivot.position = island.beacon_pos
	add_child(beam_pivot)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.25
	cone.bottom_radius = 2.6
	cone.height = 22.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/beam.gdshader")
	beam_mat.set_shader_parameter("half_len", 11.0)
	for s in [1.0, -1.0]:
		var b := MeshInstance3D.new()
		b.mesh = cone
		b.material_override = beam_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# lay the cone on its side: the narrow top at the lamp, the wide end 22 m out, tipped a little down
		b.basis = Basis(Vector3.UP, 0.0 if s > 0.0 else PI) * Basis(Vector3.RIGHT, PI * 0.5 - 0.06)
		b.position = b.basis * Vector3(0, -11.0, 0)
		beam_pivot.add_child(b)
	beam_pivot.visible = false
	# fireflies around the campfire, the hut and the palms behind the beach
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 28
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := island.campfire_pos
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.6, 7.5)
		var x := c.x + cos(a) * r
		var z := c.z + sin(a) * r
		var y := island.ground_h(x, z) + rng.randf_range(0.35, 1.7)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	fly_mat = ShaderMaterial.new()
	fly_mat.shader = load("res://shaders/firefly.gdshader")
	flies = MultiMeshInstance3D.new()
	flies.multimesh = mm
	flies.material_override = fly_mat
	flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flies.extra_cull_margin = 2.0
	flies.layers = 1 | WaterReflection.SKIP_LAYER
	add_child(flies)
	apply(0.0, Vector3.ZERO, Vector3(0, 0.47, -0.88), 0.0)

func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func apply(k: float, cam_pos: Vector3, moon_dir: Vector3, delta: float) -> void:
	t += delta
	var on := k > 0.01
	visible = on
	if not on:
		# Explicitly kill lamp omnis by day (parent hide alone still leaves child.visible true).
		for ol in lamp_lights:
			ol.visible = false
			ol.light_energy = 0.0
		if beacon_light:
			beacon_light.visible = false
			beacon_light.light_energy = 0.0
		return
	dome.position = cam_pos
	dome_mat.set_shader_parameter("k", k)
	dome_mat.set_shader_parameter("moon_dir", moon_dir)
	dome_mat.set_shader_parameter("time", t)
	# Cap active night omnis to 2–3 nearest the player. Prefer path lanterns (hanging cage key).
	var scored: Array = []
	for i in lamp_lights.size():
		var ol := lamp_lights[i]
		var d := ol.global_position.distance_to(cam_pos)
		var kind := lamp_kinds[i] if i < lamp_kinds.size() else ""
		# Path lamps get a slight distance bias so the forest lantern stays in the top-3.
		var score := d - (2.5 if kind == "path" else 0.0)
		scored.append([score, d, i])
		ol.visible = false
		ol.light_energy = 0.0
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var active_n := mini(3, scored.size())
	for n in active_n:
		var i: int = scored[n][2]
		var d: float = scored[n][1]
		var ol := lamp_lights[i]
		if d > ol.omni_range + 12.0:
			continue
		ol.visible = true
		var e := lamp_energy[i]
		# Path: a bit more energy so the hanging lantern + ground pool read.
		if i < lamp_kinds.size() and lamp_kinds[i] == "path":
			e = maxf(e, 0.62)
		ol.light_energy = e * k * (1.0 + 0.05 * sin(t * 7.0 + i * 2.0))
	for i in halos.size():
		var hk := halo_kinds[i] if i < halo_kinds.size() else ""
		# Path: no halo bloom — hanging glass + flame tip carry the source.
		halos[i].set_shader_parameter("k", 0.0 if hk == "path" else k)
	beam_pivot.visible = true
	beam_pivot.rotation.y = t * 0.55
	beam_mat.set_shader_parameter("k", k * 0.85)
	fly_mat.set_shader_parameter("k", smoothstep(0.5, 1.0, k))
	fly_mat.set_shader_parameter("time", t)
