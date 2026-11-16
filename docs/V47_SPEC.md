# 海岛打水漂 · v47

Same branch as v46, `cursor/v46-regress-d4ce`. `docs/index.html` stays on v35. Trial build remains `docs/game_v46/game_v46.html`. No new gameplay. The play camera stays inside 30–40° down. The grounding core stays frozen. Not merged.

“耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。”

“打水漂的游戏制作标准我给你一个参考对象。要做到怪物猎人的游戏水准。塞尔达传说旷野之息的流畅度。”

The first sentence stays the standing bar for play, controls and picture. The second sets the references for the next versions: Monster Hunter for how specific the picture and the animation have to be, Breath of the Wild for how the walk, the stick and the camera have to feel — stable frame time, no hitch, no jitter. Both sentences go into the next version's spec, unchanged, until the game is actually there.

## What was measured

SwiftShader at 390×844 is not an iPhone. The frame delta on the dock is about **119–146 ms**. That is not 60 fps.

`Performance.TIME_PROCESS` printed **670–705 ms** on the early audit samples and **207–245 ms** on a later idle sample. It does not match the frame delta, so it is not the time the phone will take.

Timed sections of the same idle frame, in GDScript:

| section | time |
| --- | --- |
| props (LOD + flames) | 0.10 ms |
| camera rig | 0.10 ms |
| occluder (105 props) | 0.10 ms |
| physics | 0.2–0.5 ms |

The heavy number is not a script loop. The frame is the software renderer drawing the scene. Visible cost on that idle dock frame: **52 draws, 66,808 prims**, shadow prims **5,361**, shadow draws **0** on this renderer. The orbit frame that shows the whole path is **101 draws, 71,196 prims**. Both are under the 93k aim. The sea and the ground stay on the full shader. Cutting them earlier did not make SwiftShader faster and made the picture worse.

## Feel already in this build

After the orbit finger lifts, the camera eases back along the dock so the planks ahead fill the frame. A step off the flat pier onto the beach beside it is put back on the boards. The throw camera sits just behind the boy so the pose and the water share the narrow portrait frame. These are the walk, stick and camera fixes. They are not Breath of the Wild yet. The iPhone frame time is still unread; 帧时间 is on the lower right, in the game font, for that.

## Not claimed

60 fps, Monster Hunter picture detail, or Breath of the Wild smoothness. Those are the bar for the next version, copied above.
