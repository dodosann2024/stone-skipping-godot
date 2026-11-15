extends RefCounted
## HUD construction and layout. Same behaviour as the former main.gd methods.

var m

func bind(host) -> void:
	m = host

func _label(size: int, col = Color.WHITE) -> Label:
	var l = Label.new()
	l.add_theme_font_override("font", m.ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.18, 0.32, 0.9))
	l.add_theme_constant_override("outline_size", 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ------------------------------------------------------------------ UI

func _btn(text: String, size: int, primary = false) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_override("font", m.ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var sb = StyleBoxFlat.new()
		if primary:
			sb.bg_color = Color(1.0, 0.82, 0.3, 0.95) if st_name != "pressed" else Color(1.0, 0.92, 0.6, 1.0)
			sb.border_color = Color(0.55, 0.3, 0.05)
		else:
			# Slightly less opaque — over the lighthouse climb the old 0.82 white pills
			# fused with the tower into one "ghost panel" on iPhone Safari.
			sb.bg_color = Color(1, 1, 1, 0.72) if st_name != "pressed" else Color(0.85, 0.95, 1, 0.90)
			sb.border_color = Color(0.1, 0.45, 0.65)
		sb.set_corner_radius_all(40)
		sb.set_border_width_all(3)
		sb.content_margin_left = 18; sb.content_margin_right = 18
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(st_name, sb)
	var fc = Color(0.45, 0.2, 0.02) if primary else Color(0.05, 0.35, 0.55)
	for cn in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, fc)
	return b

func _build_ui() -> void:
	var layer = CanvasLayer.new()
	m.add_child(layer)
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	m.ui_root = root

	# joystick: the bottom-left part of the screen (explore mode)
	m.joy = InputJoystick.new()
	m.joy.anchor_left = 0.0; m.joy.anchor_right = 0.5; m.joy.anchor_top = 0.55; m.joy.anchor_bottom = 1.0
	root.add_child(m.joy)

	m.top_box = VBoxContainer.new()
	m.top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	m.top_box.offset_left = 18; m.top_box.offset_top = 12; m.top_box.offset_right = -190
	m.top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.top_box.add_theme_constant_override("separation", 0)
	root.add_child(m.top_box)
	m.lbl_title = _label(26, Color(1, 0.95, 0.7))
	m.lbl_title.text = "海岛打水漂"
	m.top_box.add_child(m.lbl_title)
	m.lbl_stats = _label(32)
	m.top_box.add_child(m.lbl_stats)
	m.lbl_best = _label(22, Color(0.9, 0.97, 1))
	m.top_box.add_child(m.lbl_best)

	m.throw_pad = ThrowPad.new()
	m.throw_pad.font = m.ui_font
	m.throw_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.throw_pad.visible = false
	root.add_child(m.throw_pad)
	m.el_slider = _angle_slider("仰角", "el", m.EL_MIN, m.EL_MAX, m.aim_pitch, Vector2(0, 10))
	m.tilt_slider = _angle_slider("倾角", "tilt", 0.0, m.TILT_MAX, m.aim_tilt, Vector2(15, 25))
	m.el_slider.changed.connect(func(v: float) -> void: m.aim_pitch = v)
	m.tilt_slider.changed.connect(func(v: float) -> void: m.aim_tilt = v)

	m.right_box = VBoxContainer.new()
	m.right_box.anchor_left = 1.0; m.right_box.anchor_right = 1.0
	m.right_box.offset_left = -176; m.right_box.offset_right = -14; m.right_box.offset_top = 14
	m.right_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.right_box.add_theme_constant_override("separation", 10)
	root.add_child(m.right_box)
	m.view_btn = _btn("观景", 26)
	m.view_btn.custom_minimum_size = Vector2(162, 62)
	m.view_btn.pressed.connect(m._toggle_view)
	m.right_box.add_child(m.view_btn)
	m.cam_mode_btn = _btn("固定视角", 22)
	m.cam_mode_btn.custom_minimum_size = Vector2(162, 50)
	m.cam_mode_btn.pressed.connect(m._toggle_cam_fixed)
	m.right_box.add_child(m.cam_mode_btn)
	var zoom_row = HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 8)
	zoom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.right_box.add_child(zoom_row)
	m.zoom_out_btn = _btn("−", 28)
	m.zoom_out_btn.custom_minimum_size = Vector2(74, 48)
	m.zoom_out_btn.pressed.connect(func() -> void: m._nudge_zoom(1.0 / 0.85))
	zoom_row.add_child(m.zoom_out_btn)
	m.zoom_in_btn = _btn("+", 28)
	m.zoom_in_btn.custom_minimum_size = Vector2(74, 48)
	m.zoom_in_btn.pressed.connect(func() -> void: m._nudge_zoom(0.85))
	zoom_row.add_child(m.zoom_in_btn)
	m.sound_btn = _btn("声音：开", 22)
	m.sound_btn.custom_minimum_size = Vector2(162, 50)
	m.sound_btn.pressed.connect(m._toggle_sound)
	m.right_box.add_child(m.sound_btn)
	m.night_btn = _btn("夜晚", 22)
	m.night_btn.custom_minimum_size = Vector2(162, 50)
	m.night_btn.pressed.connect(m._toggle_night)
	m.right_box.add_child(m.night_btn)
	m.stance_btn = _btn("姿势：站立", 22)
	m.stance_btn.custom_minimum_size = Vector2(162, 56)
	m.stance_btn.pressed.connect(m._toggle_stance)
	m.right_box.add_child(m.stance_btn)
	m.leave_btn = _btn("离开码头", 22)
	m.leave_btn.custom_minimum_size = Vector2(162, 56)
	m.leave_btn.pressed.connect(m._leave_throw)
	m.right_box.add_child(m.leave_btn)

	# context action (打水漂 / 睡觉 / 晒太阳 / 起来), bottom right
	m.action_btn = _btn("打水漂", 34, true)
	m.action_btn.anchor_left = 1.0; m.action_btn.anchor_right = 1.0; m.action_btn.anchor_top = 1.0; m.action_btn.anchor_bottom = 1.0
	m.action_btn.offset_left = -214; m.action_btn.offset_right = -24; m.action_btn.offset_top = -134; m.action_btn.offset_bottom = -40
	m.action_btn.pressed.connect(m._on_action)
	root.add_child(m.action_btn)
	m.lie_btn = _btn("躺下", 30, true)
	m.lie_btn.anchor_left = 1.0; m.lie_btn.anchor_right = 1.0; m.lie_btn.anchor_top = 1.0; m.lie_btn.anchor_bottom = 1.0
	m.lie_btn.pressed.connect(m._lie_down)
	root.add_child(m.lie_btn)

	m.bottom_box = VBoxContainer.new()
	m.bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	m.bottom_box.offset_left = 18; m.bottom_box.offset_right = -18; m.bottom_box.offset_bottom = -14
	m.bottom_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.bottom_box.alignment = BoxContainer.ALIGNMENT_END
	m.bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m.bottom_box)
	m.power_box = VBoxContainer.new()
	m.power_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.bottom_box.add_child(m.power_box)
	m.lbl_aim = _label(28)
	m.lbl_aim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.power_box.add_child(m.lbl_aim)
	m.power_bar = ProgressBar.new()
	m.power_bar.custom_minimum_size = Vector2(0, 26)
	m.power_bar.show_percentage = false
	m.power_bar.max_value = 1.0
	m.power_bar.step = 0.001
	m.power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0.15, 0.3, 0.5)
	bg.set_corner_radius_all(13)
	var fg = StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.8, 0.25)
	fg.set_corner_radius_all(13)
	m.power_bar.add_theme_stylebox_override("background", bg)
	m.power_bar.add_theme_stylebox_override("fill", fg)
	m.power_box.add_child(m.power_bar)
	m.power_box.visible = false
	m.lbl_hint = _label(24, Color(1, 1, 1, 0.96))
	m.lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.bottom_box.add_child(m.lbl_hint)

	m.lbl_toast = _label(44, Color(1, 0.95, 0.55))
	m.lbl_toast.anchor_left = 0.0; m.lbl_toast.anchor_right = 1.0
	m.lbl_toast.anchor_top = 0.24; m.lbl_toast.anchor_bottom = 0.24
	m.lbl_toast.offset_left = 10; m.lbl_toast.offset_right = -10
	m.lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.lbl_toast.add_theme_constant_override("outline_size", 12)
	root.add_child(m.lbl_toast)

	# "no sound?" tip (web only), dismissible
	m.tip_box = PanelContainer.new()
	var tsb = StyleBoxFlat.new()
	tsb.bg_color = Color(0.02, 0.15, 0.28, 0.82)
	tsb.set_corner_radius_all(18)
	tsb.content_margin_left = 16; tsb.content_margin_right = 8; tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	m.tip_box.add_theme_stylebox_override("panel", tsb)
	m.tip_box.anchor_left = 0.5; m.tip_box.anchor_right = 0.5; m.tip_box.anchor_top = 0.0
	m.tip_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m.tip_box.offset_top = 150
	var th = HBoxContainer.new()
	m.tip_box.add_child(th)
	var tl = _label(22, Color(1, 0.95, 0.75))
	tl.text = "没声音？请关闭 iPhone 侧边静音开关并调高音量"
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(260, 0)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var tx = _btn("×", 26)
	tx.custom_minimum_size = Vector2(52, 52)
	tx.pressed.connect(func() -> void: m.tip_box.visible = false)
	th.add_child(tx)
	m.tip_box.visible = false
	root.add_child(m.tip_box)

	# iOS / browsers only allow sound after a tap: a "tap to start" curtain unlocks the audio
	if not m.audio_started:
		m.start_overlay = ColorRect.new()
		(m.start_overlay as ColorRect).color = Color(0.02, 0.12, 0.22, 0.55)
		m.start_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		m.start_overlay.gui_input.connect(m._on_start_input)
		root.add_child(m.start_overlay)
		var big = _label(64, Color(1, 0.95, 0.6))
		big.text = "点击开始"
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		big.set_anchors_preset(Control.PRESET_FULL_RECT)
		big.offset_bottom = -60
		m.start_overlay.add_child(big)
		var small = _label(26)
		small.text = "轻点屏幕开始，开启海浪声\niPhone 请先关闭侧边静音开关、调高音量"
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		small.set_anchors_preset(Control.PRESET_FULL_RECT)
		small.offset_top = 110; small.offset_left = 16; small.offset_right = -16
		m.start_overlay.add_child(small)
	m.get_viewport().size_changed.connect(_layout_ui)
	m.bottom_box.resized.connect(_fit_action)
	m.right_box.resized.connect(_layout_ui)
	_layout_ui()

