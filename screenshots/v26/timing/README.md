# v26 frame timing (60 / 120 fps)

CSV columns: frame, dt, boy screen xy, boy_ds (px), camera xyz, cam_ds (m), yaw/pitch/dist.

Stats filter near-idle frames (boy_ds > 0.02 px, cam_ds > 0.001 m) before median/max.

Typical max/median after warmup:
- walk/run boy ≈ 2–4, camera ≈ 1.0–1.3
- orbit camera ≈ 1.0–1.2; boy screen delta higher while framing shifts

Plots: `*_60fps.png`, `*_120fps.png`.
