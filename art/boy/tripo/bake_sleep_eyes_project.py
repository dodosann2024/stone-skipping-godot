#!/usr/bin/env python3
"""Headless Blender: screen-space closed-eye projection bake onto Tripo albedo.

1) Front orthographic render of the head (open eyes).
2) Paint closed lids on that render (skin fill + soft lash + crease).
3) Project the painted pixels back onto the albedo from the same camera so
   every UV island under the eyes gets consistent paint.
4) Write boy_tripo_sleep_eyes.png (second albedo for sleep swap).

Does not re-split the baked hat — only texels that project into the eye mask
and fall on head-ish mesh are written.
"""
import bpy
import math
import os
import shutil
import sys
from mathutils import Vector

GLB = "/workspace/art/boy/tripo/boy_tripo.glb"
OUT_SLEEP = "/workspace/art/boy/tripo/boy_tripo_sleep_eyes.png"
OUT_DIR = "/workspace/screenshots/v24"
RENDER_OPEN = os.path.join(OUT_DIR, "_eye_proj_open.png")
RENDER_CLOSED = os.path.join(OUT_DIR, "_eye_proj_closed.png")
RENDER_MASK = os.path.join(OUT_DIR, "_eye_proj_mask.png")
RES = 1024  # ortho render resolution


def clear_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def import_boy():
	bpy.ops.import_scene.gltf(filepath=GLB)
	for o in list(bpy.data.objects):
		if o.type == "MESH" and "Ico" in o.name:
			bpy.data.objects.remove(o, do_unlink=True)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	mesh = next(
		o for o in bpy.data.objects
		if o.type == "MESH" and o.data.materials and len(o.data.polygons) > 100
	)
	bpy.context.view_layer.objects.active = arm
	arm.data.pose_position = "REST"
	bpy.context.view_layer.update()
	return arm, mesh


def find_albedo_image(mesh_obj):
	mat = None
	if mesh_obj.material_slots:
		mat = mesh_obj.material_slots[0].material
	if mat is None and mesh_obj.data.materials:
		mat = mesh_obj.data.materials[0]
	if mat and mat.node_tree:
		for n in mat.node_tree.nodes:
			if n.type == "BSDF_PRINCIPLED":
				inp = n.inputs.get("Base Color")
				if inp and inp.is_linked:
					src = inp.links[0].from_node
					if src.type == "TEX_IMAGE" and src.image:
						return src.image, src
		for n in mat.node_tree.nodes:
			if n.type == "TEX_IMAGE" and n.image and n.image.size[0] >= 1024:
				return n.image, n
	best = None
	for img in bpy.data.images:
		if img.size[0] < 1024:
			continue
		if "tripo_image" in img.name or best is None or img.size[0] > best.size[0]:
			best = img
	return best, None


def face_look_target(mesh_obj, arm):
	"""Return (look_at, face_fwd_candidates, ortho_scale) aimed at the eyes."""
	look = None
	head_z = None
	top_z = None
	if arm is not None:
		head_pb = None
		top_pb = None
		for name in ("mixamorig:Head", "mixamorig_Head", "Head"):
			if name in arm.pose.bones:
				head_pb = arm.pose.bones[name]
				break
		for name in ("mixamorig:HeadTop_End", "mixamorig_HeadTop_End", "HeadTop_End"):
			if name in arm.pose.bones:
				top_pb = arm.pose.bones[name]
				break
		if head_pb is not None:
			head_pos = (arm.matrix_world @ head_pb.matrix).translation.copy()
			head_z = head_pos.z
			if top_pb is not None:
				top_pos = (arm.matrix_world @ top_pb.matrix).translation.copy()
				top_z = top_pos.z
				# Eyes sit ~35% of the way from Head toward HeadTop_End.
				look = head_pos.lerp(top_pos, 0.35)
			else:
				look = head_pos.copy()
				look.z += 0.025
	if look is None:
		deps = bpy.context.evaluated_depsgraph_get()
		eval_obj = mesh_obj.evaluated_get(deps)
		me = eval_obj.to_mesh()
		mw = mesh_obj.matrix_world
		pts = [mw @ v.co for v in me.vertices]
		eval_obj.to_mesh_clear()
		zs = [p.z for p in pts]
		z_cut = sorted(zs)[int(len(zs) * 0.82)]
		head = [p for p in pts if p.z >= z_cut]
		look = Vector((
			sum(p.x for p in head) / len(head),
			sum(p.y for p in head) / len(head),
			sum(p.z for p in head) / len(head),
		))
	candidates = [Vector((0, -1, 0)), Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((-1, 0, 0))]
	# Slightly wider ortho so lids + brows fit; eyes stay in upper half.
	return look, candidates, 0.32