func _angle_slider(t: String, k: String, lo: float, hi: float, v: float, band: Vector2) -> AngleSlider:
	var s = AngleSlider.new()
	s.title = t
	s.kind = k
	s.vmin = lo
	s.vmax = hi
	s.value = v
	s.band = band
	s.font = m.ui_font
	s.anchor_left = 1.0; s.anchor_right = 1.0; s.anchor_top = 1.0; s.anchor_bottom = 1.0
	s.visible = false
	m.ui_root.add_child(s)
	return s

func _tall() -> bool:
	var vs = m.get_viewport().get_visible_rect().size
	return vs.x < vs.y

## Screen insets (notch / Dynamic Island, home indicator, rounded corners) in UI units: top, right,
## bottom, left. The page asks for viewport-fit=cover and reports env(safe-area-inset-*) (export
## head_include); `--safe=t,r,b,l` (CSS px) fakes a phone's insets for desktop checks.

func _read_safe_area() -> bool:
	var raw = ""
	var css_h = float(DisplayServer.window_get_size().y)
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("window.__safeArea ? window.__safeArea() : ''", true))
	else:
		for a0 in OS.get_cmdline_user_args():
			if a0.begins_with("--safe="):
				raw = a0.substr(7) + ",0," + str(css_h)
	if raw == m.safe_css:
		return false
	m.safe_css = raw
	var v = raw.split(",")
	if v.size() < 6 or float(v[5]) <= 0.0:
		m.safe = Vector4.ZERO
		return true
	var k = m.get_viewport().get_visible_rect().size.y / float(v[5])
	m.safe = Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3])) * k
	return true

