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

| Gate | Result | Evidence |
|---|---|---|
| A-5 drag, three frames, full shins and both sandals | **Pass on the pictures.** All three frames show both sandals and the shins. Frame c is 0.8 s after release and the boy is still on the dock, whole body above the planks. | `screenshots/v42/drag/d41_a.png`, `d41_b.png`, `d41_c.png` |
| A-1 stance sole within ±1 cm on 110 m | **Pass.** 4564 stance samples, **100%** inside ±1 cm. Histogram bins are only `-1` (691) and `0` (3873). The route includes the dock, the sand, and the grass slope. | `screenshots/v42/m2/route.log` |
| A-2 ortho ruler stills | **Not run.** The drag pictures agree with a planted sole. | — |
| B-1 skate ≤ 1 cm on a straight walk | **Pass.** Walk-segment max drift from the plant lock is **0.12 cm**. | same log |
| Shin length ≥ 0.95 | **Pass** on this route. `shin_min=1.00`. | same log |
| C-1 first step ≤ 100 ms | **Not measured** on the touch path. | — |
| P-2 prims ≤ 110k | **Pass with shadows on**, on the dock drag: the debug line reads **98972** and **100606**. | `screenshots/v42/m6/d41_a.png`, `d41_c.png` |
| M6 look | Sand grain, wet shore, wood planks, water foam, palms, a stilt hut, a lighthouse, and a long sun shadow. Not yet the full v40 prop set, and the four spots were not shot from the old build in the same session. | `screenshots/v42/m6/v42_spawn.png`, `v42_pier.png`, `v42_hut.png`, `v42_hammock.png` |
| P-3 boy ≤ 25k triangles | **Fail.** The approved mesh is still 47,194 triangles. It was not decimated. | `docs/V42_SPEC.md` asset note |
| Walk p95 | **Not an iPhone number.** SwiftShader on this drag reports walk p95 **139.5–141.7 ms**. | drag stills |
| O-6 pier cutout regression | **No cut in the new stills.** Fade on and `occ` off at the pier / hut are the same picture: hut, bush, sign, and steps stay whole. This is not a pixel match of the old iPhone frame. | `screenshots/v42/m3/occ_on.png`, `occ_off.png`, reference `screenshots/v42/occlusion_bug_iphone.png` |
| M4 sit / lie / hammock | **Not met.** 坐下 only stops the stick. The bench/hammock clips are not driven. | — |
| M5 side-arm throw | **Not met.** 打水漂 spawns a sphere. There is no side-arm clip. | — |
| M6 water / night / audio polish | **Partial.** A flat water shader, a night toggle, and the ocean loop are wired. Not scored against F. | — |
| M7 index.html | **Not switched.** Waiting on a real iPhone pass that this build does not earn. | — |

## What changed for the dock

The 26 cm dock gap was a ray that missed a hole where terrain under the pier had been deleted, so the probe returned 0 while the body stood on the planks. The pier is now the same triangle list as the sand, with the deck and steps added on top. The foot probe and the body both read that body. Walk speed matches the clip (about 0.64 m/s at a strong walk stick) instead of playing the clip at 1.8×. The plant locks the stance foot in world space and lets go when the step ends. The release camera stays above the walk surface, so frame c no longer puts the body inside the deck.