def setup_front_ortho(look, face_fwd, ortho_scale):
	cam = bpy.data.objects.get("EyeCam")
	if cam is None:
		cam_data = bpy.data.cameras.new("EyeCam")
		cam_data.type = "ORTHO"
		cam = bpy.data.objects.new("EyeCam", cam_data)
		bpy.context.scene.collection.objects.link(cam)
	else:
		cam_data = cam.data
	cam_data.ortho_scale = ortho_scale
	dist = 0.65
	cam.location = look + face_fwd * dist
	cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Z").to_euler()
	bpy.context.scene.camera = cam
	world_up = Vector((0, 0, 1))
	right = face_fwd.cross(world_up)
	if right.length < 1e-4:
		right = Vector((1, 0, 0))
	else:
		right.normalize()
	for nm in ("EyeKey", "EyeFill"):
		o = bpy.data.objects.get(nm)
		if o:
			bpy.data.objects.remove(o, do_unlink=True)
	# Softer lights so iris/skin aren't blown out (helps detection + skin sample).
	light_data = bpy.data.lights.new("EyeKey", "AREA")
	light_data.energy = 40.0
	light_data.size = 0.55
	light = bpy.data.objects.new("EyeKey", light_data)
	bpy.context.scene.collection.objects.link(light)
	light.location = look + face_fwd * 0.4 + world_up * 0.15 + right * 0.12
	fill = bpy.data.lights.new("EyeFill", "AREA")
	fill.energy = 18.0
	fill.size = 0.7
	fill_o = bpy.data.objects.new("EyeFill", fill)
	bpy.context.scene.collection.objects.link(fill_o)
	fill_o.location = look + face_fwd * 0.3 - right * 0.18
	# Dim world
	if bpy.context.scene.world is None:
		bpy.context.scene.world = bpy.data.worlds.new("EyeWorld")
	bpy.context.scene.world.use_nodes = True
	bg = bpy.context.scene.world.node_tree.nodes.get("Background")
	if bg:
		bg.inputs[0].default_value = (0.02, 0.02, 0.02, 1)
		bg.inputs[1].default_value = 0.3
	return cam


def render_view(path):
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_EEVEE_NEXT"
	scene.render.resolution_x = RES
	scene.render.resolution_y = RES
	scene.render.resolution_percentage = 100
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_mode = "RGBA"
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("rendered", path)


