# 海岛打水漂 · v46

Branch `cursor/v46-regress-d4ce`, cut from main `51991d9`. `docs/index.html` stays on v35. This version exports to `docs/game_v46/`. No new gameplay. The play camera stays inside 30–40° down. The grounding core is frozen. Not merged.

“耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。”

## What went wrong in v45

The same touch session was run at 390×844 on v35, v40, v43 and v45. v43 stays on the pier and can throw. v45, after the orbit and another run, leaves the dock, falls through the sea, and the camera follows. The picture becomes an empty teal field. Sit, lie and the three throws never happen because the body is already gone.

The camera also eases its own position on top of physics interpolation, and it eases pitch back to 35° while a finger is still dragging. The web sea and ground were forced onto the cheap path, which dropped the lace and the grain and did not make the SwiftShader frame faster. A 帧时间 button sat over the title. The iPhone mute hint from the earlier game was gone.

## What this version changes

One writer still owns the body. If it leaves the walk mesh and drops under the sea, that writer puts it back on the last floor position. Orbit drag owns the pitch until the finger lifts. The extra camera-position ease is gone. The sea and the ground use the full shader again. The shadow distance and the soft filter are the v44 values. The frame-time control sits on the right, and a one-line sound hint shows on the web build until the stick moves.
