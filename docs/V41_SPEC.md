# v41 spec

Cut from `main` at `38d0351` (v40). `docs/index.html` stays on v35 until the owner decides after iPhone testing. The web export is `docs/game_v41/`.

## Standing requirement

This sentence is the owner's requirement. It is copied here verbatim, and every later version's spec must carry it until the bar is actually met:

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

`docs/AAA_BAR.md` is the checklist under that sentence. v41 does not claim the bar is met.

## This version

Only the gaps left in `docs/V40_REPORT.md`.

1. The ~17 cm float (`float_pct` 68.79). The harness gap is the lower foot's skinned sole vertex against `Ground.height` at that vertex, not the ankle bone. Re-run the 110 m route. Side views at five or more flagged frames carry a ruler. If the picture is planted and the old number was the ankle sample, the corrected harness should read near zero float and the pose should not move. If the sole is really up, fix it in the current pipeline and keep `drag39.py` passing.
2. Walk, joystick, and camera, checked against a short-hike / animal-crossing kind of third-person phone feel: touch-to-motion, the first step, turn rate, camera damping and drift, and stick size on a 390 pt screen. Before and after traces go in the report. The review drag still has to show both sandals in all three frames, including the wide release.

## Hard gate

Every commit's export must pass `drag39.py`: full shins and both sandals in all three frames, and the wide frame 0.8 s after release. The PNGs are committed with the commit. No VRAM-compressed textures. The 60 fps budget is for an iPhone; SwiftShader is not that phone.
