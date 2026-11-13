extends SceneTree
## Paint closed lids on EVERY texel touched by eye-shell verts (full UV coverage).
## Writes face_alb_{cheer,sleep,smile}.png from idle base.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await process_frame
	var b = m.boy
	b.set_idle()
	for _i in 6:
		await process_frame
	b._ensure_skin_cache()
	b._cache_eye_shell_verts()
	print("EYE_VERTS ", b._eye_shell_idxs.size())
	if b._eye_shell_idxs.is_empty():
		print("NO_EYE_VERTS"); quit(1); return
	var arrays: Array = b._body_arrays_orig
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idle_tex: Texture2D = b._load_face_tex("res://art/boy/tripo/face_alb_idle.png")
	if idle_tex == null:
		idle_tex = b._boy_albedo_tex_day
	var img: Image = idle_tex.get_image().duplicate()
	var w := img.get_width()
	var h := img.get_height()
	# Collect all eye texels + sample skin near them.
	var eye_mask := PackedByteArray(); eye_mask.resize(w * h); eye_mask.fill(0)
	var skin_acc := Color(0, 0, 0, 0)
	var skin_n := 0
	for j in b._eye_shell_idxs.size():
		var vi: int = b._eye_shell_idxs[j]
		if vi >= uvs.size():
			continue
		var uv: Vector2 = uvs[vi]
		var cx := int(uv.x * float(w))
		var cy := int(uv.y * float(h))
		# Stamp a disc around each eye vert UV so shell tris are fully covered.
		var rad := 10
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if dx * dx + dy * dy > rad * rad:
					continue
				var x := clampi(cx + dx, 0, w - 1)
				var y := clampi(cy + dy, 0, h - 1)
				eye_mask[y * w + x] = 1
		# Sample skin a bit above this UV for lid colour.
		for sy in range(cy - 18, cy - 4):
			for sx in range(cx - 4, cx + 5):
				if sx < 0 or sy < 0 or sx >= w or sy >= h:
					continue
				var c: Color = img.get_pixel(sx, sy)
				if c.r > 0.55 and c.g > 0.40 and c.b > 0.28 and c.r > c.b + 0.05:
					skin_acc += c
					skin_n += 1
	var skin := skin_acc / float(skin_n) if skin_n > 0 else Color(0.78, 0.58, 0.42)
	# Darken slightly for under-brim match.
	skin = Color(skin.r * 0.92, skin.g * 0.90, skin.b * 0.88)
	print("SKIN ", skin, " mask_texels=", _count_mask(eye_mask))
	# Build cheer / sleep from idle with lid fill + arc.
	var cheer := img.duplicate()
	var sleep := img.duplicate()
	_fill_mask(cheer, eye_mask, w, h, skin, true)
	_fill_mask(sleep, eye_mask, w, h, skin, false)
	_paint_mouth_open(cheer, b._eye_shell_idxs, uvs, w, h)
	_paint_mouth_smile(img, b._eye_shell_idxs, uvs, w, h)  # smile from idle
	var smile := img.duplicate()
	_paint_mouth_smile(smile, b._eye_shell_idxs, uvs, w, h)
	cheer.save_png("/workspace/art/boy/tripo/face_alb_cheer.png")
	sleep.save_png("/workspace/art/boy/tripo/face_alb_sleep.png")
	smile.save_png("/workspace/art/boy/tripo/face_alb_smile.png")
	# Debug: red-mark eye mask on idle
	var dbg := img.duplicate()
	for i in eye_mask.size():
		if eye_mask[i] != 0:
			var x := i % w
			var y := int(i / w)
			dbg.set_pixel(x, y, Color(1, 0, 0))
	dbg.save_png("/workspace/screenshots/v25/probe/eye_uv_mask.png")
	print("BAKE_LID_OK"); quit(0)


func _count_mask(mask: PackedByteArray) -> int:
	var n := 0
	for i in mask.size():
		if mask[i] != 0:
			n += 1
	return n


