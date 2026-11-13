"""Paint flat-eye expression albedos onto the Tripo UV atlas.

CRITICAL: paints are clipped to a face-skin UV mask rasterized from Head-bone
face-forward triangles whose albedo is peach (not hair/hat). This stops
mouth/eye paints bleeding into mirrored hair islands under the brim.
"""
import json
import os
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_dilation, binary_erosion, label, gaussian_filter

SRC_GLB = "/workspace/boy/boy.glb"
OUT_DIR = "/workspace/art/boy/flateyes"
TRIPO_DIR = "/workspace/art/boy/tripo"
BASE = os.path.join(OUT_DIR, "basecolor.png")


def load_glb(path):
	with open(path, "rb") as f:
		f.read(12)
		js = None
		bindata = None
		while True:
			h = f.read(8)
			if not h:
				break
			clen, ctype = struct.unpack("<I4s", h)
			data = f.read(clen)
			if ctype == b"JSON":
				js = json.loads(data)
			elif ctype == b"BIN\x00":
				bindata = data
	return js, bindata


def get_acc(js, bindata, i):
	a = js["accessors"][i]
	bv = js["bufferViews"][a["bufferView"]]
	off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
	comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
	dtype = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
	raw = np.frombuffer(bindata, dtype=dtype, count=a["count"] * comps, offset=off)
	return raw.reshape(a["count"], comps) if comps > 1 else raw


def extract_basecolor(js, bindata, out_path):
	for img in js.get("images", []):
		name = (img.get("name") or "").lower()
		if "basecolor" in name or "albedo" in name:
			bv = js["bufferViews"][img["bufferView"]]
			start = bv.get("byteOffset", 0)
			open(out_path, "wb").write(bindata[start : start + bv["byteLength"]])
			return
	raise SystemExit("no basecolor")


def _is_peach(c):
	"""Skin texel — exclude dark hair, straw, red vest, yellow shirt."""
	r, g, b = float(c[0]), float(c[1]), float(c[2])
	if r < 145 or g < 95:
		return False
	if r <= g + 8:  # not warm enough
		return False
	if b > r - 15:  # too grey/cool
		return False
	# Reject saturated yellow/straw (hat)
	if r > 200 and g > 160 and b < 100 and (r - b) > 90:
		return False
	# Reject deep brown hair
	if r < 120 and g < 80 and b < 60:
		return False
	return True


def build_face_skin_mask(js, bindata, arr):
	"""Rasterize Head-bone face-forward peach triangles → face UV mask (excludes hair)."""
	H, W = arr.shape[:2]
	p = js["meshes"][0]["primitives"][0]
	pos = get_acc(js, bindata, p["attributes"]["POSITION"]).astype(np.float32)
	uv = get_acc(js, bindata, p["attributes"]["TEXCOORD_0"]).astype(np.float32)
	joints = get_acc(js, bindata, p["attributes"]["JOINTS_0"])
	weights = get_acc(js, bindata, p["attributes"]["WEIGHTS_0"]).astype(np.float32)
	idxs = get_acc(js, bindata, p["indices"]).astype(np.int64)
	skin = js["skins"][0]
	bone_names = [js["nodes"][ni].get("name", "") for ni in skin["joints"]]
	head_i = bone_names.index("mixamorig:Head")
	prim = joints[np.arange(len(joints)), weights.argmax(axis=1)]
	head = prim == head_i

	px = np.clip((uv[:, 0] * W).astype(int), 0, W - 1)
	py = np.clip((uv[:, 1] * H).astype(int), 0, H - 1)
	cols = arr[py, px]
	r, g, b = cols[:, 0], cols[:, 1], cols[:, 2]
	peach_v = (r > 145) & (g > 95) & (r > g + 8) & (b < r - 15) & ~((r > 200) & (g > 160) & (b < 100))
	y_mid = float(np.percentile(pos[head, 1], 55)) if head.any() else 0.75
	face_v = head & (pos[:, 2] > 0.02) & (pos[:, 1] < y_mid + 0.12) & peach_v

	# Rasterize via PIL (fast) into a luminance mask image
	mask_img = Image.new("L", (W, H), 0)
	draw = ImageDraw.Draw(mask_img)
	tris = idxs.reshape(-1, 3)
	kept = 0
	for a, b, c in tris:
		votes = int(face_v[a]) + int(face_v[b]) + int(face_v[c])
		if votes < 2:
			continue
		poly = [
			(float(uv[a, 0]) * W, float(uv[a, 1]) * H),
			(float(uv[b, 0]) * W, float(uv[b, 1]) * H),
			(float(uv[c, 0]) * W, float(uv[c, 1]) * H),
		]
		draw.polygon(poly, fill=255)
		kept += 1
	mask = np.asarray(mask_img) > 0
	mask = binary_dilation(mask, iterations=2)
	mask = binary_erosion(mask, iterations=1)
	hair = (arr[:, :, 0] < 110) & (arr[:, :, 1] < 80) & (arr[:, :, 2] < 60)
	mask &= ~hair
	straw = (arr[:, :, 0] > 190) & (arr[:, :, 1] > 150) & (arr[:, :, 2] < 110) & ((arr[:, :, 0] - arr[:, :, 2]) > 80)
	mask &= ~straw
	print("face_mask tris", kept, "texels", int(mask.sum()), f"({100.0 * mask.mean():.2f}%)")
	return mask, pos, uv, head, face_v, px, py

