class_name WaterReflection
extends Node
## Planar reflection for the sea: a low-res SubViewport that shares the world, rendered from the main
## camera mirrored about the water plane. The image is flipped vertically (the mirror camera keeps a
## proper rotation), so water.gdshader samples it at (x, 1 - y), offset by the wave normal. Water and the
## wade ring live on render layer 2, which this camera skips; shaders that include refl_clip.gdshaderinc
## drop whatever is below the surface while the camera is under it (only this one ever is).
## Lights are culled by camera layers too: the main camera sees the shadowed sun, this one a shadowless
## copy, so the directional shadow maps are not rendered a second time for the mirror.

const WATER_LAYER := 2
const MAIN_LIGHT_LAYER := 4
const REFL_LIGHT_LAYER := 8
const PLANE_Y := 0.0
const MAX_SIDE := 480.0     # wave distortion hides the detail anyway

var vp: SubViewport
var cam: Camera3D
var src: Camera3D
var sun: DirectionalLight3D
var sun2: DirectionalLight3D
var scale := 0.35
var enabled := true
var every := 1          # render every n-th frame (adaptive quality)
var frame := 0

func setup(main_cam: Camera3D, main_sun: DirectionalLight3D) -> void:
	src = main_cam
	sun = main_sun
	sun.layers = MAIN_LIGHT_LAYER
	src.cull_mask &= ~REFL_LIGHT_LAYER
	sun2 = DirectionalLight3D.new()
	sun2.layers = REFL_LIGHT_LAYER
	sun2.shadow_enabled = false
	sun.add_child(sun2)
	vp = SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.positional_shadow_atlas_size = 0
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.size = Vector2i(128, 128)
	add_child(vp)
	cam = Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~(WATER_LAYER | MAIN_LIGHT_LAYER)
	vp.add_child(cam)
	cam.current = true

func texture() -> Texture2D:
	return vp.get_texture()

func set_enabled(on: bool) -> void:
	enabled = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

## call after the main camera has been placed for this frame
func update() -> void:
	if not enabled:
		return
	var px := Vector2(get_window().size) * scale
	px *= minf(1.0, MAX_SIDE / maxf(px.x, px.y))
	var want := Vector2i(px.round()).max(Vector2i(48, 48))
	if vp.size != want:
		vp.size = want
	frame += 1
	if every > 1:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE if frame % every == 0 else SubViewport.UPDATE_DISABLED
	sun2.light_energy = sun.light_energy
	sun2.light_color = sun.light_color
	sun2.sky_mode = sun.sky_mode
	var t := src.global_transform
	var o := t.origin
	o.y = 2.0 * PLANE_Y - o.y
	var m := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, v.z)
	cam.global_transform = Transform3D(Basis(m.call(t.basis.x), -m.call(t.basis.y), m.call(t.basis.z)), o)
	cam.fov = src.fov
	cam.keep_aspect = src.keep_aspect
	cam.near = src.near
	cam.far = minf(src.far, 400.0)
