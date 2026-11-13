#!/usr/bin/env python3
"""Add aggressive eyes_closed shape key: sink Tripo eye shells into brow/cheek plane."""
from __future__ import annotations

import json
import math
import os
import shutil
from collections import defaultdict

import bpy
import numpy as np
from mathutils import Vector
from PIL import Image, ImageDraw

GLB_IN = "/workspace/art/boy/tripo/boy_tripo_ORIG.glb"
# Prefer pristine original if present; else current
if not os.path.isfile(GLB_IN):
	GLB_IN = "/workspace/art/boy/tripo/boy_tripo.glb"
GLB_OUT = "/workspace/art/boy/tripo/boy_tripo.glb"
GAME_GLB = "/workspace/boy/boy.glb"
OUT_DIR = "/workspace/screenshots/v24"
RES = 1024
MORPH_NAME = "eyes_closed"


def clear_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def import_boy():
	bpy.ops.import_scene.gltf(filepath=GLB_IN)
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
	for pb in arm.pose.bones:
		pb.matrix_basis.identity()
	bpy.context.view_layer.update()
	return arm, mesh


def face_look_target(arm):
	head = arm.pose.bones.get("mixamorig:Head")
	top = arm.pose.bones.get("mixamorig:HeadTop_End")
	head_pos = (arm.matrix_world @ head.matrix).translation.copy()
	if top is not None:
		top_pos = (arm.matrix_world @ top.matrix).translation.copy()
		look = head_pos.lerp(top_pos, 0.35)
	else:
		look = head_pos.copy(); look.z += 0.025
	return look, Vector((0, -1, 0)), 0.32, head_pos


def setup_cam(look, face_fwd, ortho_scale):
	cam_data = bpy.data.cameras.new("EyeCam")
	cam_data.type = "ORTHO"
	cam_data.ortho_scale = ortho_scale
	cam = bpy.data.objects.new("EyeCam", cam_data)
	bpy.context.scene.collection.objects.link(cam)
	cam.location = look + face_fwd * 0.65
	cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Z").to_euler()
	bpy.context.scene.camera = cam
	world_up = Vector((0, 0, 1))
	right = face_fwd.cross(world_up).normalized()
	key = bpy.data.lights.new("EyeKey", "AREA"); key.energy = 40; key.size = 0.55
	key_o = bpy.data.objects.new("EyeKey", key)
	bpy.context.scene.collection.objects.link(key_o)
	key_o.location = look + face_fwd * 0.4 + world_up * 0.15 + right * 0.12
	if bpy.context.scene.world is None:
		bpy.context.scene.world = bpy.data.worlds.new("W")
	bpy.context.scene.world.use_nodes = True
	bg = bpy.context.scene.world.node_tree.nodes.get("Background")
	if bg:
		bg.inputs[0].default_value = (0.02, 0.02, 0.02, 1)
		bg.inputs[1].default_value = 0.3
	return cam


def render_view(path):
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_EEVEE_NEXT"
	sc.render.resolution_x = RES
	sc.render.resolution_y = RES
	sc.render.filepath = path
	sc.render.image_settings.file_format = "PNG"
	bpy.ops.render.render(write_still=True)
	print("rendered", path)


