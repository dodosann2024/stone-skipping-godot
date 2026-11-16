# 海岛打水漂 · v45

Branch `cursor/v45-smooth-d4ce`, cut from v44 `2ef717e`. `docs/index.html` stays on v35. This version exports to `docs/game_v45/`. No new gameplay. The play camera stays inside 30–40° down. The grounding core is frozen. Not merged.

“耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。”

## What this version is for

Walking, the joystick, and the camera should feel smooth on a real iPhone at a level that could ship. SwiftShader frame time is not that number. The export carries a frame-time overlay the phone can show, and a walk pacing graph from the same export.

## Costs worth cutting

The boy is one skinned colour mesh plus a shadow proxy. The sea fragment runs a stack of noise and lace on every water pixel. Each prop is its own draw. The occluder builds a new ray list and dictionary every frame. The debug readout sorts its sample array every frame.

Cuts that follow from that: one cheaper sea path on the web build, a shorter shadow distance, distant props on the existing card LOD and on multimeshes, and no fresh arrays in the per-frame scripts.

## Smoothness

Physics stays at 60 ticks. Render interpolation is on, so 60 Hz and 120 Hz both draw the body between ticks. The camera follows the interpolated chest in `_process`. The joystick writes its value on the touch event and again every render frame.

## Stone and splash

The pebble keeps a real size and gains an irregular rounded silhouette. After the first skip it darkens as if wet. The skip still uses a droplet crown, a bright-edged ring in the sea shader, a foam patch, and a taller column on the final plunk.

## Shore

Palm clusters, rocks, driftwood, shells, and beach grass fill the shore with multimeshes and the card LOD. The near trunks on the path stay out of the top of the portrait frame. Prims stay at or under 93k.