func _fill_mask(img: Image, mask: PackedByteArray, w: int, h: int, skin: Color, happy: bool) -> void:
	var lash := Color(0.18, 0.12, 0.09)
	# Compute mask bbox for arc
	var minx := w
	var maxx := 0
	var miny := h
	var maxy := 0
	for i in mask.size():
		if mask[i] == 0:
			continue
		var x := i % w
		var y := int(i / w)
		minx = mini(minx, x); maxx = maxi(maxx, x)
		miny = mini(miny, y); maxy = maxi(maxy, y)
		var shade := 0.90 + 0.10 * (1.0 - absf((float(y) - float(miny + maxy) * 0.5) / maxf(1.0, float(maxy - miny))))
		var c := Color(skin.r * shade, skin.g * shade, skin.b * shade)
		# Preserve dark brow pixels
		var cur: Color = img.get_pixel(x, y)
		if cur.r < 0.35 and cur.g < 0.28 and cur.b < 0.25 and y < (miny + maxy) * 0.5 - 4:
			continue
		img.set_pixel(x, y, c)
	# Split into two eye blobs by y midpoint for arcs (atlas stacks L/R vertically).
	var midy := (miny + maxy) / 2
	_arc_on_band(img, mask, w, h, minx, maxx, miny, midy, lash, happy)
	_arc_on_band(img, mask, w, h, minx, maxx, midy, maxy, lash, happy)


func _arc_on_band(img: Image, mask: PackedByteArray, w: int, h: int, x0: int, x1: int, y0: int, y1: int, lash: Color, happy: bool) -> void:
	var cx := 0.5 * float(x0 + x1)
	var cy := 0.5 * float(y0 + y1)
	var rx := 0.42 * float(x1 - x0)
	var ry := 0.35 * float(y1 - y0)
	for t in 48:
		var u := float(t) / 47.0
		var x := int(cx + (u - 0.5) * 2.0 * rx)
		var y: int
		if happy:
			y = int(cy - sin(u * PI) * ry)
		else:
			y = int(cy + sin(u * PI) * ry * 0.55)
		for o in range(-1, 2):
			for p in range(-1, 2):
				var xx := clampi(x + o, 0, w - 1)
				var yy := clampi(y + p, 0, h - 1)
				if mask[yy * w + xx] == 0:
					continue
				img.set_pixel(xx, yy, lash)


func _paint_mouth_open(img: Image, idxs: PackedInt32Array, uvs: PackedVector2Array, w: int, h: int) -> void:
	# Mouth below the average eye UV.
	var sum := Vector2.ZERO
	var n := 0
	for j in idxs.size():
		var vi: int = idxs[j]
		if vi >= uvs.size():
			continue
		sum += uvs[vi]
		n += 1
	if n == 0:
		return
	var mid: Vector2 = sum / float(n)
	var mcx := int(mid.x * float(w))
	var mcy := int((mid.y + 0.045) * float(h))
	var mrx := 38
	var mry := 28
	for y in range(mcy - mry, mcy + mry + 1):
		for x in range(mcx - mrx, mcx + mrx + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var nx := float(x - mcx) / float(mrx)
			var ny := float(y - mcy) / float(mry)
			if nx * nx + ny * ny > 1.0:
				continue
			var cur: Color = img.get_pixel(x, y)
			if not (cur.r > 0.55 and cur.g > 0.40 and cur.b > 0.28 and cur.r > cur.b):
				continue
			if ny < -0.2:
				img.set_pixel(x, y, Color(0.96, 0.94, 0.92))
			elif ny > 0.25:
				img.set_pixel(x, y, Color(0.80, 0.38, 0.42))
			else:
				img.set_pixel(x, y, Color(0.18, 0.08, 0.08))


func _paint_mouth_smile(img: Image, idxs: PackedInt32Array, uvs: PackedVector2Array, w: int, h: int) -> void:
	var sum := Vector2.ZERO
	var n := 0
	for j in idxs.size():
		var vi: int = idxs[j]
		if vi >= uvs.size():
			continue
		sum += uvs[vi]
		n += 1
	if n == 0:
		return
	var mid: Vector2 = sum / float(n)
	var mcx := int(mid.x * float(w))
	var mcy := int((mid.y + 0.04) * float(h))
	var mrx := 42.0
	var mry := 14.0
	var col := Color(0.32, 0.17, 0.13)
	for t in 56:
		var u := float(t) / 55.0
		var x := int(mcx + (u - 0.5) * 2.0 * mrx)
		var y := int(mcy + sin(u * PI) * mry)
		for o in range(-1, 2):
			for p in range(-1, 2):
				var xx := clampi(x + o, 0, w - 1)
				var yy := clampi(y + p, 0, h - 1)
				var cur: Color = img.get_pixel(xx, yy)
				if cur.r > 0.55 and cur.g > 0.40 and cur.b > 0.28:
					img.set_pixel(xx, yy, col)