def find_eye_islands(arr, face_mask, pos, head, px, py):
	"""Eye sites near the face-skin mask (sclera may sit just outside peach texels)."""
	H, W = arr.shape[:2]
	# Dilate face mask so white sclera / iris next to peach cheeks still count
	near_face = binary_dilation(face_mask, iterations=18)
	hi = (arr[:, :, 0] > 200) & (arr[:, :, 1] > 200) & (arr[:, :, 2] > 185)
	brown = (
		(arr[:, :, 0] > 35)
		& (arr[:, :, 0] < 165)
		& (arr[:, :, 1] < 125)
		& (arr[:, :, 2] < 105)
		& (arr[:, :, 0] > arr[:, :, 1] + 5)
	)
	seed = hi & binary_dilation(brown, iterations=8) & near_face
	lab, n = label(binary_dilation(seed, iterations=2))
	raw = []
	for i in range(1, n + 1):
		ys, xs = np.where(lab == i)
		if len(xs) < 20:
			continue
		cx, cy = float(xs.mean()), float(ys.mean())
		ix, iy = int(cx), int(cy)
		if not near_face[min(H - 1, iy), min(W - 1, ix)]:
			if not near_face[ys, xs].any():
				continue
		d = np.sqrt((px[head].astype(float) - cx) ** 2 + (py[head].astype(float) - cy) ** 2)
		near = d < 55
		if near.sum() < 2:
			continue
		side = float(pos[head][near][:, 0].mean())
		pad = 70
		y0, y1 = max(0, int(cy - pad)), min(H, int(cy + pad))
		x0, x1 = max(0, int(cx - pad)), min(W, int(cx + pad))
		patch = arr[y0:y1, x0:x1]
		peach = ((patch[:, :, 0] > 160) & (patch[:, :, 1] > 110) & (patch[:, :, 0] > patch[:, :, 2] + 10)).mean()
		if peach < 0.12:
			continue
		lum = 0.2126 * patch[:, :, 0] + 0.7152 * patch[:, :, 1] + 0.0722 * patch[:, :, 2]
		eye_m = (lum < 130) | ((patch[:, :, 0] > 205) & (patch[:, :, 1] > 205))
		yy, xx = np.ogrid[: patch.shape[0], : patch.shape[1]]
		dist = np.sqrt((xx - (cx - x0)) ** 2 + (yy - (cy - y0)) ** 2)
		r = float(np.percentile(dist[eye_m], 92)) if eye_m.any() else 32.0
		r = float(np.clip(r, 22.0, 70.0))
		raw.append({"cx": cx, "cy": cy, "r": r, "side": side, "n": len(xs), "peach": float(peach)})

	raw.sort(key=lambda e: -e["n"])
	picked = []
	for e in raw:
		merged = False
		for p in picked:
			if (e["cx"] - p["cx"]) ** 2 + (e["cy"] - p["cy"]) ** 2 < 100 ** 2:
				w = e["n"] + p["n"]
				p["cx"] = (p["cx"] * p["n"] + e["cx"] * e["n"]) / w
				p["cy"] = (p["cy"] * p["n"] + e["cy"] * e["n"]) / w
				p["r"] = float(np.clip(max(p["r"], e["r"]), 22, 70))
				p["n"] = w
				p["side"] = (p["side"] + e["side"]) * 0.5
				p["peach"] = max(p["peach"], e["peach"])
				merged = True
				break
		if not merged:
			picked.append(dict(e))

	left = [e for e in picked if e["side"] < 0]
	right = [e for e in picked if e["side"] >= 0]
	out = []
	for group in (left, right):
		kept = []
		for e in sorted(group, key=lambda x: -x["n"]):
			if any((e["cx"] - k["cx"]) ** 2 + (e["cy"] - k["cy"]) ** 2 < 130 ** 2 for k in kept):
				continue
			kept.append(e)
			if len(kept) >= 2:
				break
		out.extend(kept)

	# Recessed left dual-island
	for cx0, cy0, rr in [(2900.0, 1035.0, 36.0)]:
		ix, iy = int(cx0), int(cy0)
		if not (0 <= ix < W and 0 <= iy < H and near_face[iy, ix]):
			continue
		if any((cx0 - e["cx"]) ** 2 + (cy0 - e["cy"]) ** 2 < 90 ** 2 for e in out):
			continue
		d = np.sqrt((px[head].astype(float) - cx0) ** 2 + (py[head].astype(float) - cy0) ** 2)
		if d.min() > 40:
			continue
		near = d < 45
		side = float(pos[head][near][:, 0].mean()) if near.sum() else -0.05
		out.append({"cx": cx0, "cy": cy0, "r": rr, "side": side, "n": 180, "peach": 0.4})
	print("eyes", [{k: round(v, 2) if isinstance(v, float) else v for k, v in e.items()} for e in out])
	return out


