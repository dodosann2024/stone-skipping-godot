"""Paint flat-eye expression albedos onto the Tripo UV atlas.

Preserves skin/clothes/hat. Overpaints only eyes, brows, and mouth on every
UV island that the Head bone's face-forward verts sample. No floating plates.
"""
import json
import os
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_dilation, label

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


def mesh_face_coverage(js, bindata, W, H):
	"""Boolean mask of texels covered by Head-bone face-forward verts (glTF UV top-left)."""
	p = js["meshes"][0]["primitives"][0]
	pos = get_acc(js, bindata, p["attributes"]["POSITION"]).astype(np.float32)
	uv = get_acc(js, bindata, p["attributes"]["TEXCOORD_0"]).astype(np.float32)
	joints = get_acc(js, bindata, p["attributes"]["JOINTS_0"])
	weights = get_acc(js, bindata, p["attributes"]["WEIGHTS_0"]).astype(np.float32)
	skin = js["skins"][0]
	bone_names = [js["nodes"][ni].get("name", "") for ni in skin["joints"]]
	head_i = bone_names.index("mixamorig:Head")
	prim = joints[np.arange(len(joints)), weights.argmax(axis=1)]
	head = prim == head_i
	# +Z is face-forward on this Mixamo import (white sclera samples live there).
	face = head & (pos[:, 2] > 0.04)
	px = np.clip((uv[:, 0] * W).astype(int), 0, W - 1)
	py = np.clip((uv[:, 1] * H).astype(int), 0, H - 1)
	cov = np.zeros((H, W), dtype=bool)
	cov[py[face], px[face]] = True
	cov = binary_dilation(cov, iterations=5)
	# Also keep head coverage for dual UV islands that sit slightly off face mask.
	hcov = np.zeros((H, W), dtype=bool)
	hcov[py[head], px[head]] = True
	hcov = binary_dilation(hcov, iterations=3)
	return cov | hcov, pos, uv, head, face, px, py


def find_eye_islands(arr, cov, pos, uv, head, face, px, py):
	"""Return deduped eye paint sites {cx,cy,r,side} on every UV island used by the face."""
	W = arr.shape[1]
	H = arr.shape[0]
	hi = (arr[:, :, 0] > 200) & (arr[:, :, 1] > 200) & (arr[:, :, 2] > 185)
	brown = (
		(arr[:, :, 0] > 35)
		& (arr[:, :, 0] < 165)
		& (arr[:, :, 1] < 125)
		& (arr[:, :, 2] < 105)
		& (arr[:, :, 0] > arr[:, :, 1] + 5)
	)
	seed = hi & binary_dilation(brown, iterations=8) & binary_dilation(cov, iterations=4)
	lab, n = label(binary_dilation(seed, iterations=2))
	raw = []
	for i in range(1, n + 1):
		ys, xs = np.where(lab == i)
		if len(xs) < 25:
			continue
		cx, cy = float(xs.mean()), float(ys.mean())
		# 3D side from nearby head verts (glTF UV, no V-flip).
		d = np.sqrt((px[head].astype(float) - cx) ** 2 + (py[head].astype(float) - cy) ** 2)
		near = d < 55
		if near.sum() < 2:
			continue
		side = float(pos[head][near][:, 0].mean())
		# Radius from white+iris extent inside a peach neighborhood.
		pad = 70
		y0, y1 = max(0, int(cy - pad)), min(H, int(cy + pad))
		x0, x1 = max(0, int(cx - pad)), min(W, int(cx + pad))
		patch = arr[y0:y1, x0:x1]
		peach = ((patch[:, :, 0] > 160) & (patch[:, :, 1] > 110) & (patch[:, :, 0] > patch[:, :, 2] + 10)).mean()
		if peach < 0.18:
			continue
		lum = 0.2126 * patch[:, :, 0] + 0.7152 * patch[:, :, 1] + 0.0722 * patch[:, :, 2]
		eye_m = (lum < 130) | ((patch[:, :, 0] > 205) & (patch[:, :, 1] > 205))
		yy, xx = np.ogrid[: patch.shape[0], : patch.shape[1]]
		dist = np.sqrt((xx - (cx - x0)) ** 2 + (yy - (cy - y0)) ** 2)
		if eye_m.any():
			r = float(np.percentile(dist[eye_m], 92))
		else:
			r = float(np.sqrt(((xs - cx) ** 2 + (ys - cy) ** 2).max()) * 0.5)
		r = float(np.clip(r, 24.0, 78.0))
		raw.append({"cx": cx, "cy": cy, "r": r, "side": side, "n": len(xs), "peach": float(peach)})

	# Merge UV fragments of the SAME island (within 110px). Tripo dual-packs
	# put L/R eyes on distant islands — those stay separate.
	raw.sort(key=lambda e: -e["n"])
	picked = []
	for e in raw:
		merged = False
		for p in picked:
			if (e["cx"] - p["cx"]) ** 2 + (e["cy"] - p["cy"]) ** 2 < 110 ** 2:
				# Weighted center; radius covers both fragments without stacking two irises.
				w = e["n"] + p["n"]
				nx = (p["cx"] * p["n"] + e["cx"] * e["n"]) / w
				ny = (p["cy"] * p["n"] + e["cy"] * e["n"]) / w
				span = 0.5 * np.hypot(e["cx"] - p["cx"], e["cy"] - p["cy"])
				p["r"] = float(np.clip(max(p["r"], e["r"], span + min(p["r"], e["r"]) * 0.6), 24, 72))
				p["cx"], p["cy"] = nx, ny
				p["n"] = w
				p["side"] = (p["side"] * (w - e["n"]) + e["side"] * e["n"]) / w
				p["peach"] = max(p["peach"], e["peach"])
				merged = True
				break
		if not merged:
			picked.append(dict(e))

	# Per 3D side keep at most 2 UV islands (primary face pack + optional dual pack).
	picked.sort(key=lambda e: (-e["n"], -e["peach"]))
	left = [e for e in picked if e["side"] < 0]
	right = [e for e in picked if e["side"] >= 0]
	out = []
	for group in (left, right):
		kept = []
		for e in sorted(group, key=lambda x: -x["n"]):
			if any((e["cx"] - k["cx"]) ** 2 + (e["cy"] - k["cy"]) ** 2 < 140 ** 2 for k in kept):
				continue
			kept.append(e)
			if len(kept) >= 2:
				break
		out.extend(kept)

	# Force-include recessed left-eye island near (2900,1035) if still missing.
	cx0, cy0 = 2900.0, 1035.0
	d = np.sqrt((px[head].astype(float) - cx0) ** 2 + (py[head].astype(float) - cy0) ** 2)
	if d.min() < 40 and not any((cx0 - e["cx"]) ** 2 + (cy0 - e["cy"]) ** 2 < 90 ** 2 for e in out):
		near = d < 45
		side = float(pos[head][near][:, 0].mean()) if near.sum() else -0.05
		out.append({"cx": cx0, "cy": cy0, "r": 38.0, "side": side, "n": 200, "peach": 0.4})
	print("eyes", [{k: (round(v, 2) if isinstance(v, float) else v) for k, v in e.items()} for e in out])
	return out