def detect_eyes(open_path):
	from scipy import ndimage
	im = Image.open(open_path).convert("RGBA")
	arr = np.array(im); rgb = arr[:, :, :3].astype(np.float32)
	h, w = rgb.shape[:2]
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	lum = 0.299 * r + 0.587 * g + 0.114 * b
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
		if area < 100 or area > 8000: continue
		bw = xs.max() - xs.min() + 1; bh = ys.max() - ys.min() + 1
		if bw < 18 or bh < 18 or bw > 160 or bh > 140: continue
		aspect = bw / max(bh, 1)
		if aspect < 0.5 or aspect > 2.0: continue
		cx, cy = float(xs.mean()), float(ys.mean())
		if cy < h * 0.12 or cy > h * 0.55: continue
		if cx < w * 0.15 or cx > w * 0.85: continue
		y0b, y1b = max(0, int(cy) - 40), min(h, int(cy) + 40)
		x0b, x1b = max(0, int(cx) - 50), min(w, int(cx) + 50)
		br = float(bright[y0b:y1b, x0b:x1b].mean())
		if br < 0.008: continue
		roundness = area / float(max(bw * bh, 1))
		score = area * (1.0 + 30.0 * br) * (0.4 + roundness)
		blobs.append((score, area, cx, cy, bw, bh))
	blobs.sort(reverse=True)
	left = [b for b in blobs if b[2] < w * 0.5]
	right = [b for b in blobs if b[2] >= w * 0.5]
	best = None
	for L in left[:8]:
		for R in right[:8]:
			dx = R[2] - L[2]; dy = abs(L[3] - R[3])
			if dx < w * 0.12 or dx > w * 0.55 or dy > h * 0.10: continue
			score = -(L[0] + R[0]) + dy * 5.0
			if best is None or score < best[0]:
				best = (score, L, R)
	if best is None:
		raise SystemExit("no eyes")
	picked = []
	for side, B in (("L", best[1]), ("R", best[2])):
		ecx, ecy, bw, bh = B[2], B[3], B[4], B[5]
		ecy = ecy + max(14.0, 0.22 * max(bw, bh))
		iris_r = 0.5 * max(bw, bh)
		picked.append({
			"side": side, "cx": ecx, "cy": ecy,
			"rx": max(iris_r * 1.95, 55.0), "ry": max(iris_r * 1.55, 45.0),
		})
	dbg = im.convert("RGB"); draw = ImageDraw.Draw(dbg)
	for p in picked:
		draw.ellipse([p["cx"]-p["rx"], p["cy"]-p["ry"], p["cx"]+p["rx"], p["cy"]+p["ry"]], outline=(0,255,0), width=2)
	dbg.save(os.path.join(OUT_DIR, "_morph2_detect.png"))
	print("eyes", [(p["side"], int(p["cx"]), int(p["cy"])) for p in picked])
	return picked, (w, h)


def cam_ray(cam, px, py, rw, rh):
	mw = cam.matrix_world
	fwd = (mw.to_3x3() @ Vector((0, 0, -1))).normalized()
	up = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
	right = (mw.to_3x3() @ Vector((1, 0, 0))).normalized()
	ortho = cam.data.ortho_scale
	nx = (px + 0.5) / rw * 2.0 - 1.0
	ny = 1.0 - (py + 0.5) / rh * 2.0
	origin = mw.translation + right * (nx * 0.5 * ortho) + up * (ny * 0.5 * ortho) - fwd * 0.02
	return origin, fwd


def collect_and_grow(mesh_obj, cam, eyes, rw, rh, face_fwd):
	scene = bpy.context.scene
	deps = bpy.context.evaluated_depsgraph_get()
	me = mesh_obj.data
	mw = mesh_obj.matrix_world
	imw = mw.inverted()
	adj = defaultdict(set)
	for e in me.edges:
		a, b = e.vertices; adj[a].add(b); adj[b].add(a)
	# Precompute world verts
	wpos = [mw @ v.co for v in me.vertices]
	eye_sets = {}
	for e in eyes:
		side = e["side"]
		seeds = set()
		centers = []
		for iy in range(32):
			for ix in range(32):
				nx = (ix + 0.5) / 32 * 2 - 1
				ny = (iy + 0.5) / 32 * 2 - 1
				if nx*nx + (ny*ny)*(1.15 + 0.25*nx*nx) > 1.0:
					continue
				px = e["cx"] + nx * e["rx"]
				py = e["cy"] + ny * e["ry"]
				origin, direction = cam_ray(cam, px, py, rw, rh)
				ok, loc, _n, _fi, obj, _m = scene.ray_cast(deps, origin, direction, distance=2.0)
				if not ok:
					continue
				local = imw @ loc
				best_i, best_d = None, 1e9
				# local search near hit — sample every vert is slow; use spatial bucket
				# For ~20k verts ok once:
				for i, p in enumerate(wpos):
					d = (p - loc).length_squared
					if d < best_d:
						best_d = d; best_i = i
				if best_i is not None and best_d < 0.005**2:
					seeds.add(best_i)
					centers.append(loc)
		if not centers:
			print(side, "NO HITS"); eye_sets[side] = set(); continue
		center = sum(centers, Vector((0,0,0))) / len(centers)
		# Grow: include verts within radius that protrude along face_fwd from cheek depth
		selected = set(seeds)
		frontier = set(seeds)
		for _hop in range(8):
			nxt = set()
			for vi in frontier:
				for nj in adj[vi]:
					if nj in selected: continue
					p = wpos[nj]
					if (p - center).length > 0.048: continue
					# keep forward hemisphere
					if (p - center).dot(-face_fwd) < -0.015: continue
					selected.add(nj); nxt.add(nj)
			frontier = nxt
			if not frontier: break
		eye_sets[side] = selected
		print(side, "seeds", len(seeds), "grown", len(selected), "center", [round(c,4) for c in center])
	return eye_sets, wpos, adj


