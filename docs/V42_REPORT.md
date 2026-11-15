# v42 rebuild report

Branch `cursor/rebuild-r1-d4ce`, cut from `main` at `38d0351`. PR #43 was not updated. `docs/index.html` is unchanged and still points at v35.

The spec is `docs/V42_SPEC.md` (the rebuild requirements, including the standing sentence):

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

The new game lives in `rebuild/` and the playable build is `docs/game_v42/`. Trial path: `docs/game_v42/game_v42.html`. The stills in `screenshots/v42/web/` are screenshots of that page in Chrome at 390×844, after the export in this commit. Old gameplay code was not patched.

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
| A-5 drag, three frames, full shins and both sandals | **Pass on the exported page.** The walk frame from `game_v42.html` shows both sandals on the plank texture. The earlier three-frame drag on the editor build still shows the body on the planks. | `screenshots/v42/web/walk.png`, `screenshots/v42/drag/d41_a.png` |
| A-1 stance sole within ±1 cm on 110 m | **Pass, re-run after this export.** 5476 stance samples, **100%** inside ±1 cm. Walk skate **0.14 cm**. `shin_min=1.00`. | `screenshots/v42/m6/route.log` |
| A-2 ortho ruler stills | **34 stills.** Banner gap is 0.00 cm on 31 of them. The worst three are **0.24 cm**, **-0.04 cm**, and **-0.05 cm**, all inside 0.5 cm. The red tick is the zero line under the sole. | `screenshots/v42/a2/foot_00.png` … `foot_33.png`, `ruler.log` |
| B-1 skate ≤ 1 cm on a straight walk | **Pass.** Walk-segment max drift from the plant lock is **0.14 cm**. | same route log |
| Shin length ≥ 0.95 | **Pass.** `shin_min=1.00`. | same route log |
| C-1 first step ≤ 100 ms | **Pass on this machine.** A screen-touch at the stick, then a drag to full deflection, moved the body 2.81 cm in **67.5 ms** (2 frames). This is SwiftShader, not an iPhone. | log line `LATENCY_MS 67.5` |
| P-2 prims ≤ 110k | **Pass on the exported page, shadows on.** Wide pier view **33294**. Throw close-up **55442**. Hut view **58812**. Behind-the-boy view **58662**. | `screenshots/v42/web/spawn.png`, `throw_whip.png`, `hut.png`, `occ_on.png` |
| P-3 boy ≤ 25k triangles | **Pass.** `rebuild/assets/boy.glb` is a real file (not the symlink) with **24,499** triangles and **14,162** vertices. The source `boy/boy.glb` is still 47,194. UVs and joints were copied from the surviving vertices; head-weighted vertices kept their old positions. | `rebuild/tools/decimate_boy.py` |
| Face after the decimation | The two close-ups are the same boy. Straw hat, eyes, buttons, and the flower shorts are intact at this distance. | `screenshots/v42/m6/face_full.png`, `face_lod.png` |
| M6 look vs v40 | **In the export.** The pier is the mip-mapped board texture, the sea has depth colour and lace, the pier has a rope rail, and the hut has plank walls, a thatched roof, a sign reading 钓鱼小屋, a blue door, a porch and a lantern. v40 still has denser foliage and a more finished boat. | `screenshots/v42/web/spawn.png`, `hut.png`. v40 pairs stay in `screenshots/v42/m6/v40_*.png` |
| M4 sit / lie / sun | **From the export.** The hammock is on the open beach and he lies in the cloth. Bench and lounger use the lie clips. | `screenshots/v42/web/hammock_rest.png`, `bench_lie.png`, `lounger.png` |
| M5 side-arm throw | **From the export, 3/4 camera.** The whip frame has the throwing arm back and the knees bent. The release frame has the arm extended and the torso turned. The crouch frame is low, with the arm out to the side. The follow frame brings the arm across the chest. | `screenshots/v42/web/throw_whip.png`, `throw_release.png`, `throw_crouch.png`, `throw_follow.png` |
| O-6 cutout regression | **No holes on the export.** Fade on and fade off are the same frame from behind the boy: planks, rope posts, and the bush stay whole. It is not a pixel copy of the iPhone hut-and-palm-row frame. | `screenshots/v42/web/occ_on.png`, `occ_off.png` |
| Walk p95 | **Not an iPhone number.** The drag debug line reads walk p95 **33.3 ms** on SwiftShader. | drag stills |
| M7 index.html | **Not switched.** `docs/index.html` still points at v35. | — |

## What changed for the dock

The 26 cm dock gap was a ray that missed a hole where terrain under the pier had been deleted, so the probe returned 0 while the body stood on the planks. The pier is now the same triangle list as the sand, with the deck and steps added on top. The foot probe and the body both read that body. Walk speed matches the clip (about 0.64 m/s at a strong walk stick) instead of playing the clip at 1.8×. The plant locks the stance foot in world space and lets go when the step ends. The release camera stays above the walk surface, so frame c no longer puts the body inside the deck.

## This pass

Rest and throw pause the foot IK so a clip can hold the hips. Bench, log, and the three fire logs use the library sit clips. `bench_lie` and `lounger_lie` add spine and leg keys on top of that sit. `throw_stand` and `throw_crouch` are full-body keys (hips, spine, both arms, both legs). The stone is still kinematic. The dock samples `assets/tex/planks.jpg` with mipmaps and anisotropic filtering. Shadows are one cascade so the close camera stays under 110k. The decimated boy replaces the symlink at `rebuild/assets/boy.glb`. `boy/boy.glb` is unchanged. `docs/index.html` is unchanged.