def find_mouths(arr, eyes, pos, head, px, py):
	"""One mouth per UV face island — search below the eye cluster, not per fragment."""
	H = arr.shape[0]
	W = arr.shape[1]
	# Group eyes that share a face UV neighborhood.
	groups = []
	for e in eyes:
		placed = False
		for g in groups:
			if any((e["cx"] - x["cx"]) ** 2 + (e["cy"] - x["cy"]) ** 2 < 220 ** 2 for x in g):
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
		# Search a ring around the eye(s) — Tripo packs mouth above OR below in UV.
		best = None
		for y0, y1, x0, x1 in [
			(max(0, int(cy + r * 0.7)), min(H, int(cy + r * 2.6)), max(0, int(cx - r * 1.5)), min(W, int(cx + r * 1.5))),
			(max(0, int(cy - r * 2.6)), min(H, int(cy - r * 0.7)), max(0, int(cx - r * 1.5)), min(W, int(cx + r * 1.5))),
		]:
			if y1 - y0 < 8 or x1 - x0 < 8:
				continue
			patch = arr[y0:y1, x0:x1]
			dark = (patch[:, :, 0] < 100) & (patch[:, :, 1] < 80) & (patch[:, :, 2] < 70)
			score = float(dark.mean())
			if score < 0.002:
				continue
			ys, xs = np.where(dark)
			cand = {
				"cx": float(xs.mean()) + x0,
				"cy": float(ys.mean()) + y0,
				"rx": float(np.clip(max(r * 0.8, (xs.max() - xs.min()) * 0.5 + 6), 16, r * 1.2)),
				"ry": float(np.clip(max(r * 0.18, (ys.max() - ys.min()) * 0.4 + 2), 5, r * 0.4)),
				"side": side,
				"_score": score,
			}
			if best is None or cand["_score"] > best["_score"]:
				best = cand
		if best is None:
			# Fallback: place toward image interior from eye (avoid going off atlas).
			dy = -r * 1.55 if cy > H * 0.7 else r * 1.55
			best = {"cx": cx, "cy": cy + dy, "rx": r * 0.9, "ry": r * 0.22, "side": side, "_score": 0}
		best.pop("_score", None)
		mouths.append(best)
	print("mouths", [{k: round(v, 1) if isinstance(v, float) else v for k, v in m.items()} for m in mouths])
	return mouths


