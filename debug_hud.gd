class_name DebugHud
extends CanvasLayer
## On-device diagnostics when ?debug=1. Top-left FPS + frame-time graph + copyable stats.

const HIST := 120
const WINDOW_S := 5.0

var root: Control
var lbl: Label
var graph: Control
var copy_btn: Button
var copy_box: TextEdit
var frame_ms := PackedFloat32Array()
var frame_t := PackedFloat32Array()
var hist_i := 0
var hist_n := 0
var phys_ticks_frame := 0
var process_ms := 0.0
var physics_ms := 0.0
var render_scale := 1.0
var quality_tier := ""
var gpu_renderer := ""
var dpr := 1.0
var screen_px := Vector2i.ZERO
var _proc_t0 := 0.0
var _phys_t0 := 0.0
var _last_copy := ""


func setup() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame_ms.resize(HIST)
	frame_t.resize(HIST)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	lbl = Label.new()
	lbl.position = Vector2(8, 8)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 0.75, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)
	graph = Control.new()
	graph.position = Vector2(8, 168)
	graph.custom_minimum_size = Vector2(160, 48)
	graph.size = Vector2(160, 48)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph.draw.connect(_draw_graph)
	root.add_child(graph)
	copy_btn = Button.new()
	copy_btn.text = "复制数据"
	copy_btn.position = Vector2(8, 222)
	copy_btn.custom_minimum_size = Vector2(88, 28)
	copy_btn.add_theme_font_size_override("font_size", 13)
	copy_btn.pressed.connect(_on_copy)
	root.add_child(copy_btn)
	copy_box = TextEdit.new()
	copy_box.visible = false
	copy_box.position = Vector2(8, 256)
	copy_box.size = Vector2(300, 160)
	copy_box.editable = false
	copy_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	copy_box.add_theme_font_size_override("font_size", 11)
	root.add_child(copy_box)
	_probe_gpu()


func _probe_gpu() -> void:
	if not OS.has_feature("web"):
		gpu_renderer = RenderingServer.get_video_adapter_name()
		return
	var s := str(JavaScriptBridge.eval(
		"(function(){try{var c=document.createElement('canvas');var g=c.getContext('webgl')||c.getContext('experimental-webgl');if(!g)return 'no-webgl';var d=g.getExtension('WEBGL_debug_renderer_info');if(!d)return g.getParameter(g.RENDERER)||'?';return String(g.getParameter(d.UNMASKED_RENDERER_WEBGL)||'?');}catch(e){return String(e);}})()",
		true))
	gpu_renderer = s
	dpr = float(str(JavaScriptBridge.eval("window.devicePixelRatio||1", true)))


func begin_process() -> void:
	_proc_t0 = Time.get_ticks_usec() * 1e-3


func end_process() -> void:
	process_ms = Time.get_ticks_usec() * 1e-3 - _proc_t0


func begin_physics() -> void:
	_phys_t0 = Time.get_ticks_usec() * 1e-3


func end_physics() -> void:
	physics_ms = Time.get_ticks_usec() * 1e-3 - _phys_t0
	phys_ticks_frame += 1


func note_frame(delta: float, scale_3d: float, tier: String) -> void:
	render_scale = scale_3d
	quality_tier = tier
	var ms := delta * 1000.0
	var now := Time.get_ticks_msec() * 0.001
	frame_ms[hist_i] = ms
	frame_t[hist_i] = now
	hist_i = (hist_i + 1) % HIST
	hist_n = mini(hist_n + 1, HIST)
	var vp := get_viewport().get_visible_rect().size
	screen_px = Vector2i(int(vp.x), int(vp.y))
	_refresh_label()
	graph.queue_redraw()
	# Reset physics-tick counter after the display frame samples it.
	phys_ticks_frame = 0


func p_stats() -> Vector3:
	## Returns p50, p95, max over last WINDOW_S seconds.
	var samples: Array[float] = []
	var now := Time.get_ticks_msec() * 0.001
	var n := hist_n
	for k in n:
		var i := (hist_i - 1 - k + HIST * 4) % HIST
		if now - frame_t[i] > WINDOW_S:
			break
		samples.append(frame_ms[i])
	if samples.is_empty():
		return Vector3.ZERO
	samples.sort()
	var p50 := samples[int((samples.size() - 1) * 0.50)]
	var p95 := samples[int((samples.size() - 1) * 0.95)]
	var mx := samples[samples.size() - 1]
	return Vector3(p50, p95, mx)


func _refresh_label() -> void:
	var st := p_stats()
	var fps := Engine.get_frames_per_second()
	var last_ms := frame_ms[(hist_i - 1 + HIST) % HIST] if hist_n > 0 else 0.0
	var vp := get_viewport()
	var dc := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prim := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	lbl.text = (
		"FPS %.0f  %.1f ms\n"
		+ "p50 %.1f  p95 %.1f  max %.1f\n"
		+ "phys/f %d  proc %.1f  phys %.1f\n"
		+ "scale %.2f  tier %s\n"
		+ "draws %d  prim %d\n"
		+ "px %dx%d  dpr %.2f\n"
		+ "%s"
	) % [fps, last_ms, st.x, st.y, st.z, phys_ticks_frame, process_ms, physics_ms,
		render_scale, quality_tier, dc, prim, screen_px.x, screen_px.y, dpr, gpu_renderer]


func compact_text() -> String:
	var st := p_stats()
	var vp := get_viewport()
	var dc := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prim := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	return (
		"v30 debug\n"
		+ "fps=%.0f p50=%.1f p95=%.1f max=%.1f\n"
		+ "phys/f=%d proc_ms=%.1f phys_ms=%.1f\n"
		+ "scale=%.2f tier=%s refl?\n"
		+ "draws=%d prim=%d px=%dx%d dpr=%.2f\n"
		+ "gpu=%s"
	) % [Engine.get_frames_per_second(), st.x, st.y, st.z, phys_ticks_frame, process_ms, physics_ms,
		render_scale, quality_tier, dc, prim, screen_px.x, screen_px.y, dpr, gpu_renderer]


func _on_copy() -> void:
	_last_copy = compact_text()
	copy_box.text = _last_copy
	copy_box.visible = true
	if OS.has_feature("web"):
		var esc := _last_copy.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
		JavaScriptBridge.eval("try{navigator.clipboard.writeText('%s')}catch(e){}" % esc, true)
	else:
		DisplayServer.clipboard_set(_last_copy)


func _draw_graph() -> void:
	var r := Rect2(Vector2.ZERO, graph.size)
	graph.draw_rect(r, Color(0, 0, 0, 0.45))
	# 16.7 ms / 33 ms guides
	var h := r.size.y
	var w := r.size.x
	for guide in [16.7, 33.3]:
		var gy := r.size.y - clampf(guide / 40.0, 0.0, 1.0) * h
		graph.draw_line(Vector2(0, gy), Vector2(w, gy), Color(1, 1, 1, 0.2), 1.0)
	if hist_n < 2:
		return
	var pts := PackedVector2Array()
	var n := mini(hist_n, HIST)
	for k in n:
		var i := (hist_i - n + k + HIST * 4) % HIST
		var x := w * float(k) / float(n - 1)
		var y := h - clampf(frame_ms[i] / 40.0, 0.0, 1.0) * h
		pts.append(Vector2(x, y))
	for i in pts.size() - 1:
		graph.draw_line(pts[i], pts[i + 1], Color(0.45, 0.95, 0.55, 0.95), 1.5)
