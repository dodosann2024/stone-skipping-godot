# v43 throw and shadow

Branch `cursor/v43-throw-shadow-d4ce`, cut from `main` at `c268fbd` (the merged v42). `docs/index.html` is unchanged and still points at v35. `docs/game_v42/` is untouched. This trial build is `docs/game_v43/game_v43.html`. It is not merged.

The spec is `docs/V43_SPEC.md`. The next version's requirements carry this sentence again:

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

Stills in `screenshots/v43/web/` are Chrome screenshots of that page at 390×844, after the export in this commit.

## Throw

Eight frames, 3/4 side, from `game_v43.html?debug=1&shot=throw_s0` through `throw_s7`.

The pose is driven by `SideArm` on the approved skeleton. The hips drop into a crouch and yaw first. The chest yaw lags, then passes the hips, with a forward lean. The right hand goes from behind the hip, out low at about knee height, then across the body, with a wrist snap on the way through. Both feet stay on the planks; the only root shift is a few centimetres of weight. FootIK is unchanged and still plants both soles.

The stone in the strip is a flat light-grey disc. It sits out from the hand through the load, then leaves on a straight line at `player.y + 0.40` (about knee height) toward the water. The stone the player actually throws uses the same flat grey mesh.

## Shadow

The 47,194-triangle body does not cast. A separate skinned copy, `rebuild/assets/boy_shadow.glb`, is 4,999 triangles and 3,314 vertices. It is parented to the same skeleton with `cast_shadow = SHADOWS_ONLY`, so the colour pass stays on the full mesh and the shadow pass draws the proxy once. The deck shader now samples the directional shadow, which is why the planks show a body shadow instead of a contact disc.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Throw strip | Eight frames. Crouch, arm from behind through a low sidearm into a follow-through, stone visible and leaving flat, both sandals on the planks. | `screenshots/v43/web/throw_s0.png` … `throw_s7.png`, `throw_strip.jpg` |
| Prims | Face **59,013**. Throw **63,393**. Both under 93k. The face count is about 5k above v42's no-shadow 54,014, which is the proxy drawn once, not a second pass of the 47k mesh. | `screenshots/v43/web/face.png`, `throw_s4.png` |
| Route, 110 m | **Pass.** 5469 stance samples, **100%** inside ±1 cm. Skate max **0.56 cm**, walk skate **0.11 cm**, `shin_min=1.00`. Grounding files were not edited. | `screenshots/v43/m6/route.log` |
| index.html | Still v35. | `docs/index.html` |