## The context buttons sit bottom right; on a tall screen the hint spans the width, so they stand on top of it.

func _fit_action() -> void:
	var tall = _tall()
	var base = 56.0 if tall else 36.0
	if tall and is_instance_valid(m.bottom_box) and m.lbl_hint.text != "":
		base = maxf(base, 14.0 + m.bottom_box.size.y + 14.0)
	m.action_btn.offset_right = -24 - m.safe.y
	m.action_btn.offset_left = m.action_btn.offset_right - 190
	m.action_btn.offset_bottom = -base - m.safe.z
	m.action_btn.offset_top = m.action_btn.offset_bottom - 94
	m.lie_btn.offset_left = m.action_btn.offset_left; m.lie_btn.offset_right = m.action_btn.offset_right
	m.lie_btn.offset_bottom = m.action_btn.offset_top - 16
	m.lie_btn.offset_top = m.lie_btn.offset_bottom - 80

## portrait: smaller title, action button a bit higher; landscape: roomier. Everything anchored to an
## edge keeps clear of the safe-area insets.

func _layout_ui() -> void:
	if not is_instance_valid(m.action_btn):
		return
	_read_safe_area()
	var st = m.safe.x
	var sr = m.safe.y
	var sb = m.safe.z
	var sl = m.safe.w
	var tall = _tall()
	m.lbl_title.add_theme_font_size_override("font_size", 24 if tall else 26)
	m.lbl_stats.add_theme_font_size_override("font_size", 28 if tall else 32)
	m.top_box.offset_left = 18 + sl
	m.top_box.offset_top = 12 + st
	m.top_box.offset_right = -184 - sr
	m.right_box.offset_top = 14 + st
	m.right_box.offset_right = -14 - sr
	m.right_box.offset_left = m.right_box.offset_right - 162
	_fit_action()
	m.joy.anchor_top = 0.6 if tall else 0.45
	m.joy.anchor_right = 0.62 if tall else 0.45
	m.joy.offset_left = sl
	m.joy.offset_bottom = -sb
	m.joy.radius = 66.0 if tall else 72.0
	m.joy.lift = 62.0 if tall else 0.0
	m.bottom_box.offset_left = 18 + sl
	m.bottom_box.offset_right = -18 - sr
	m.bottom_box.offset_bottom = -14 - sb
	# (portrait: the tip spans most of the 720 units across, so it starts below the button column)
	m.tip_box.offset_top = maxf((170.0 if tall else 120.0) + st, m.right_box.offset_top + m.right_box.size.y + 16.0) if tall else 120.0 + st
	# throw mode: the two angle sliders bottom right, the stone pad bottom centre (both above the hint)
	var sw = 92.0
	var sh = 320.0 if tall else 250.0
	var lift = (150.0 if tall else 112.0) + sb
	for i in 2:
		var s: AngleSlider = m.tilt_slider if i == 0 else m.el_slider
		s.offset_right = -14.0 - sr - i * (sw + 12.0)
		s.offset_left = s.offset_right - sw
		s.offset_bottom = -lift
		s.offset_top = -lift - sh
	var vs = m.get_viewport().get_visible_rect().size
	m.throw_pad.pad_r = 54.0 if tall else 50.0
	m.throw_pad.pad_c = Vector2((vs.x + sl - sr) * 0.5, vs.y - lift - m.throw_pad.pad_r + (24.0 if tall else 4.0))
	m.throw_pad.queue_redraw()

