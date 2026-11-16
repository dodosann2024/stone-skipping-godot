# v46 regression audit

Branch `cursor/v46-regress-d4ce`, from main `51991d9`. `docs/index.html` still points at v35. Trial build: `docs/game_v46/game_v46.html`. Not merged.

> “耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。”

The same touch session was run at 390×844 on the exported v35, v40, v43 and v45 pages, then again on v46. Frames are under `screenshots/v46/audit/`. SwiftShader is not an iPhone. Walk p95 on the v46 overlay is still about **140–145 ms**.

## Regressions in v45, with the frame

- **The body falls through the world.** After the orbit and another run, v45 `10_inland`, `14_pier` and `15_throw_1` are an empty teal field. Draw calls drop to 1–4 because only the UI is left. The same moment in v43 `14_pier` is the boy standing on the dock with the sea in frame, and v43 `15_throw_0` shows 出手. v40 `04_run` is the boy on the beach with palms and a readable sea.
- **Movement is camera-relative, and the orbit drag does not own the pitch.** `_process` eases pitch back to 35° on the same frames the finger is adding to it, so the view yaws to a bad angle and the next stick runs off the dock. v45 `09_orbit` is the dock seen from a steep side. There is no floor under the sea (`Ground` skips cells below -0.55), and the old height snap ignores a miss (`height` returns -999). The camera follows the body under the plane, which is culled, so the picture is the sky colour.
- **The camera position was smoothed twice.** Physics interpolation already moves the chest between ticks, and v45 then eased the eye toward that point over another 50 ms.
- **The cheap sea and ground did not buy frame time.** v45 idle sea at the bottom of `02_idle` is a flat dark band. The full shader is what v44 had after the sea was accepted. SwiftShader walk p95 on v45 was already **142 ms** (`04_run` overlay).
- **帧时间 covered the title.** v45 `02_idle` puts that button under the record line, and the debug text (on because the audit used `debug=1`) covers the left of the pier.
- **The iPhone mute hint was gone.** v35 and v40 show “没声音？请关闭 iPhone 侧边静音开关并调高音量”. v45 does not. A silent phone has no explanation.
- **Scene density.** v40 `02_idle` and `04_run` are a beach, palms, rocks and a full figure. v45’s play session never reaches that shore because the body is already gone. That is not a fair density contest, and it is the bigger failure.

The scripted sit and lie never found the bench in v35 either (`11_sit` is still standing in the bushes). v43 and v46 stay on the dock, so those taps hit empty air. This pass does not claim the bench lie was re-checked in play.

## Root cause

One chain. The orbit drag and the pitch ease fight, the stick then runs off the dock, the walk mesh has a hole over the sea, and the camera follows the body through that hole. The cheap shader, the extra eye ease, the frame-time button and the missing mute line are separate v45 changes that made the picture and the UI worse without moving the SwiftShader frame.

## What changed

- The one position writer puts the body back on the last floor point if it drops under -0.55 and the ground ray misses. Foot IK and the walk mesh are untouched.
- Orbit drag owns pitch until the finger lifts. The extra eye lerp is gone. Yaw and distance still ease as before. Pitch stays inside 30–40°.
- Sea and ground `cheap` is 0 again. The sea mesh is 32×32. Shadow distance is 14 m, blur 0.8, atlas 2048, soft filter back on.
- 帧时间 sits on the lower right. A one-line sound hint shows on the web build until the stick moves.
- Physics interpolation stays on, so a 60/120 Hz phone still draws the body between ticks.

## After, same session

v46 `04_run`: the boy is on the dock, sea on both sides, shadow on the planks. Overlay **121.9 ms**, walk p95 **140.4 ms**, prims **68,028**, draws **60**. v46 `10_inland` and `14_pier`: still on the dock, sea in frame, not the void. Prims about **53,000–54,000**, frame about **126–136 ms**, walk p95 **144 ms**.

v43 `14_pier` is the earlier version that still has the boy on the pier. v45 `14_pier` is the void. The three frames are `screenshots/v46/audit/side_by_side_pier.jpg`.

Route: **3,907** samples, **100%** inside ±1 cm, skate max **0.27 cm**, walk skate **0.00**, shin **1.00**.

## Not verified on an iPhone

60 fps, the silent switch, and whether the 50 ms of interpolation lag is pleasant at 120 Hz. SwiftShader here is still about **140 ms** on the walk. That is not 60 fps.