def paint_closed_eyes_on_render(open_path, closed_path, mask_path):
	"""Detect L/R eyes in the upper face band and paint closed lids."""
	import numpy as np
	from PIL import Image, ImageFilter
	from scipy import ndimage

	im = Image.open(open_path).convert("RGBA")
	arr = np.array(im)
	rgb = arr[:, :, :3].astype(np.float32)
	h, w = rgb.shape[:2]
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	lum = 0.299 * r + 0.587 * g + 0.114 * b

	# Eyes: brown patches near skin that also have nearby sclera/specular.
	skin = (r > 190) & (g > 150) & (b > 120) & (r > b + 10)
	near_skin = ndimage.binary_dilation(skin, iterations=8)
	bright = (r > 230) & (g > 230) & (b > 220)
	brown = (
		(r > 45) & (r < 180) & (g > 25) & (g < 140) & (b < 120)
		& (r > g + 5) & (r > b + 18) & (lum > 35) & (lum < 150) & near_skin
	)
	brown = ndimage.binary_closing(ndimage.binary_opening(brown, iterations=1), iterations=2)
	lab, n = ndimage.label(brown)
	blobs = []
	for i in range(1, n + 1):
		ys, xs = np.where(lab == i)
		area = len(xs)
		if area < 100 or area > 8000:
			continue
		bw = xs.max() - xs.min() + 1
		bh = ys.max() - ys.min() + 1
		if bw < 18 or bh < 18 or bw > 160 or bh > 140:
			continue
		aspect = bw / max(bh, 1)
		if aspect < 0.5 or aspect > 2.0:
			continue
		cx, cy = float(xs.mean()), float(ys.mean())
		if cy < h * 0.12 or cy > h * 0.55:
			continue
		if cx < w * 0.15 or cx > w * 0.85:
			continue
		y0b = max(0, int(cy) - 40)
		y1b = min(h, int(cy) + 40)
		x0b = max(0, int(cx) - 50)
		x1b = min(w, int(cx) + 50)
		br = float(bright[y0b:y1b, x0b:x1b].mean())
		if br < 0.008:
			continue  # no catchlight/sclera — reject hair clumps
		roundness = area / float(max(bw * bh, 1))
		score = area * (1.0 + 30.0 * br) * (0.4 + roundness)
		blobs.append((score, area, cx, cy, bw, bh))
	blobs.sort(reverse=True)
	left = [b for b in blobs if b[2] < w * 0.5]
	right = [b for b in blobs if b[2] >= w * 0.5]
	print("eye L cands", [(int(b[2]), int(b[3]), int(b[1])) for b in left[:5]])
	print("eye R cands", [(int(b[2]), int(b[3]), int(b[1])) for b in right[:5]])
	best_pair = None
	for L in left[:8]:
		for R in right[:8]:
			dx = R[2] - L[2]
			dy = abs(L[3] - R[3])
			if dx < w * 0.12 or dx > w * 0.55:
				continue
			if dy > h * 0.10:
				continue
			score = -(L[0] + R[0]) + dy * 5.0
			if best_pair is None or score < best_pair[0]:
				best_pair = (score, L, R)
	if best_pair is None:
		raise SystemExit("No eye blobs found in front render — abort projection bake")
	L, R = best_pair[1], best_pair[2]
	picked = [("L", L[2], L[3], L[4], L[5]), ("R", R[2], R[3], R[4], R[5])]
	print("eye pair", [(int(p[1]), int(p[2]), int(p[3]), int(p[4])) for p in picked])

	# Build hard almond coverage + lid color, then soft-blur the mask once.
	lid_rgb = np.zeros_like(rgb)
	mask = np.zeros((h, w), dtype=np.float32)
	for side, ecx, ecy, bw, bh in picked:
		# Fixed lid size from iris size — do NOT flood from a giant bbox.
		# These Tripo eyes are large; cover the full socket generously.
		# Brown-blob centroids bias high (brow/upper lid) — nudge down onto the iris.
		ecy = ecy + max(14.0, 0.22 * max(bw, bh))
		iris_r = 0.5 * max(bw, bh)
		rx = max(iris_r * 1.95, 58.0)
		ry = max(iris_r * 1.55, 48.0)
		xa2 = max(0, int(ecx - rx - 6))
		xb2 = min(w - 1, int(ecx + rx + 6))
		ya2 = max(0, int(ecy - ry - 8))
		yb2 = min(h - 1, int(ecy + ry + 8))
		# Sample surrounding skin outside the iris disc
		skin_samples = []
		for yy in range(ya2, yb2 + 1):
			for xx in range(xa2, xb2 + 1):
				dx = (xx - ecx) / max(iris_r, 1)
				dy = (yy - ecy) / max(iris_r, 1)
				if dx * dx + dy * dy < 1.45:
					continue
				c = rgb[yy, xx]
				if c[0] > 150 and c[1] > 110 and c[2] > 90 and c[0] > c[2] + 8 and lum[yy, xx] > 140:
					skin_samples.append(c)
		if len(skin_samples) > 8:
			skin = np.mean(skin_samples, axis=0)
		else:
			skin = np.array([228.0, 185.0, 155.0])
		lash = np.array([42.0, 24.0, 16.0])
		crease = np.array([155.0, 115.0, 95.0])
		for yy in range(ya2, yb2 + 1):
			for xx in range(xa2, xb2 + 1):
				nx = (xx - ecx) / rx
				ny = (yy - ecy) / ry
				# Almond / closed-lid silhouette — solid cover (no see-through iris)
				almond = nx * nx * 1.02 + (ny * ny) * (1.20 + 0.35 * nx * nx)
				if almond > 1.05:
					continue
				# Almost opaque inside; soft only at outer rim
				edge = 1.0 if almond < 0.82 else max(0.0, min(1.0, (1.05 - almond) / 0.23))
				col = skin.copy()
				# Soft crease above lash
				if -0.75 < ny < -0.05:
					t = math.exp(-((ny + 0.40) ** 2) / 0.016) * (1.0 - 0.22 * abs(nx))
					col = col * (1 - 0.40 * t) + crease * (0.40 * t)
				# Soft curved lash (thinner, tapered at corners)
				lash_y = 0.06 + 0.10 * (nx * nx)  # slight smile curve
				if abs(ny - lash_y) < 0.28:
					t2 = math.exp(-((ny - lash_y) ** 2) / 0.006) * (1.0 - 0.55 * abs(nx) ** 1.6)
					col = col * (1 - 0.92 * t2) + lash * (0.92 * t2)
				# Soft lower lid shadow
				if 0.18 < ny < 0.65 and abs(nx) < 0.90:
					t3 = math.exp(-((ny - 0.34) ** 2) / 0.022) * 0.16 * (1.0 - 0.3 * abs(nx))
					col = col * (1 - t3) + lash * t3
				if edge >= mask[yy, xx]:
					lid_rgb[yy, xx] = col
					mask[yy, xx] = edge

	# Avoid black fringes when the mask softens past the hard almond.
	lid_rgb = np.where(mask[:, :, None] > 1e-3, lid_rgb, rgb)
	mask_img = Image.fromarray((mask * 255).astype(np.uint8), mode="L").filter(ImageFilter.GaussianBlur(1.1))
	mask = np.array(mask_img).astype(np.float32) / 255.0
	# Single blend: opaque lids over open eyes
	out = rgb * (1.0 - mask[:, :, None]) + lid_rgb * mask[:, :, None]
	closed = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), mode="RGB")
	closed.save(closed_path)
	mask_img.save(mask_path)
	print("wrote", closed_path, "eyes", len(picked),
		  [(int(p[1]), int(p[2])) for p in picked])
	return closed_path, mask_path, picked


