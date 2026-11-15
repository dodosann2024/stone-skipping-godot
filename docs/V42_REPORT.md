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

Numbers below are from the exported page `docs/game_v42/game_v42.html` in Chrome at 390×844. The boy in that export is the approved 47,194-triangle `boy_flateyes` mesh. The 24,499-triangle decimation is not used: it sampled the wrong atlas islands and left dark blotches on the hat, vest and legs.

| Gate | Result | Evidence |
|---|---|---|
| A-5 drag, three frames, full shins and both sandals | **Pass on the exported page.** The walk frame from `game_v42.html` shows both sandals on the plank texture. The earlier three-frame drag on the editor build still shows the body on the planks. | `screenshots/v42/web/walk.png`, `screenshots/v42/drag/d41_a.png` |
| A-1 stance sole within ±1 cm on 110 m | **Pass, re-run after the palm row.** 5468 stance samples, **100%** inside ±1 cm. Skate max **0.56 cm**, walk skate **0.12 cm**. `shin_min=1.00`. | `screenshots/v42/m6/route.log` |
| A-2 ortho ruler stills | **34 stills.** Banner gap is 0.00 cm on 31 of them. The worst three are **0.24 cm**, **-0.04 cm**, and **-0.05 cm**, all inside 0.5 cm. The red tick is the zero line under the sole. | `screenshots/v42/a2/foot_00.png` … `foot_33.png`, `ruler.log` |
| B-1 skate ≤ 1 cm on a straight walk | **Pass.** Walk-segment max drift from the plant lock is **0.12 cm**. | same route log |
| Shin length ≥ 0.95 | **Pass.** `shin_min=1.00`. | same route log |
| C-1 first step ≤ 100 ms | **Pass on this machine.** A screen-touch at the stick, then a drag to full deflection, moved the body 2.81 cm in **67.5 ms** (2 frames). This is SwiftShader, not an iPhone. | log line `LATENCY_MS 67.5` |
| P-2 prims ≤ 93k | **Pass.** The compatibility renderer was drawing the 47,194-triangle boy a second time for the shadow. That pass is off. A flat contact disc sits under his feet. Palms past 16 m and bushes past 12 m swap to cards, so the near view stays dense. Face **54,014**. Pier **59,150**. Occlusion **58,510**. Throw **62,832**. | `screenshots/v42/web/face.png`, `pier.png`, `occ_on.png`, `throw_whip.png` |
| Boy mesh | **The approved model.** `rebuild/assets/boy.glb` is a real copy of `boy/boy.glb`: **47,194** triangles. Mesh LOD bias on the instances is 16 so the play camera stays on that mesh. Palms and pier posts do not cast shadows, and the water grid is 16×16, which is what keeps the close throw under 110k. | `screenshots/v42/web/face.png` |
| Face | Clean straw hat, flat eyes, red vest with three buttons, flower shorts. No dark atlas blotches. The sea behind him shows the wave normals. | `screenshots/v42/web/face.png` |
| M6 look vs v40 | **In the export.** Plank boards and the rope rail stay. The sea uses the v40 shallow / mid / deep / abyss colours, a depth ramp that goes dark past the pier, wave normals, a shore breaker and open-water lace. The sky blob on the drag was the distant-palm multimesh; that mesh is no longer in the scene. Extra palms, bushes, reeds, a second boat, a lantern, a crate and an umbrella fill the island out. | `screenshots/v42/web/spawn.png`, `pier.png`, `face.png` |
| M4 sit / lie / sun | **From the export.** The bench is slats, rails and legs, and he lies on the slats. The hammock is posts, sagging ropes and cloth, and he lies in the curve. | `screenshots/v42/web/bench_lie.png`, `hammock_rest.png` |
| M5 side-arm throw | **Six frames, 3/4 side, from the export.** Both sandals stay on the planks from windup through the stone leaving the hand. The arm stays low and out to the side. The last frame has the stone off the hand, low, continuing the arm line. | `screenshots/v42/web/throw_strip.jpg`, `throw_s0.png` … `throw_s5.png` |
| Near props | The pier lantern has a collision the spring arm stops on, and anything within 3.2 m of the camera, or sitting in the lower half of the screen within 6.5 m, fades to 35% and is not discarded. The orbit frame keeps the joystick clear. | `screenshots/v42/web/near.png` |
| O-6 cutout regression | **No discarded pixels.** Eight frames of the boy walking the dock at a 34° camera: the hut stays on the right, the palm and the bush stay in frame, and the bush is translucent rather than gone. It is still one palm beside the hut, not the iPhone's left-hand row of three. | `screenshots/v42/web/occ_strip.jpg`, `occ_on.png`, `occ_f0.png` … `occ_f7.png` |
| Walk p95 | **Not an iPhone number.** The drag debug line reads walk p95 **33.3 ms** on SwiftShader. | drag stills |
| M7 index.html | **Not switched.** `docs/index.html` still points at v35. | — |

## What changed for the dock

The 26 cm dock gap was a ray that missed a hole where terrain under the pier had been deleted, so the probe returned 0 while the body stood on the planks. The pier is now the same triangle list as the sand, with the deck and steps added on top. The foot probe and the body both read that body. Walk speed matches the clip (about 0.64 m/s at a strong walk stick) instead of playing the clip at 1.8×. The plant locks the stance foot in world space and lets go when the step ends. The release camera stays above the walk surface, so frame c no longer puts the body inside the deck.

## This pass

The throw keeps Foot IK on and weights both feet, so the soles stay on the deck while the hips drop and the spine twists. The throwing-side camera is what makes the short chibi arm read as a sidearm. The stone mesh sits in the hand for the windup and whip, and is placed ahead of the hand for the release and follow. The bench is a slatted seat with legs and a low back. The hammock is two posts, edge ropes that follow the sag, and a cloth surface; the sleep clip is aligned to that axis. The distant palm multimesh that read as a dark blob over the sea is gone. `boy/boy.glb` is unchanged. `docs/index.html` is unchanged.

The standing sentence is still in `docs/V42_SPEC.md`:

「耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。」