def _albedo_classes(arr):
	r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
	peach = (r > 145) & (g > 95) & (r > g + 8) & (b < r - 15) & ~((r > 200) & (g > 160) & (b < 100))
	sclera = (r > 195) & (g > 195) & (b > 180)
	iris = (r > 35) & (r < 170) & (g < 130) & (b < 110) & (r > g + 5) & (r > b + 10)
	hair = (r < 165) & (g < 125) & (b < 95) & (r > g + 5) & ~peach & ~sclera & ~iris
	straw = (r > 185) & (g > 145) & (b < 120) & ((r - b) > 70)
	red_cloth = (r > 140) & (g < 70) & (b < 70) & (r > g + 50)
	return peach, sclera, iris, hair, straw, red_cloth


def expand_mask_for_eyes(face_mask, eyes, mouths, arr):
	"""Face paint mask = triangle peach core + dual-island eye/mouth peach disks.

	Dual UV islands often sit outside the Head-forward triangle raster; without
	local peach disks around every eye/mouth the smile/cheer paints get clipped.
	Hair / straw / red cloth are always excluded (stops under-brim blotch).
	"""
	H, W = face_mask.shape
	mask = face_mask.copy()
	peach, sclera, iris, hair, straw, red_cloth = _albedo_classes(arr)
	skin_ok = peach | face_mask
	eye_ok = peach | sclera | iris
	yy, xx = np.mgrid[0:H, 0:W]
	for e in eyes:
		rad = e["r"] * 1.6
		disk = (xx - e["cx"]) ** 2 + (yy - e["cy"]) ** 2 <= rad * rad
		mask |= disk & eye_ok
		# Cheek ring around the eye (peach only) so blush / smile corners survive
		ring = (xx - e["cx"]) ** 2 + (yy - e["cy"]) ** 2 <= (rad * 2.2) ** 2
		mask |= ring & peach
	for m in mouths:
		rx = max(float(m["rx"]) * 1.8, 40.0)
		ry = max(float(m["ry"]) * 3.2, 36.0)
		ell = ((xx - m["cx"]) / rx) ** 2 + ((yy - m["cy"]) / ry) ** 2 <= 1.0
		mask |= ell & peach
	mask &= ~(hair | straw | red_cloth)
	print("paint_mask texels", int(mask.sum()), f"({100.0 * mask.mean():.2f}%)")
	return mask