func _toast(t: String, dur = 1.4) -> void:
	m.lbl_toast.text = t
	m.lbl_toast.modulate.a = 1.0
	m.toast_timer = dur

func _update_ui() -> void:
	var throw_mode = m.mode == m.Mode.THROW
	m.lbl_stats.visible = throw_mode
	m.lbl_best.visible = throw_mode or m.mode == m.Mode.EXPLORE
	m.lbl_stats.text = "弹跳 %d 次   距离 %.1f 米" % [m.skips, m.throw_dist]
	m.lbl_best.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [m.best_skips, m.best_dist]
	m.view_btn.text = "返回" if m.mode == m.Mode.VIEW else "观景"
	m.view_btn.visible = (m.mode == m.Mode.EXPLORE) or m.mode == m.Mode.VIEW or (throw_mode and m.state == m.State.READY)
	if m.cam_mode_btn:
		# Label is the mode you switch TO (same pattern as 白天/夜晚).
		m.cam_mode_btn.text = "跟随视角" if m.cam_fixed else "固定视角"
		m.cam_mode_btn.visible = m.mode == m.Mode.EXPLORE or m.mode == m.Mode.REST or m.mode == m.Mode.VIEW
	if m.zoom_in_btn and m.zoom_out_btn:
		var show_zoom = m.cam_fixed and (m.mode == m.Mode.EXPLORE or m.mode == m.Mode.REST or m.mode == m.Mode.VIEW)
		m.zoom_in_btn.get_parent().visible = show_zoom
	m.sound_btn.text = "声音：关" if m.muted else "声音：开"
	m.night_btn.text = "白天" if m.night_on else "夜晚"
	m.stance_btn.visible = throw_mode and m.state == m.State.READY
	m.stance_btn.text = "姿势：半蹲" if m.boy.stance == "crouch" else "姿势：站立"
	m.leave_btn.visible = throw_mode and m.state == m.State.READY
	m.joy.visible = m.mode == m.Mode.EXPLORE
	if m.mode != m.Mode.EXPLORE:
		m.joy._end()
	var act = ""
	if m.mode == m.Mode.EXPLORE:
		act = {"throw": "打水漂", "sleep": "睡觉", "sun": "晒太阳", "seat": "坐下"}.get(m.action_kind, "")
	elif m.mode == m.Mode.REST and m.rest_phase == 4:
		act = "起来"
	m.action_btn.visible = act != ""
	m.action_btn.text = act
	m.lie_btn.visible = m.mode == m.Mode.REST and m.rest_phase == 4 and m.rest_kind == "seat" and not m.seat_lying \
		and m.seat_i >= 0 and m.island.seats[m.seat_i]["can_lie"]
	match m.mode:
		m.Mode.VIEW:
			m.lbl_hint.text = "观景：单指拖动 360° 旋转，双指捏合缩放（电脑：拖鼠标 / 滚轮）\n点右上角「返回」继续玩"
		m.Mode.EXPLORE:
			var h = "左下摇杆走路，推到底就跑（电脑：WASD/方向键，Shift 跑）· 拖动屏幕转视角"
			match m.action_kind:
				"throw":
					h = "到码头尽头了！点「打水漂」开始扔石子"
				"sleep":
					h = "椰子树间的吊床，点「睡觉」躺上去打个盹"
				"sun":
					h = "沙滩毛巾，点「晒太阳」躺下晒一会儿"
				"seat":
					h = m.island.seats[m.seat_i]["hint"]
				_:
					if _tall():
						h = "左下摇杆走路，推到底就跑 · 拖屏幕转视角\n打水漂要去码头尽头"
					else:
						h += "\n打水漂要走到码头尽头；吊床可以睡觉，沙滩毛巾可以晒太阳，长椅和篝火边可以坐"
			m.lbl_hint.text = h
		m.Mode.REST:
			var rh = {"sleep": "呼……睡着了 · 轻点屏幕或「起来」叫醒他", "sun": "晒太阳中 · 轻点屏幕或「起来」站起来", "seat": "坐着歇一会儿 · 轻点屏幕或「起来」站起来",
				"seatcan": "坐着歇一会儿 · 点「躺下」翘腿躺一会儿，轻点屏幕或「起来」站起来",
				"seatlie": "草帽盖脸，翘着腿躺着 · 轻点屏幕或「起来」起身"}
			var rk = m.rest_kind
			if m.rest_kind == "seat" and m.seat_lying:
				rk = "seatlie"
			elif m.rest_kind == "seat" and m.island.seats[m.seat_i]["can_lie"]:
				rk = "seatcan"
			m.lbl_hint.text = rh[rk] if m.rest_phase == 4 else ""
		_:
			match m.state:
				m.State.READY:
					if m.last_tip != "":
						m.lbl_hint.text = m.last_tip
					elif _tall():
						m.lbl_hint.text = "按住石头往海面划：方向 = 瞄准，越长越用力\n松手时顺势一甩 = 旋转 · 右边调仰角和倾角"
					else:
						m.lbl_hint.text = "按住石头往海面划：方向 = 瞄准，越长越用力，松手时顺势一甩 = 旋转\n右边调出手仰角和石头倾角（20° 最好）· 键盘：←→ 瞄准  ↑↓ 仰角  Q/E 倾角  按住空格蓄力"
				m.State.AIMING:
					m.lbl_hint.text = {"swipe": "松手扔出 · 往回拉取消", "key": "看准力度条，松开空格投出！"}.get(m.aim_src, "看准力度条，松手投出！")
				_:
					m.lbl_hint.text = ""
	m.power_box.visible = m.state == m.State.AIMING and throw_mode
	m.power_bar.visible = m.aim_src != "swipe"

