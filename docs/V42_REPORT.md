# v42 rebuild report

Branch `cursor/rebuild-r1-d4ce`, cut from `main` at `38d0351`. PR #43 was not updated. `docs/index.html` is unchanged and still points at v35.

The spec is `docs/V42_SPEC.md` (the rebuild requirements, including the standing sentence):

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

The new game lives in `rebuild/` and exports to `docs/game_v42/`. Trial path: `docs/game_v42/game_v42.html`. Old gameplay code was not patched.

## What is in the tree

- One walk surface: `rebuild/world/ground.gd` bakes the island height into a mesh and sets the concave shape from `mesh.get_faces()`.
- One root writer: `PlayerBody.move_and_slide`.
- Stance IK in skeleton space (`FootIK`). Shin length on the 110 m route stayed **1.00**. The v41 failure mode (orthonormalizing a world basis and writing it back, which drops the ×1.35 scale) is not in this solver.
- Camera pitch default is 35°. Occluders are separate meshes with a per-mesh alpha, minimum 0.35. There is no discard / dither cutout shader. `?occ=0` turns the fader off.
- Chinese HUD, loading shell, debug panel (`?debug=1`) with walk p95 and a 复制数据 button.

## Gates

Numbers below are from the decimated boy (24,499 triangles), except the face pair, which is the 47,194-triangle mesh and the 24,499-triangle mesh from the same camera.

| Gate | Result | Evidence |
|---|---|---|
| A-5 drag, three frames, full shins and both sandals | **Pass on the pictures.** Frame a shows both sandals on the dock planks. Frame c is the wide frame 0.8 s after the stick is released; the body is on the planks, not inside them. | `screenshots/v42/drag/d41_a.png`, `d41_b.png`, `d41_c.png` |
| A-1 stance sole within ±1 cm on 110 m | **Pass.** 4963 stance samples, **100%** inside ±1 cm. Histogram bins are only `-1` (695) and `0` (4268). | `screenshots/v42/m6/route.log` |
| A-2 ortho ruler stills | **34 stills.** Banner gap is 0.00 cm on 31 of them. The worst three are **0.24 cm**, **-0.04 cm**, and **-0.05 cm**, all inside 0.5 cm. The red tick is the zero line under the sole. | `screenshots/v42/a2/foot_00.png` … `foot_33.png`, `ruler.log` |
| B-1 skate ≤ 1 cm on a straight walk | **Pass.** Walk-segment max drift from the plant lock is **0.14 cm**. | same route log |
| Shin length ≥ 0.95 | **Pass.** `shin_min=1.00`. | same route log |
| C-1 first step ≤ 100 ms | **Pass on this machine.** A screen-touch at the stick, then a drag to full deflection, moved the body 2.81 cm in **67.5 ms** (2 frames). This is SwiftShader, not an iPhone. | log line `LATENCY_MS 67.5` |
| P-2 prims ≤ 110k | **Pass on the play camera, fail on the close occlusion camera.** Dock drag, shadows on: **54474** and **54476**. The close behind-the-boy frame reads **149994**. | drag stills; `screenshots/v42/m3/occ_match_on.png` |
| P-3 boy ≤ 25k triangles | **Pass.** `rebuild/assets/boy.glb` is a real file (not the symlink) with **24,499** triangles and **14,162** vertices. The source `boy/boy.glb` is still 47,194. UVs and joints were copied from the surviving vertices; head-weighted vertices kept their old positions. | `rebuild/tools/decimate_boy.py` |
| Face after the decimation | The two close-ups are the same boy. Straw hat, eyes, buttons, and the flower shorts are intact at this distance. | `screenshots/v42/m6/face_full.png`, `face_lod.png` |
| M6 look vs v40 | **Not at v40.** The four pairs are in `screenshots/v42/m6/`. v40 has barrels, rope, a built hut, dense palms, and a real boat. v42 has a plank shader, sand grain, jade water, simple palms, a box hut, and a small boat. | `v40_spawn.png` / `v42_spawn.png`, and the pier, hut, and hammock pairs |
| M4 sit / lie / sun | **Partial.** Bench and log play `bench_sit_idle` / `log_sit_idle`; the side stills show him seated with his face in profile. The lie modifier does not read as a recline in `Bench_lie.png`. `hammock_sleep` plays, but `Hammock_idle.png` is inside the hut wall. The towel still shows him on his back on the red towel. | `screenshots/v42/m4/` |
| M5 side-arm throw | **Partial.** There is no side-arm clip in the library (`pitch_baseball` is unused). A two-bone arm arc plays instead. The stills show an arm out to the side, and the crouch is only a small knee bend. A standing throw settled at **12 skips and 37.0 m**. The record line updates and is written to `user://settings.cfg`. Splash audio is a short generated wave. | `screenshots/v42/m5/throw_stand.png`, `throw_crouch.png` |
| O-6 cutout regression | **No holes in this pair.** Fade on and fade off are the same picture: the boy, the planks, and the bush stay whole. It is a behind-the-boy dock frame. It is not the iPhone composition (hut on the right, palm row on the left). | `screenshots/v42/m3/occ_match_on.png`, `occ_match_off.png`, reference `occlusion_bug_iphone.png` |
| Walk p95 | **Not an iPhone number.** The drag debug line reads walk p95 **33.3 ms** on SwiftShader. | drag stills |
| M7 index.html | **Not switched.** `docs/index.html` still points at v35. | — |

## What changed for the dock

The 26 cm dock gap was a ray that missed a hole where terrain under the pier had been deleted, so the probe returned 0 while the body stood on the planks. The pier is now the same triangle list as the sand, with the deck and steps added on top. The foot probe and the body both read that body. Walk speed matches the clip (about 0.64 m/s at a strong walk stick) instead of playing the clip at 1.8×. The plant locks the stance foot in world space and lets go when the step ends. The release camera stays above the walk surface, so frame c no longer puts the body inside the deck.

## This pass

Rest and throw pause the foot IK so the clips can keep their hip offset. Bench, log, and the three fire logs use the authored sit clips. The towel and the lounger tip the model onto its back because those clips do not exist. The throw is a skeleton-space two-bone arc on the right arm, with the left hand pointing out and then tucking in. The stone is kinematic: a shallow hit bounces, a steep hit sinks, and each bounce plays the splash. The decimated boy replaces the symlink at `rebuild/assets/boy.glb`. `boy/boy.glb` is unchanged. `docs/index.html` is unchanged.