def find_mouths(arr, eyes, face_mask):
	"""Mouth sites on peach face mask — one per UV eye-group.

	Tripo flat-eye UV: mouth is ~1.6·r toward atlas-center from the eye
	(smaller V when eye is near V=1, larger V when eye is near V=0). Never
	centroid the peach window — that locks onto the cheek under the eye.
	"""
	H, W = arr.shape[:2]
	groups = []
	for e in eyes:
		placed = False
		for g in groups:
			if any((e["cx"] - x["cx"]) ** 2 + (e["cy"] - x["cy"]) ** 2 < 200 ** 2 for x in g):
				g.append(e)
				placed = True
				break
		if not placed:
			groups.append([e])
	mouths = []
	for g in groups:
		cx = float(np.mean([e["cx"] for e in g]))
		cy = float(np.mean([e["cy"] for e in g]))
		r = float(np.mean([e["r"] for e in g]))
		side = float(np.mean([e["side"] for e in g]))
		# Geometric chin direction in UV
		dy = -r * 1.60 if cy > H * 0.5 else r * 1.60
		mx, my = cx, cy + dy
		# Refine on dark lip texels only in a tight window around the geometric guess
		y0, y1 = max(0, int(my - r * 0.9)), min(H, int(my + r * 0.9))
		x0, x1 = max(0, int(mx - r * 1.3)), min(W, int(mx + r * 1.3))
		patch = arr[y0:y1, x0:x1]
		pmask = face_mask[y0:y1, x0:x1]
		# Idle lips are soft brown, not jet black
		lip = (
			(patch[:, :, 0] < 150)
			& (patch[:, :, 1] < 120)
			& (patch[:, :, 2] < 110)
			& (patch[:, :, 0] > patch[:, :, 2])
			& pmask
		)
		rx, ry = r * 0.95, r * 0.30
		if lip.any() and float(lip.mean()) > 0.002:
			ys, xs = np.where(lip)
			mx = float(xs.mean()) + x0
			my = float(ys.mean()) + y0
			rx = float(np.clip(max(r * 0.85, (xs.max() - xs.min()) * 0.55 + 6), 18, r * 1.25))
			ry = float(np.clip(max(r * 0.22, (ys.max() - ys.min()) * 0.45 + 2), 7, r * 0.5))
		# Snap onto peach albedo near the geometric guess (dual islands may miss triangle mask)
		peach, _, _, _, _, red_cloth = _albedo_classes(arr)
		ok = peach & ~red_cloth
		bx, by = int(mx), int(my)
		if not (0 <= bx < W and 0 <= by < H and ok[by, bx]):
			y0, y1 = max(0, by - 55), min(H, by + 55)
			x0, x1 = max(0, bx - 55), min(W, bx + 55)
			ys, xs = np.where(ok[y0:y1, x0:x1])
			if len(xs):
				# Prefer peach closest to geometric mouth
				d2 = (xs + x0 - mx) ** 2 + (ys + y0 - my) ** 2
				j = int(np.argmin(d2))
				mx = float(xs[j] + x0)
				my = float(ys[j] + y0)
		mouths.append({"cx": mx, "cy": my, "rx": rx, "ry": ry, "side": side})
	print("mouths", [{k: round(v, 1) if isinstance(v, float) else v for k, v in m.items()} for m in mouths])
	return mouths


