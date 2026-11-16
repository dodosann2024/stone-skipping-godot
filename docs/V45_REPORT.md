# v45 smoothness

Branch `cursor/v45-smooth-d4ce`, cut from v44 `2ef717e`. `docs/index.html` still points at v35. Trial build: `docs/game_v45/game_v45.html`. Not merged.

The spec, including the standing sentence, is `docs/V45_SPEC.md`:

> “耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。”

Stills are Chrome screenshots of that page at 390×844. The monitors below are Godot's, printed from the export (`PROFILE` on the console, and the in-game 帧时间 overlay). Textures stay uncompressed. The grounding files were not edited.

## What the frame actually costs

Before any cut, on the same SwiftShader export path, a walk up the path (`loc_4`) was **123–131 ms**, **48 then 67** visible draw calls, **58,880 then 67,042** visible prims, shadow prims **5,361–7,199**, physics **0.9–1.2 ms**. Shadow draw calls read **0** on this renderer even while shadow prims were counted. `TIME_PROCESS` read **250–285 ms** and does not match the frame delta, so the pacing number is the frame delta.

A 120-frame walk averaged **131.4 ms**, p95 **145.4 ms**.

After the cuts (cheaper sea and ground on the web build, shadow distance 9 m, shadow map 1024 and a hard filter, sea mesh 16×16, no fresh ripple array each frame, occluder rays every other frame, joystick redraw only when the knob moves):

| Shot | Frame ms | Visible draws | Visible prims | Shadow prims | Physics ms |
|---|---|---|---|---|---|
| Walk up the path (`loc_4`) | 135.9 | 67 | 73,370 | 6,493 | 1.4 |
| Throw (`throw_s2`) | 130.8 | 52 | 65,208 | 5,361 | 0.4 |
| Skip (`skip_2` overlay) | 128.8 | — | 52,988 | — | — |

The paced walk after the cuts averaged **132.4 ms**, p95 **144.9 ms**. Graph: `screenshots/v45/m6/pacing.png`.

SwiftShader did not get faster. Draw calls stayed in the 50–70 range. The boy is still most of the triangles. The cheaper sea removed lace work and did not move a 130 ms software frame. These numbers are not an iPhone. The 帧时间 button toggles the same overlay in the build so a phone can show its own frame time.

## Smoothness

Physics stays at 60 ticks with render interpolation on. Teleports call `reset_physics_interpolation`. The camera follows the interpolated chest in `_process` and eases the eye over about 50 ms. The joystick writes its value on the touch and redraws only when that value changes. None of that can be confirmed at 60 or 120 Hz from this SwiftShader capture. The walk graph is still a 130 ms band, not a 16 ms line.

## Stone and splash

The flight stone and the one in the hand are the same irregular mesh, about 6 cm across and flatter than it is wide. `throw_s2` shows it in the fingers. `throw_s4` shows a thin trail of dots out over the water; the stone at the head of that trail is still a small speck.

`skip_2` shows a white droplet crown on the water, a dark contact mark, and the trail back toward the hand. `skip_5` shows a pale column, a foam patch at its foot, and another crown. The bright ring is in the sea shader. In these stills the crown, the trail, the column, and the foam patch are what read. The ring is not a separate hard edge next to them.

## Shore

`loc_4` no longer has trunks crossing the top of the portrait. Palms sit at the left edge and one trunk at the right. `spawn` shows a white foam line, a pale wet-sand edge, scattered rocks, a piece of driftwood, and grass on the bank. It is denser than an empty shore and it is not the v40 colonnade. Prims on these frames stay under 93k.

## Route

After the path palms moved out to the sides: **3,905** stance samples, **100%** inside ±1 cm, skate max **0.30 cm**, walk skate **0.00 cm**, `shin_min=1.00`. Log: `screenshots/v45/m6/route.log`.

## Still not at the bar

- The export is still about **130 ms** a frame under SwiftShader, p95 about **145 ms**. That is not 60 fps and not an iPhone measurement.
- Draw calls did not fall. The shadow-draw counter stays at 0, so the shadow pass is only visible here as prims.
- The pebble reads as a small light stone, not a disc, and it is still easy to lose at the skip.
- The skip crown, trail, foam, and plunk column show. The shader ring does not read as its own bright edge in the stills.
- The shore gained a foam line, wet sand, rocks, and driftwood. It is not v40's density.
