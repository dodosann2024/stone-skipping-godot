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
| A-5 drag, three frames, full shins and both sandals | **Fail.** Frame a shows both sandals. Frame b shows one sandal clearly. Frame c, 0.8 s after release, sinks the body into the deck; only the hat and shoulders remain. | `screenshots/v42/drag/d41_a.png`, `d41_b.png`, `d41_c.png` |
| A-1 stance sole within ±1 cm on 110 m | **Fail.** 2389 stance samples, **0.1%** inside ±1 cm. Typical gap on the dock is about +26 cm. Bins above +160 cm are rays that missed and returned 0. | `screenshots/v42/m2/route.log` (`ROUTE_DONE m=110.0 stance=2389 in_1cm=0.1 skate_max_cm=1.20 shin_min=1.00`) |
| A-2 ortho ruler stills | **Not run.** The numeric test already disagrees with a planted foot, so stills were not used to paper over it. | — |
| B-1 skate ≤ 1 cm over a stance | **Fail.** Max recorded skate **1.20 cm**. | same log |
| Shin length ≥ 0.95 | **Pass** on this route. `shin_min=1.00`. | same log |
| C-1 first step ≤ 100 ms | **Not measured** on the touch path. | — |
| P-2 prims ≤ 110k | **Pass on the drag shot** after the sun shadow was turned off: the debug line reads **51682**. | drag stills |
| P-3 boy ≤ 25k triangles | **Fail.** The approved mesh is still 47,194 triangles. It was not decimated. | `docs/V42_SPEC.md` asset note |
| Walk p95 | **Not an iPhone number.** SwiftShader on this drag reports walk p95 **139.5–141.7 ms**. | drag stills |
| O-6 pier cutout regression | **Not reproduced as a pass.** The reference shot is saved. The new fader does not discard fragments, but the drag never framed the hut and palms, and there is no id-color on/off pair. | `screenshots/v42/occlusion_bug_iphone.png` |
| M4 sit / lie / hammock | **Not met.** 坐下 only stops the stick. The bench/hammock clips are not driven. | — |
| M5 side-arm throw | **Not met.** 打水漂 spawns a sphere. There is no side-arm clip. | — |
| M6 water / night / audio polish | **Partial.** A flat water shader, a night toggle, and the ocean loop are wired. Not scored against F. | — |
| M7 index.html | **Not switched.** Waiting on a real iPhone pass that this build does not earn. | — |

## Why the foot number and the pictures disagree

On the dock the stance sample sits about 26 cm above the deck while the drag stills show a sandal near the wood. The harness ray and the picture are not measuring the same contact. Per the spec, the picture wins: the feet are not accepted as planted, and the 0.1% figure is not a license to move the threshold.

Frame c is the clearer failure. Pulling the arm back to 8.8 m puts the camera where the deck mesh covers the body. That is a camera-versus-mesh bug, not a passing wide shot.