def sample_skin(arr, face_mask, cx, cy, r):
	H, W = arr.shape[:2]
	ring = []
	for ang in np.linspace(0, 2 * np.pi, 32, endpoint=False):
		for mul in (1.15, 1.4, 1.65):
			x = int(cx + np.cos(ang) * r * mul)
			y = int(cy + np.sin(ang) * r * mul)
			if 0 <= x < W and 0 <= y < H and face_mask[y, x]:
				c = arr[y, x]
				if _is_peach(c):
					ring.append(c)
	if not ring:
		return (215, 168, 138, 255)
	m = np.mean(ring, axis=0)
	return (int(m[0]), int(m[1]), int(m[2]), 255)


def _clip_layer(layer: Image.Image, face_mask) -> Image.Image:
	"""Zero out any paint outside the face-skin UV mask."""
	a = np.asarray(layer).copy()
	a[~face_mask, 3] = 0
	return Image.fromarray(a, "RGBA")


def paint_eye_happy(draw, cx, cy, r, skin):
	"""Cheer: clear open iris to skin, draw ^^ happy closed curves. No ghost lines under."""
	lash = (32, 20, 14, 255)
	brow = (48, 30, 24, 255)
	# Full clear of open eye — cover sclera + iris + any under-eye ghost
	draw.ellipse([cx - r * 1.65, cy - r * 1.5, cx + r * 1.65, cy + r * 1.55], fill=skin)
	# ^^ upward arcs (happy closed eyes) — bold
	w = max(5, int(r * 0.26))
	draw.arc([cx - r * 1.1, cy - r * 0.7, cx + r * 1.1, cy + r * 0.4], 205, 335, fill=lash, width=w)
	# brow slightly raised
	by = cy - r * 1.2
	draw.line([(cx - r * 0.9, by + 2), (cx + r * 0.9, by - 3)], fill=brow, width=max(2, int(r * 0.14)))

def paint_eye_shut(draw, cx, cy, r, skin):
	"""Sleep: skin cover + soft downward lid crease."""
	lash = (42, 26, 20, 255)
	brow = (52, 32, 26, 255)
	draw.ellipse([cx - r * 1.4, cy - r * 1.2, cx + r * 1.4, cy + r * 1.2], fill=skin)
	w = max(3, int(r * 0.15))
	draw.arc([cx - r * 1.0, cy - r * 0.2, cx + r * 1.0, cy + r * 0.85], 20, 160, fill=lash, width=w)
	by = cy - r * 1.05
	draw.line([(cx - r * 0.9, by), (cx + r * 0.9, by + 1)], fill=brow, width=max(2, int(r * 0.12)))


def paint_mouth_smile(draw, m, skin):
	"""Clearly upturned closed-mouth smile + slight cheek lift."""
	cx, cy, rx, ry = m["cx"], m["cy"], m["rx"] * 1.35, m["ry"] * 1.25
	draw.ellipse([cx - rx * 1.45, cy - ry * 2.2, cx + rx * 1.45, cy + ry * 2.6], fill=skin)
	lip = (55, 28, 24, 255)
	w = max(5, int(rx * 0.2))
	# Strong wide U — corners clearly higher than center
	draw.arc([cx - rx * 1.25, cy - ry * 0.2, cx + rx * 1.25, cy + ry * 3.4], 20, 160, fill=lip, width=w + 2)
	# Raised-cheek blush
	blush = (240, 140, 120, 110)
	draw.ellipse([cx - rx * 1.95, cy - ry * 1.5, cx - rx * 0.35, cy + ry * 0.7], fill=blush)
	draw.ellipse([cx + rx * 0.35, cy - ry * 1.5, cx + rx * 1.95, cy + ry * 0.7], fill=blush)


