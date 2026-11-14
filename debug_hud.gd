class_name DebugHud
extends CanvasLayer
## On-device diagnostics when ?debug=1.
## Sits below the title/score (~y=90), left side only — no overlap with right buttons.

const HIST := 120
const WINDOW_S := 5.0
## Logical px: clear title + 最高纪录 on tall phones (safe inset + two lines).
const PANEL_Y := 156.0
const PANEL_W := 220.0

var root: Control
var panel: PanelContainer
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
var gnd_err := 0.0
var max_step := 0.0
var _proc_t0 := 0.0
var _phys_t0 := 0.0
var _last_copy := ""
var ui_font: Font


func setup(font: Font = null) -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui_font = font if font else load("res://fonts/ui.otf")
	frame_ms.resize(HIST)
	frame_t.resize(HIST)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = PanelContainer.new()
	panel.position = Vector2(8, PANEL_Y)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.1, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	lbl = Label.new()
	if ui_font:
		lbl.add_theme_font_override("font", ui_font)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.92, 1.0, 0.78, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(PANEL_W - 16, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)

	graph = Control.new()
	graph.custom_minimum_size = Vector2(PANEL_W - 16, 36)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph.draw.connect(_draw_graph)
	vbox.add_child(graph)

	copy_btn = Button.new()
	copy_btn.text = "复制数据"
	if ui_font:
		copy_btn.add_theme_font_override("font", ui_font)
	copy_btn.add_theme_font_size_override("font_size", 12)
	copy_btn.custom_minimum_size = Vector2(96, 26)
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	copy_btn.pressed.connect(_on_copy)
	vbox.add_child(copy_btn)

	copy_box = TextEdit.new()
	copy_box.visible = false
	copy_box.custom_minimum_size = Vector2(PANEL_W - 16, 120)
	copy_box.editable = false
	copy_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	if ui_font:
		copy_box.add_theme_font_override("font", ui_font)
	copy_box.add_theme_font_size_override("font_size", 10)
	vbox.add_child(copy_box)

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
	phys_ticks_frame = 0


func p_stats() -> Vector3:
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
	# Keep GPU string short so the panel stays narrow (no right-side overlap).
	var gpu := gpu_renderer
	if gpu.length() > 42:
		gpu = gpu.substr(0, 40) + "…"
	lbl.text = (
		"FPS %.0f  %.1f ms\n"
		+ "p50 %.1f  p95 %.1f  max %.1f\n"
		+ "phys/f %d  proc %.1f  phys %.1f\n"
		+ "gnd %.1fcm  maxΔ %.1fcm\n"
		+ "scale %.2f  tier %s\n"
		+ "draws %d  prim %d\n"
		+ "px %dx%d  dpr %.2f\n"
		+ "%s"
	) % [fps, last_ms, st.x, st.y, st.z, phys_ticks_frame, process_ms, physics_ms,
		gnd_err * 100.0, max_step * 100.0,
		render_scale, quality_tier, dc, prim, screen_px.x, screen_px.y, dpr, gpu]


func compact_text() -> String:
	var st := p_stats()
	var vp := get_viewport()
	var dc := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prim := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	return (
		"v32 debug\n"
		+ "fps=%.0f p50=%.1f p95=%.1f max=%.1f\n"
		+ "phys/f=%d proc_ms=%.1f phys_ms=%.1f\n"
		+ "gnd_err_cm=%.2f max_step_cm=%.2f\n"
		+ "scale=%.2f tier=%s\n"
		+ "draws=%d prim=%d px=%dx%d dpr=%.2f\n"
		+ "gpu=%s"
	) % [Engine.get_frames_per_second(), st.x, st.y, st.z, phys_ticks_frame, process_ms, physics_ms,
		gnd_err * 100.0, max_step * 100.0,
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
	graph.draw_rect(r, Color(0, 0, 0, 0.35))
	var h := r.size.y
	var w := r.size.x
	for guide in [16.7, 33.3]:
		var gy := r.size.y - clampf(guide / 40.0, 0.0, 1.0) * h
		graph.draw_line(Vector2(0, gy), Vector2(w, gy), Color(1, 1, 1, 0.18), 1.0)
	if hist_n < 2:
		return
	var pts := PackedVector2Array()
	var n := mini(hist_n, HIST)
	for k in n:
		var i := (hist_i - n + k + HIST * 4) % HIST
		var x := w * float(k) / float(maxi(n - 1, 1))
		var y := h - clampf(frame_ms[i] / 40.0, 0.0, 1.0) * h
		pts.append(Vector2(x, y))
	for i in pts.size() - 1:
		graph.draw_line(pts[i], pts[i + 1], Color(0.45, 0.95, 0.55, 0.95), 1.5)