def sample_skin(arr, cx, cy, r):
	"""Average peach around an eye for seamless clear-to-skin."""
	H, W = arr.shape[:2]
	ring = []
	for ang in np.linspace(0, 2 * np.pi, 24, endpoint=False):
		x = int(cx + np.cos(ang) * r * 1.45)
		y = int(cy + np.sin(ang) * r * 1.45)
		if 0 <= x < W and 0 <= y < H:
			c = arr[y, x]
			if c[0] > 150 and c[1] > 100 and c[0] > c[2] + 8:
				ring.append(c)
	if not ring:
		return (215, 168, 138, 255)
	m = np.mean(ring, axis=0)
	return (int(m[0]), int(m[1]), int(m[2]), 255)


def paint_eye(draw, cx, cy, r, mode, skin):
	lash = (42, 26, 20, 255)
	brow = (52, 32, 26, 255)
	if mode == "shut":
		# Cover original open iris completely, then draw a soft closed lid.
		draw.ellipse([cx - r * 1.45, cy - r * 1.15, cx + r * 1.45, cy + r * 1.15], fill=skin)
		draw.arc(
			[cx - r * 1.05, cy - r * 0.15, cx + r * 1.05, cy + r * 0.75],
			200, 340, fill=lash, width=max(3, int(r * 0.16)),
		)
		by = cy - r * 1.05
		draw.line([(cx - r * 0.95, by), (cx + r * 0.95, by + 1)], fill=brow, width=max(2, int(r * 0.14)))
		return
	if mode == "squint":
		# Soft lids over the ORIGINAL approved eyes — no full iris redraw (avoids doubles).
		lid_h = r * 0.42
		draw.ellipse([cx - r * 1.15, cy - r * 1.2, cx + r * 1.15, cy - r * 0.15], fill=skin)
		draw.ellipse([cx - r * 1.1, cy + r * 0.25, cx + r * 1.1, cy + r * 1.15], fill=skin)
		draw.arc([cx - r, cy - lid_h, cx + r, cy + lid_h * 1.6], 200, 340, fill=lash, width=max(2, int(r * 0.12)))
		by = cy - r * 1.05
		draw.line([(cx - r * 0.95, by + 2), (cx + r * 0.95, by - 1)], fill=brow, width=max(2, int(r * 0.13)))
		return
	# Full idle-style redraw (rarely used — idle keeps original albedo).
	sclera = (248, 244, 236, 255)
	iris = (88, 52, 32, 255)
	pupil = (18, 10, 8, 255)
	hi = (255, 255, 255, 255)
	draw.ellipse([cx - r * 1.55, cy - r * 1.55, cx + r * 1.55, cy + r * 1.55], fill=skin)
	draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=sclera)
	ir = r * 0.72
	draw.ellipse([cx - ir, cy - ir * 0.85, cx + ir, cy + ir * 0.85], fill=iris)
	pr = r * 0.28
	draw.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=pupil)
	hx, hy, hr = cx - r * 0.28, cy - r * 0.35, max(3, int(r * 0.16))
	draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=hi)
	draw.arc([cx - r, cy - r, cx + r, cy + r], 200, 340, fill=lash, width=max(2, int(r * 0.12)))
	by = cy - r * 1.35
	draw.line([(cx - r * 0.9, by), (cx + r * 0.9, by + 1)], fill=brow, width=max(2, int(r * 0.12)))


def paint_mouth(draw, m, mode, skin):
	cx, cy, rx, ry = m["cx"], m["cy"], m["rx"], m["ry"]
	# Clear prior stroke to skin so sleep/smile don't ghost.
	draw.ellipse([cx - rx * 1.15, cy - ry * 1.6, cx + rx * 1.15, cy + ry * 1.6], fill=skin)
	lip = (55, 32, 28, 255)
	w = max(2, int(min(rx, ry) * 0.22))
	if mode == "shut" or mode == "idle":
		# Soft neutral curve
		draw.arc([cx - rx, cy - ry, cx + rx, cy + ry * 1.4], 20, 160, fill=lip, width=w)
	elif mode == "smile":
		draw.arc([cx - rx, cy - ry * 0.2, cx + rx, cy + ry * 2.2], 15, 165, fill=lip, width=w + 1)
	elif mode == "squint":  # cheer — wider open smile
		draw.arc([cx - rx * 1.05, cy - ry * 0.1, cx + rx * 1.05, cy + ry * 2.4], 10, 170, fill=lip, width=w + 1)
		# tiny upper lip hint
		draw.arc([cx - rx * 0.55, cy - ry * 1.1, cx + rx * 0.55, cy + ry * 0.4], 200, 340, fill=lip, width=max(1, w - 1))