def paint_mouth_cheer(draw, m, skin):
	"""Big open mouth: dark interior + tongue. No faint under-eye ghosts (eyes handled separately)."""
	cx, cy, rx, ry = m["cx"], m["cy"], m["rx"] * 1.55, m["ry"] * 2.6
	draw.ellipse([cx - rx * 1.45, cy - ry * 1.7, cx + rx * 1.45, cy + ry * 2.0], fill=skin)
	interior = (28, 8, 10, 255)
	lip = (140, 50, 48, 255)
	draw.ellipse([cx - rx, cy - ry * 0.7, cx + rx, cy + ry * 1.5], fill=interior)
	draw.ellipse([cx - rx, cy - ry * 0.7, cx + rx, cy + ry * 1.5], outline=lip, width=max(3, int(rx * 0.12)))
	tongue = (220, 85, 95, 255)
	draw.ellipse([cx - rx * 0.55, cy + ry * 0.25, cx + rx * 0.55, cy + ry * 1.3], fill=tongue)
	teeth = (250, 240, 228, 255)
	draw.rectangle([cx - rx * 0.8, cy - ry * 0.5, cx + rx * 0.8, cy - ry * 0.05], fill=teeth)
def paint_mouth_sleep(draw, m, skin):
	cx, cy, rx, ry = m["cx"], m["cy"], m["rx"], m["ry"]
	draw.ellipse([cx - rx * 1.15, cy - ry * 1.5, cx + rx * 1.15, cy + ry * 1.5], fill=skin)
	lip = (55, 32, 28, 255)
	w = max(2, int(min(rx, ry) * 0.2))
	draw.arc([cx - rx * 0.85, cy - ry * 0.3, cx + rx * 0.85, cy + ry * 1.2], 25, 155, fill=lip, width=w)


def paint_mode(base, eyes, mouths, paint_mask, mode: str) -> Image.Image:
	"""Paint expression clipped to paint_mask (peach face + dual-island eye/mouth disks)."""
	img = base.copy().convert("RGBA")
	arr = np.asarray(base.convert("RGB")).astype(np.float32)
	layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
	draw = ImageDraw.Draw(layer, "RGBA")
	if mode == "cheer":
		for e in eyes:
			skin = sample_skin(arr, paint_mask, e["cx"], e["cy"], e["r"])
			paint_eye_happy(draw, e["cx"], e["cy"], e["r"], skin)
		for m in mouths:
			skin = sample_skin(arr, paint_mask, m["cx"], m["cy"], max(m["rx"], 20))
			paint_mouth_cheer(draw, m, skin)
	elif mode == "smile":
		for m in mouths:
			skin = sample_skin(arr, paint_mask, m["cx"], m["cy"], max(m["rx"], 20))
			paint_mouth_smile(draw, m, skin)
	elif mode == "sleep":
		for e in eyes:
			skin = sample_skin(arr, paint_mask, e["cx"], e["cy"], e["r"])
			paint_eye_shut(draw, e["cx"], e["cy"], e["r"], skin)
		for m in mouths:
			skin = sample_skin(arr, paint_mask, m["cx"], m["cy"], max(m["rx"], 20))
			paint_mouth_sleep(draw, m, skin)
	layer = _clip_layer(layer, paint_mask)
	layer = layer.filter(ImageFilter.GaussianBlur(radius=0.35))
	layer = _clip_layer(layer, paint_mask)
	return Image.alpha_composite(img, layer).convert("RGB")