def fit_plane(points):
	c = sum(points, Vector((0,0,0))) / len(points)
	xx=xy=xz=yy=yz=zz=0.0
	for p in points:
		d = p - c
		xx += d.x*d.x; xy += d.x*d.y; xz += d.x*d.z
		yy += d.y*d.y; yz += d.y*d.z; zz += d.z*d.z
	mat = np.array([[xx,xy,xz],[xy,yy,yz],[xz,yz,zz]], dtype=np.float64)
	w, v = np.linalg.eigh(mat)
	n = Vector(v[:,0].tolist()).normalized()
	return c, n


def build_shape_key(mesh_obj, eye_sets, wpos, adj, face_fwd):
	me = mesh_obj.data
	mw = mesh_obj.matrix_world
	imw = mw.inverted()
	if me.shape_keys is None:
		mesh_obj.shape_key_add(name="Basis", from_mix=False)
	else:
		kb = me.shape_keys.key_blocks
		if MORPH_NAME in kb:
			mesh_obj.shape_key_remove(kb[MORPH_NAME])
	sk = mesh_obj.shape_key_add(name=MORPH_NAME, from_mix=False)
	sk.value = 0.0

	world_up = Vector((0, 0, 1))
	right_axis = face_fwd.cross(world_up).normalized()
	up_axis = right_axis.cross(face_fwd).normalized()

	moved = 0
	max_push = 0.0
	for side, idxs in eye_sets.items():
		if len(idxs) < 8:
			continue
		pts = [wpos[i] for i in idxs]
		center = sum(pts, Vector((0,0,0))) / len(pts)
		# Surrounding FACE plane from ring just outside the shell (brow/cheek),
		# NOT the shell rim (which sits on the bulb equator).
		halo = set()
		for vi in idxs:
			for n in adj[vi]:
				if n not in idxs:
					halo.add(n)
		# Expand halo one more ring for a stable cheek/brow fit
		halo2 = set(halo)
		for vi in list(halo):
			for n in adj[vi]:
				if n not in idxs:
					halo2.add(n)
		# Prefer halo verts that are BEHIND the shell apex along face_fwd
		apex_depth = min((wpos[i]).dot(-face_fwd) for i in idxs)  # most forward = min if face_fwd=(0,-1,0) wait
		# face_fwd points toward camera from face, so forward protrusion has larger (-face_fwd)·p? 
		# p more negative Y when face_fwd=(0,-1): protrusion has smaller p.y → larger p·face_fwd? 
		# face_fwd=(0,-1), p.y=-0.11 → p·face_fwd = 0.11. Cheek p.y=-0.10 → 0.10. Apex has HIGHER dot with face_fwd.
		face_pts = []
		for i in halo2:
			p = wpos[i]
			# exclude anything still as forward as the shell mid
			if p.dot(face_fwd) > center.dot(face_fwd) - 0.002:
				# still too far forward — skip
				continue
			face_pts.append(p)
		if len(face_pts) < 8:
			face_pts = [wpos[i] for i in halo2]
		plane_c, plane_n = fit_plane(face_pts)
		if plane_n.dot(face_fwd) < 0:
			plane_n = -plane_n
		# Sink further into the head so no residual lens remains
		sink = 0.004  # 4 mm into the face past the cheek plane
		radii = [(p - center).length for p in pts]
		R = max(sorted(radii)[len(radii)//2], 0.012)
		print(side, "verts", len(idxs), "face_pts", len(face_pts), "R", round(R,4),
			  "plane_n", [round(x,3) for x in plane_n],
			  "center_depth", round(center.dot(face_fwd),4),
			  "plane_depth", round(plane_c.dot(face_fwd),4))

		for vi in idxs:
			p = wpos[vi]
			d = p - center
			u = d.dot(right_axis) / R
			v = d.dot(up_axis) / R
			almond = u*u + (v*v)*(1.1 + 0.25*u*u)
			# weight: full interior, soft at edge
			w = 1.0 if almond < 1.05 else max(0.0, 1.0 - (almond - 1.05) / 0.4)
			if w <= 0.0:
				continue
			dist = (p - plane_c).dot(plane_n)  # positive = in front of plane
			# Closed lid profile: almost flush, slight crease dip near mid
			crease = math.exp(-((v - 0.08)**2) / 0.035) * (1.0 - 0.35 * abs(u))
			thickness = 0.0006 - 0.0014 * crease
			# Project fully onto sunk plane
			target = p - plane_n * (dist + sink - thickness)
			new_p = p.lerp(target, w)
			sk.data[vi].co = imw @ new_p
			max_push = max(max_push, (new_p - p).length)
			moved += 1

		# Soft blend halo so no hard cliff
		for vi in halo:
			p = wpos[vi]
			dist = (p - plane_c).dot(plane_n)
			if dist < 0.0005:
				continue
			target = p - plane_n * (dist * 0.65 + sink * 0.35)
			sk.data[vi].co = imw @ p.lerp(target, 0.7)
			moved += 1
			max_push = max(max_push, abs(dist) * 0.7)

	print("shape key", MORPH_NAME, "moved", moved, "max_push_m", round(max_push, 5))
	return sk


def export_glb(arm, mesh):
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True); mesh.select_set(True)
	bpy.context.view_layer.objects.active = arm
	if mesh.data.shape_keys:
		for kb in mesh.data.shape_keys.key_blocks:
			kb.value = 0.0
	tmp = "/tmp/boy_tripo_morph2.glb"
	bpy.ops.export_scene.gltf(
		filepath=tmp, export_format="GLB", use_selection=True,
		export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
		export_force_sampling=True, export_frame_step=1, export_skins=True,
		export_yup=True, export_texcoords=True, export_normals=True,
		export_materials="EXPORT", export_image_format="JPEG",
		export_jpeg_quality=85, export_rest_position_armature=True,
		export_morph=True, export_morph_normal=True, export_morph_tangent=False,
	)
	shutil.copy2(tmp, GLB_OUT)
	shutil.copy2(tmp, GAME_GLB)
	print("exported", os.path.getsize(GLB_OUT))


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	# Restore original GLB if we overwrote it earlier without backup
	src_backup = "/workspace/art/boy/tripo/boy_tripo_ORIG.glb"
	# If current GLB already has morph, try to use git version as clean source
	clear_scene()
	arm, mesh = import_boy()
	# Strip existing morph so we rebuild from Basis
	if mesh.data.shape_keys:
		# Apply nothing; remove all keys and recreate from current geometry
		mesh.shape_key_clear()
	look, face_fwd, ortho, head_pos = face_look_target(arm)
	cam = setup_cam(look, face_fwd, ortho)
	path = os.path.join(OUT_DIR, "_morph2_open.png")
	render_view(path)
	eyes, (rw, rh) = detect_eyes(path)
	eye_sets, wpos, adj = collect_and_grow(mesh, cam, eyes, rw, rh, face_fwd)
	build_shape_key(mesh, eye_sets, wpos, adj, face_fwd)
	# Preview with morph=1 AND try to show sleep albedo if available
	kb = mesh.data.shape_keys.key_blocks[MORPH_NAME]
	kb.value = 1.0
	bpy.context.view_layer.update()
	# Keep camera at front
	render_view(os.path.join(OUT_DIR, "_morph2_closed_front.png"))
	right = face_fwd.cross(Vector((0,0,1))).normalized()
	cam.location = look + face_fwd * 0.55 + right * 0.32
	cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Z").to_euler()
	render_view(os.path.join(OUT_DIR, "_morph2_closed_34.png"))
	kb.value = 0.0
	export_glb(arm, mesh)
	print("DONE")


if __name__ == "__main__":
	# Prefer git original GLB without morph for clean Basis
	import subprocess
	os.makedirs("/workspace/art/boy/tripo", exist_ok=True)
	# Extract original from git if needed
	r = subprocess.run(
		["git", "show", "HEAD:art/boy/tripo/boy_tripo.glb"],
		capture_output=True,
	)
	# HEAD may already be morph version; use commit before morph
	r2 = subprocess.run(
		["git", "show", "7e063f1:art/boy/tripo/boy_tripo.glb"],
		capture_output=True,
	)
	if r2.returncode == 0 and len(r2.stdout) > 1000:
		open("/workspace/art/boy/tripo/boy_tripo_ORIG.glb", "wb").write(r2.stdout)
		print("restored ORIG from 7e063f1", len(r2.stdout))
	main()
