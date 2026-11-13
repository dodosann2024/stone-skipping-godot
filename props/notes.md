# v25 sit / log / hammock clips — notes

All clips were authored in Blender 5.0.1 on the real rig of `boy_flateyes_rigged.glb` (65 mixamorig bones) and baked at 24 fps
(IK/FK solver in `src/`, no procedural posing needed in the game). The game only has to play the clip with the boy node aligned
to the prop (see `alignment.json`).

## Files
- `../boy_v25_clips.glb` – boy with the 10 original Tripo clips (unchanged, verified identical after round trip, err < 1e-6) + 9 new:
  `bench_sit_enter/idle/exit`, `log_sit_enter/idle/exit`, `hammock_enter/sleep/exit` (19 animations). Armature node = identity, mesh/skin untouched.
- `bench_v25.glb`, `log_v25.glb` – reference prop geometry the clips were verified against (prop frame = Godot axes).
- `hammock_v25.glb` – cloth (84x28 grid, smooth, catenary sag, curled sides, blue/white stripe texture embedded, double sided) + spreader ropes
  + anchor rings at the game anchors (local ±1.8282, ∓0.046, 0). Glb animations `hammock_enter`, `hammock_sleep`, `hammock_exit`
  animate morph-target weights (cloth conforms to the boy; 24 fps, linear between keys every 3 frames) — play it in sync with the boy clip of the same name
  (same duration/fps). Morph targets: `occupied_sit`, `occupied_lie` (deep-sag shapes), `enter_NNN`, `exit_NNN`.
  Base mesh = EMPTY hammock.
- `hammock_v25_static.glb` – empty cloth + `occupied_sit` + `occupied_lie` morph targets only (no animation), for a simple blend (lerp weight when the boy sits/lies).
- `hammock_cloth_frames_fp16.npz` – lossless per-frame cloth vertex positions (hammock-local Godot coords, x/y/z, 2465 verts, float16) for enter/sleep/exit if you prefer
  to drive an ArrayMesh yourself (vertex order = glb cloth mesh order).
- `alignment.json` – prop frames, boy-root placement per clip (position in prop frame, yaw), end-of-clip root shift/yaw for the exits, sit positions, morph key list.
- `../clips_preview/*.png` – montages (rows = views, columns = times).
- `src/` – scripts used.

## How to place the boy (alignment.json)
Boy node transform in prop frame = translate(root_pos_prop) · rotY(root_yaw_deg) (yaw 0 → boy faces +Z), scale 1.35, y offset FLOOR_OFFSET = 0.0062*1.35.
- bench / log: prop origin = centre of seat on the ground axis; boy starts at (0,0,-0.50) yaw 0 (walks/turns/backs in himself), sits at z≈-0.05, facing -z (yaw 180).
  After `*_sit_exit` the boy stands facing -z (end_yaw_delta ≈ 179°) — add `end_root_shift_prop` to the root position and the yaw delta, then play idle.
- hammock: prop origin = midpoint of the anchors; boy starts at (0, terrain(0,0.63), 0.63) yaw 180 (inland side), sits at the middle and reclines with head toward +x.
  After the exit he stands at `after_exit.new_root_pos_prop`. Terrain must be the game terrain (feet are planted on `terr()` incl. slope ≈ 0.185 uphill at +z).
- loop clips (`*_idle`, `hammock_sleep`): 8 s; first frame == last frame of the previous enter clip; drop the duplicated last frame when looping.
- Root-motion in the clips is in the hips bone (the node itself does not move); the enter clips start at the idle pose and blend in, the exits end with a standing pose (not exactly the idle pose; cross-fade ~0.2 s to idle).

## REQUIRED prop changes in the game (important)
The boy (scale 1.35, chibi legs: thigh ≈ 0.24 m, shin+foot ≈ 0.29 m) cannot sit naturally on a 0.35 m seat with his feet on the ground
(thighs would slope ~40° and the hands cannot reach the seat). The clips are authored for:
- **bench**: seat top **0.22 m** (SEAT_TOP 0.35 → 0.22), seat depth 0.26 m, width 1.40, backrest on +z side starting 0.10 m above the seat. (In island.gd the bench sit target was `bench_top ... Vector3(0, seat_y+0.035, 0.28)` – the 0.28 offset is on the backrest side; the clip sits at z=-0.05 relative to the seat centre.)
- **log**: radius **0.12**, axis height 0.10 (top 0.22) instead of r 0.17 / top 0.35.
If the game keeps 0.35 the boy will float above/clip into the seat by 0.13 m; scale the props or re-run `src/run_bench.py`/`run_log.py` with a different SH (needs retuning).

## Measured results (authoring, 24 fps, every 4th frame)
- bench/log: min boy–prop clearance −0.7 … +1.6 mm (contact within ±2 mm, no penetration beyond 2 mm), foot min height −8 mm in the enter clip (during the 180° turn), ≥ −0.5 mm in idle/exit.
- hands rest on thighs/knees (hand verts inside thighs ≤ 1.5 cm for a handful of vertices); hand→seat is not used (arms too short).
- hammock: cloth–body checks use ray-parity “cloth vertex inside the body mesh”. Per-frame cloth (npz): sleep 0 inside, enter max 6.7 mm in 16 sampled frames (≤2 verts), exit max 5.6 mm (≤2 verts). The morph-target version (key every 3 frames) re-interpolates the cloth and may show up to ~2–5 cm of cloth vs shin overlap on a few vertices (enter 2.9–5.6 s, exit 0.9–2.4 s, i.e. while the legs swing in/out) — use the npz if that is visible.
- lying: back, hips and heels rest in the cradle with ~4–6 mm gap; hat brim: the hat is baked into the head mesh, the brim makes a ~0.19 m deep pouch of cloth under the head when lying; tilting the head does not remove it (hat not separable), so it is left as a natural-looking pillow dent. 1 cloth vertex touches the brim in some sleep frames (≤ 7 mm).

## Known issues / honest limits
- Hammock cloth is a baked conform (not a physics sim). During leg swing-in the legs are IN the cloth footprint (the hammock is only ±0.5 m wide and the boy’s legs are short), so the cloth pouches around the shins instead of the legs going over the rim; it looks fine but is not physical.
- While the feet stay planted (sit phase) shins/feet are excluded from the cloth-contact model; they hang in front of the cloth rim (visually verified).
- Frame-to-frame cloth steps up to 0.13 m occur when the legs lift off the ground (fast cloth swing, 2–3 frames).
- Hat/head collision with the hammock ropes is not modelled (ropes are behind the head in all views).
- Standing-turn clips use the sandals’ ANKLE_Y = 0.0929; on steep ground the feet are planted to the terrain function used in the authoring script (terr()).
- Bench/log idle includes alternating leg swing (0.012 m lift), head look-around, breathing.