def write_diff_heatmap(idle: Image.Image, smile: Image.Image, face_mask, path: str):
	a = np.asarray(idle).astype(np.float32)
	b = np.asarray(smile).astype(np.float32)
	d = np.abs(a - b).mean(axis=2)
	# Heatmap: black = no change, yellow/red = change
	heat = np.zeros((*d.shape, 3), dtype=np.uint8)
	norm = np.clip(d / max(d.max(), 1.0), 0, 1)
	heat[:, :, 0] = (norm * 255).astype(np.uint8)
	heat[:, :, 1] = (np.clip(norm * 2, 0, 1) * 180).astype(np.uint8)
	# Outline face mask in cyan
	edge = face_mask & ~binary_erosion(face_mask, iterations=1)
	heat[edge] = [0, 220, 255]
	Image.fromarray(heat).resize((1024, 1024), Image.NEAREST).save(path)
	# Stats: change outside face mask must be ~0
	outside = d[~face_mask]
	inside = d[face_mask]
	print(
		"diff heatmap",
		path,
		"outside_mean",
		float(outside.mean()) if outside.size else 0,
		"outside_max",
		float(outside.max()) if outside.size else 0,
		"inside_mean",
		float(inside.mean()) if inside.size else 0,
		"changed_texels_outside",
		int((outside > 2).sum()),
	)
	return float(outside.max()) if outside.size else 0.0


def preview_crop(img, eyes, mouths, path):
	"""Two face islands: eye + mouth together so smile/cheer read clearly."""
	groups = []
	for e in eyes:
		placed = False
		for g in groups:
			if any((e["cx"] - x["cx"]) ** 2 + (e["cy"] - x["cy"]) ** 2 < 220 ** 2 for x in g["eyes"]):
				g["eyes"].append(e)
				placed = True
				break
		if not placed:
			groups.append({"eyes": [e], "mouth": None})
	for m in mouths:
		best, bd = None, 1e18
		for g in groups:
			cx = float(np.mean([e["cx"] for e in g["eyes"]]))
			cy = float(np.mean([e["cy"] for e in g["eyes"]]))
			d = (m["cx"] - cx) ** 2 + (m["cy"] - cy) ** 2
			if d < bd:
				bd, best = d, g
		if best is not None:
			best["mouth"] = m
	# Prefer one left + one right island
	focus = sorted(groups, key=lambda g: -sum(e["n"] for e in g["eyes"]))[:2]
	crops = []
	for g in focus:
		xs = [e["cx"] for e in g["eyes"]] + ([g["mouth"]["cx"]] if g["mouth"] else [])
		ys = [e["cy"] for e in g["eyes"]] + ([g["mouth"]["cy"]] if g["mouth"] else [])
		rs = [e["r"] for e in g["eyes"]] + ([max(g["mouth"]["rx"], g["mouth"]["ry"]) * 1.2] if g["mouth"] else [])
		pad = max(rs) * 2.6 if rs else 80
		c = img.crop((int(min(xs) - pad), int(min(ys) - pad), int(max(xs) + pad), int(max(ys) + pad * 1.15)))
		crops.append(c.resize((280, 280), Image.LANCZOS))
	if not crops:
		return
	strip = Image.new("RGB", (280 * len(crops), 280))
	for i, c in enumerate(crops):
		strip.paste(c, (i * 280, 0))
	strip.save(path)