def project_to_albedo(mesh_obj, cam, closed_path, mask_path, albedo_img):
	"""Raycast each mask pixel from the ortho camera onto the mesh UVs and paint."""
	import numpy as np
	from PIL import Image

	closed = np.array(Image.open(closed_path).convert("RGB")).astype(np.float32)
	mask = np.array(Image.open(mask_path).convert("L")).astype(np.float32) / 255.0
	rh, rw = closed.shape[:2]

	albedo_img.pixels[:]  # force load
	aw, ah = albedo_img.size[0], albedo_img.size[1]
	pix = np.array(albedo_img.pixels[:]).reshape(ah, aw, albedo_img.channels)
	out = pix.copy()

	scene = bpy.context.scene
	deps = bpy.context.evaluated_depsgraph_get()

	# Ortho camera basis
	mw_cam = cam.matrix_world
	cam_loc = mw_cam.translation.copy()
	# Blender camera looks down local -Z; local Y is up for our track_quat("-Z","Y")
	forward = (mw_cam.to_3x3() @ Vector((0, 0, -1))).normalized()
	cam_up = (mw_cam.to_3x3() @ Vector((0, 1, 0))).normalized()
	cam_right = (mw_cam.to_3x3() @ Vector((1, 0, 0))).normalized()
	ortho = cam.data.ortho_scale

	# Restrict hits to head-ish height (around look / eyes, not just hat crown).
	eval_obj = mesh_obj.evaluated_get(deps)
	me = eval_obj.to_mesh()
	mw = mesh_obj.matrix_world
	zs = [(mw @ v.co).z for v in me.vertices]
	z_hi = max(zs)
	# Face/eyes sit well below hat crown; keep everything above mid-torso.
	z_lo = sorted(zs)[int(len(zs) * 0.48)]
	eval_obj.to_mesh_clear()
	print("project z_lo", round(z_lo, 3), "z_hi", round(z_hi, 3))

	ys_m, xs_m = np.where(mask > 0.08)
	print("mask pixels", len(xs_m))

	written = 0
	miss = 0
	# Subsample densely but not every pixel if huge; eyes masks are small.
	step = 1 if len(xs_m) < 80000 else 2
	for yi, xi in zip(ys_m[::step], xs_m[::step]):
		m = float(mask[yi, xi])
		if m < 0.08:
			continue
		# Pixel → NDC (0..1), Blender camera view Y grows upward.
		ndc_x = (xi + 0.5) / rw
		ndc_y = 1.0 - (yi + 0.5) / rh
		# Ortho offset from camera center on the view plane
		ox = (ndc_x - 0.5) * ortho
		oy = (ndc_y - 0.5) * ortho
		origin = cam_loc + cam_right * ox + cam_up * oy - forward * 0.05
		# Ray cast
		hit, loc, _n, _fi, hit_obj, _m = scene.ray_cast(deps, origin, forward, distance=2.0)
		if not hit or hit_obj is None:
			miss += 1
			continue
		# Accept hits on our boy mesh (evaluated name may differ)
		hz = loc.z
		if hz < z_lo - 0.01:
			continue
		# Find UV via closest point on evaluated mesh
		ok, loc_on, norm, face_idx = hit_obj.closest_point_on_mesh(
			hit_obj.matrix_world.inverted() @ loc
		)
		if not ok or face_idx < 0:
			miss += 1
			continue
		# Get UV from the evaluated mesh polygon
		me2 = hit_obj.data
		if me2.uv_layers.active is None:
			continue
		poly = me2.polygons[face_idx]
		uv_layer = me2.uv_layers.active.data
		# Barycentric UV from triangle fan around poly (use first loop-tri of poly)
		# Build from poly loops
		loops = list(poly.loop_indices)
		if len(loops) < 3:
			continue
		# Use first 3 loops as a triangle approximation for UV; refine with barycentric in local space
		from mathutils.geometry import intersect_point_tri_2d, barycentric_transform

		# Better: project hit into poly's triangle fan
		v0 = me2.vertices[poly.vertices[0]].co
		uv0 = uv_layer[loops[0]].uv
		uu = vv = None
		local_hit = hit_obj.matrix_world.inverted() @ loc
		for k in range(1, len(poly.vertices) - 1):
			v1 = me2.vertices[poly.vertices[k]].co
			v2 = me2.vertices[poly.vertices[k + 1]].co
			uv1 = uv_layer[loops[k]].uv
			uv2 = uv_layer[loops[k + 1]].uv
			# barycentric in 3D
			try:
				# Convert point to barycentric weights via areas
				n = (v1 - v0).cross(v2 - v0)
				if n.length < 1e-12:
					continue
				n.normalize()
				a = (v1 - local_hit).cross(v2 - local_hit).dot(n)
				b = (v2 - local_hit).cross(v0 - local_hit).dot(n)
				c = (v0 - local_hit).cross(v1 - local_hit).dot(n)
				s = a + b + c
				if abs(s) < 1e-12:
					continue
				wa, wb, wc = a / s, b / s, c / s
				if wa < -0.05 or wb < -0.05 or wc < -0.05:
					continue
				uu = uv0.x * wa + uv1.x * wb + uv2.x * wc
				vv = uv0.y * wa + uv1.y * wb + uv2.y * wc
				break
			except Exception:
				continue
		if uu is None:
			# fallback: average UV of poly
			uus = [uv_layer[li].uv for li in loops]
			uu = sum(u.x for u in uus) / len(uus)
			vv = sum(u.y for u in uus) / len(uus)

		tx = int(uu * (aw - 1)) % aw
		ty = int(vv * (ah - 1)) % ah
		col = closed[yi, xi] / 255.0
		# Stamp a small UV neighborhood so fragmented islands fill solidly
		# (one ray per screen pixel otherwise leaves holes between islands).
		rad = 2 if m > 0.55 else 1
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if dx * dx + dy * dy > rad * rad + 0.5:
					continue
				px = (tx + dx) % aw
				py = (ty + dy) % ah
				wblend = m * (1.0 - 0.18 * (abs(dx) + abs(dy)))
				if wblend < 0.08:
					continue
				old = out[py, px, :3]
				out[py, px, :3] = old * (1.0 - wblend) + col * wblend
				if albedo_img.channels > 3:
					out[py, px, 3] = 1.0
				written += 1

	print("projected samples written", written, "miss", miss)
	flat = out.reshape(-1)
	albedo_img.pixels[:] = flat.tolist()
	albedo_img.filepath_raw = OUT_SLEEP
	albedo_img.file_format = "PNG"
	top = (np.clip(out[:, :, :3], 0, 1) * 255).astype(np.uint8)
	top = np.flipud(top)
	Image.fromarray(top, mode="RGB").save(OUT_SLEEP)
	print("saved", OUT_SLEEP)
	return written


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	clear_scene()
	arm, mesh = import_boy()
	albedo, _node = find_albedo_image(mesh)
	if albedo is None:
		raise SystemExit("no albedo image found")
	print("albedo", albedo.name, albedo.size[:])
	sleep_img = albedo.copy()
	sleep_img.name = "boy_tripo_sleep_eyes"
	look, candidates, ortho = face_look_target(mesh, arm)
	print("look", tuple(look), "ortho", ortho)
	best = None
	for fwd in candidates:
		print("try face_fwd", tuple(fwd))
		cam = setup_front_ortho(look, fwd, ortho)
		tag = "pY" if fwd.y > 0.5 else "nY" if fwd.y < -0.5 else ("pX" if fwd.x > 0.5 else "nX")
		trial = RENDER_OPEN.replace(".png", "_%s.png" % tag)
		render_view(trial)
		try:
			paint_closed_eyes_on_render(trial, RENDER_CLOSED, RENDER_MASK)
			shutil.copyfile(trial, RENDER_OPEN)
			best = (cam, fwd, trial)
			print("picked face_fwd", tuple(fwd))
			break
		except SystemExit as e:
			print("skip", fwd, e)
			continue
	if best is None:
		raise SystemExit("No face-forward candidate found eyes — projection bake failed")
	cam, face_fwd, _ = best
	n = project_to_albedo(mesh, cam, RENDER_CLOSED, RENDER_MASK, sleep_img)
	if n < 200:
		raise SystemExit("projection wrote too few samples (%d) — bake failed" % n)
	print("BAKE_OK", n, "face_fwd", tuple(face_fwd))


if __name__ == "__main__":
	main()