def paint_mode(base: Image.Image, eyes, mouths, mode: str) -> Image.Image:
	img = base.copy().convert("RGBA")
	arr = np.asarray(base.convert("RGB")).astype(np.float32)
	layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
	draw = ImageDraw.Draw(layer)
	# smile/cheer: keep original approved eyes; mouth only (cheer = wider smile).
	# sleep: shut lids over original eyes — no full iris redraw.
	if mode == "shut":
		for e in eyes:
			skin = sample_skin(arr, e["cx"], e["cy"], e["r"])
			paint_eye(draw, e["cx"], e["cy"], e["r"], mode, skin)
	mouth_mode = "squint" if mode == "squint" else mode
	for m in mouths:
		skin = sample_skin(arr, m["cx"], m["cy"], max(m["rx"], 20))
		paint_mouth(draw, m, mouth_mode, skin)
	layer = layer.filter(ImageFilter.GaussianBlur(radius=0.6))
	out = Image.alpha_composite(img, layer).convert("RGB")
	return out


def preview_crop(img: Image.Image, eyes, path: str):
	if not eyes:
		img.resize((512, 512)).save(path)
		return
	# Crop around all eyes with margin.
	xs = [e["cx"] for e in eyes]
	ys = [e["cy"] for e in eyes]
	rs = [e["r"] for e in eyes]
	# Prefer the two largest islands for a readable face preview — or a union bbox.
	pad = 120
	# Use right-side main eye region if available else union.
	right = [e for e in eyes if e["side"] >= 0]
	left = [e for e in eyes if e["side"] < 0]
	focus = (right + left)[:2] if (right or left) else eyes[:2]
	# Build a montage of focus islands
	crops = []
	for e in focus:
		c = img.crop((int(e["cx"] - e["r"] * 2.5), int(e["cy"] - e["r"] * 2.8),
					  int(e["cx"] + e["r"] * 2.5), int(e["cy"] + e["r"] * 3.2)))
		crops.append(c.resize((256, 256), Image.LANCZOS))
	if not crops:
		return
	strip = Image.new("RGB", (256 * len(crops), 256))
	for i, c in enumerate(crops):
		strip.paste(c, (i * 256, 0))
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
	cov, pos, uv, head, face, px, py = mesh_face_coverage(js, bindata, W, H)
	eyes = find_eye_islands(arr, cov, pos, uv, head, face, px, py)
	if len(eyes) < 2:
		raise SystemExit("need >=2 eye islands, got %d" % len(eyes))
	mouths = find_mouths(arr, eyes, pos, head, px, py)

	# Debug UV overlay
	dbg = base.copy().convert("RGBA")
	d = ImageDraw.Draw(dbg)
	for e in eyes:
		col = (255, 40, 40, 255) if e["side"] >= 0 else (40, 220, 40, 255)
		d.ellipse([e["cx"] - e["r"], e["cy"] - e["r"], e["cx"] + e["r"], e["cy"] + e["r"]], outline=col, width=5)
	for m in mouths:
		d.ellipse([m["cx"] - m["rx"], m["cy"] - m["ry"], m["cx"] + m["rx"], m["cy"] + m["ry"]], outline=(40, 40, 255, 255), width=3)
	dbg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT_DIR, "face_uv_debug.png"))

	# idle = original approved flat-eye albedo (preserve skin/shading).
	# smile/cheer/sleep overpaint eyes/mouth/brows only.
	modes = {"smile": "smile", "cheer": "squint", "sleep": "shut"}
	idle_path = os.path.join(OUT_DIR, "face_alb_idle.png")
	base.save(idle_path, optimize=True)
	print("wrote", idle_path, "(original)")
	preview_crop(base, eyes, os.path.join(OUT_DIR, "face_preview_idle.png"))
	base.save(os.path.join(TRIPO_DIR, "face_alb_idle.png"), optimize=True)
	for name, mode in modes.items():
		out = paint_mode(base, eyes, mouths, mode)
		path = os.path.join(OUT_DIR, f"face_alb_{name}.png")
		out.save(path, optimize=True)
		print("wrote", path)
		preview_crop(out, eyes, os.path.join(OUT_DIR, f"face_preview_{name}.png"))
		out.save(os.path.join(TRIPO_DIR, f"face_alb_{name}.png"), optimize=True)

	# Persist eye boxes for any legacy tooling (unused by flat-eye runtime).
	with open(os.path.join(OUT_DIR, "eye_boxes.txt"), "w") as f:
		for e in eyes:
			u0 = (e["cx"] - e["r"]) / W
			u1 = (e["cx"] + e["r"]) / W
			v0 = (e["cy"] - e["r"]) / H
			v1 = (e["cy"] + e["r"]) / H
			f.write(f"{u0:.6f} {u1:.6f} {v0:.6f} {v1:.6f} side={e['side']:.3f}\n")
	print("done")


if __name__ == "__main__":
	main()