def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	os.makedirs(TRIPO_DIR, exist_ok=True)
	js, bindata = load_glb(SRC_GLB)
	extract_basecolor(js, bindata, BASE)
	base = Image.open(BASE).convert("RGB")
	arr = np.asarray(base).astype(np.float32)
	W, H = base.size
	print("albedo", W, H)
	face_mask, pos, uv, head, face_v, px, py = build_face_skin_mask(js, bindata, arr)
	# Save mask preview
	mask_vis = np.zeros((H, W, 3), dtype=np.uint8)
	mask_vis[:] = (arr * 0.35).astype(np.uint8)
	mask_vis[face_mask] = np.clip(arr[face_mask] * 0.5 + np.array([0, 180, 80]), 0, 255).astype(np.uint8)
	Image.fromarray(mask_vis).resize((1024, 1024)).save(os.path.join(OUT_DIR, "face_mask_debug.png"))

	eyes = find_eye_islands(arr, face_mask, pos, head, px, py)
	if len(eyes) < 2:
		raise SystemExit("need >=2 eye islands, got %d" % len(eyes))
	mouths = find_mouths(arr, eyes, face_mask)
	paint_mask = expand_mask_for_eyes(face_mask, eyes, mouths, arr)
	peach, sclera, iris, hair, straw, red_cloth = _albedo_classes(arr)
	# Update mask debug to show paint_mask
	mask_vis = np.zeros((H, W, 3), dtype=np.uint8)
	mask_vis[:] = (arr * 0.35).astype(np.uint8)
	mask_vis[paint_mask] = np.clip(arr[paint_mask] * 0.5 + np.array([0, 180, 80]), 0, 255).astype(np.uint8)
	Image.fromarray(mask_vis).resize((1024, 1024)).save(os.path.join(OUT_DIR, "face_mask_debug.png"))

	dbg = base.copy().convert("RGBA")
	d = ImageDraw.Draw(dbg)
	for e in eyes:
		col = (255, 40, 40, 255) if e["side"] >= 0 else (40, 220, 40, 255)
		d.ellipse([e["cx"] - e["r"], e["cy"] - e["r"], e["cx"] + e["r"], e["cy"] + e["r"]], outline=col, width=4)
	for m in mouths:
		d.ellipse([m["cx"] - m["rx"], m["cy"] - m["ry"], m["cx"] + m["rx"], m["cy"] + m["ry"]], outline=(40, 40, 255, 255), width=3)
	dbg.resize((1024, 1024)).save(os.path.join(OUT_DIR, "face_uv_debug.png"))

	idle = base.copy()
	idle.save(os.path.join(OUT_DIR, "face_alb_idle.png"), optimize=True)
	idle.save(os.path.join(TRIPO_DIR, "face_alb_idle.png"), optimize=True)
	idle.convert("RGB").save(os.path.join(OUT_DIR, "face_alb_idle.jpg"), quality=88, optimize=True)
	idle.convert("RGB").save(os.path.join(TRIPO_DIR, "face_alb_idle.jpg"), quality=88, optimize=True)
	preview_crop(idle, eyes, mouths, os.path.join(OUT_DIR, "face_preview_idle.png"))
	print("wrote idle (original)")

	outs = {}
	for name, mode in [("smile", "smile"), ("cheer", "cheer"), ("sleep", "sleep")]:
		out = paint_mode(base, eyes, mouths, paint_mask, mode)
		outs[name] = out
		out.save(os.path.join(OUT_DIR, f"face_alb_{name}.png"), optimize=True)
		out.save(os.path.join(TRIPO_DIR, f"face_alb_{name}.png"), optimize=True)
		out.save(os.path.join(OUT_DIR, f"face_alb_{name}.jpg"), quality=88, optimize=True)
		out.save(os.path.join(TRIPO_DIR, f"face_alb_{name}.jpg"), quality=88, optimize=True)
		preview_crop(out, eyes, mouths, os.path.join(OUT_DIR, f"face_preview_{name}.png"))
		print("wrote", name)

	outside_max = write_diff_heatmap(
		idle, outs["smile"], paint_mask, os.path.join(OUT_DIR, "face_diff_idle_smile.png")
	)
	a = np.asarray(idle).astype(np.float32)
	b = np.asarray(outs["smile"]).astype(np.float32)
	dlt = np.abs(a - b).mean(axis=2)
	hair_leak = float(dlt[hair].max()) if hair.any() else 0.0
	print("hair_leak_max", hair_leak)
	write_diff_heatmap(idle, outs["cheer"], paint_mask, os.path.join(OUT_DIR, "face_diff_idle_cheer.png"))
	if outside_max > 8 or hair_leak > 2:
		print("WARNING: paint leaked (outside_max %.1f hair_leak %.1f)" % (outside_max, hair_leak))
	with open(os.path.join(OUT_DIR, "eye_boxes.txt"), "w") as f:
		for e in eyes:
			f.write(
				f"{(e['cx']-e['r'])/W:.6f} {(e['cx']+e['r'])/W:.6f} "
				f"{(e['cy']-e['r'])/H:.6f} {(e['cy']+e['r'])/H:.6f} side={e['side']:.3f}\n"
			)
	print("done")

if __name__ == "__main__":
	main()
