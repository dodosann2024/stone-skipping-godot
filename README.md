# 海岛打水漂 Stone Skipping (Godot 4.7.2) — v4 岛上自由走动 + 半蹲投掷 + 吊床 / 晒太阳

低多边形热带海岛小游戏。场景、角色、道具全部由 GDScript 代码生成，水面为自写着色器，所有声音均为代码合成。
渲染器：Compatibility（gl_compatibility），Web 导出为单线程版本（无需 SharedArrayBuffer / 跨域隔离头）。

## v4 改动
### 1. 声音（iPhone 没声音）
- 最可能的原因：iOS Safari 的 Web Audio 默认使用 “ambient” 音频会话，**iPhone 侧边静音开关打开时网页游戏完全没有声音**（音乐 App 不受影响，所以很容易误以为是游戏坏了）。另一个次要原因：iOS 只把 `touchend` / `click` 算作“用户激活”，`touchstart` 时恢复 AudioContext 可能无效。
- 修复（`export_presets.cfg` 的 `html/head_include`，源码见 `web/audio_unlock.js`）：
  - 在每次 `touchend / pointerup / mouseup / click / keydown`（捕获阶段）以及页面切回前台（`visibilitychange` / `pageshow`）时：
    - 设置 `navigator.audioSession.type = 'playback'`（Safari 17+，让网页声音不受静音开关影响）；
    - 旧版 iOS 没有 audioSession 时，在同一手势里播放一个循环的静音 `<audio playsinline>`（把会话切到 playback）；
    - 对页面里所有 AudioContext（挂钩构造函数收集）调用 `resume()`，并播放一个 1 采样的空 buffer。
  - 「点击开始」改为**松手时**开始（touchend），开始后先响一声短“叮”，确认有声音。
  - 网页版开始后显示可关闭的提示：「没声音？请关闭 iPhone 侧边静音开关并调高音量」。
  - 之后每次点屏幕都会再尝试恢复音频（防止来电 / 切 App 后被系统挂起）。
- 音频文件仍为 OGG：Godot Web 在 wasm 里自己解码 OGG 再交给 Web Audio 播放，不依赖 Safari 的 OGG 支持。

### 2. 小男孩新形象（`boy_mesh.gd`）
- 去掉粉色腮红、圆脸、小嘴、齐耳短发：改为略方的脸型与下颌、草帽下露出刺刺的短碎发和鬓角、粗眉、大而有高光的眼睛、小鼻子、露牙的大笑、雀斑、左脸一张创可贴、晒黑的皮肤。
- 表情：待机微笑；蓄力 / 出手咬牙使劲；欢呼时张嘴大笑；失手时“哦”；睡觉闭眼；晒太阳戴墨镜、闭嘴微笑。
- 红色马甲：不再是圆筒。改为敞开的无袖马甲：前襟 V 形敞开露出白色内衬背心，宽袖口、粗肩带，下摆略微外扩且左右不齐，有口袋和纽扣、白色滚边；左右前片随身体运动轻微摆动。
- 草帽不再投下大片阴影，脸更亮。

### 3. 半蹲投掷
- 投掷模式右上角「姿势：站立 / 半蹲」切换。
- 半蹲：右膝跪在码头上、左脚在前，身体压低前倾；蓄力时更低更扭身，出手点贴近水面，随挥时右臂甩过身前。
- 物理：半蹲出手点更低、出手角度低 1°、最大力度为站立的 92%（打得更平，但略近）。

### 4. 岛上自由走动 / 跑步
- 手机：左下角浮动虚拟摇杆（手指在左下区域任意位置按下即出现），轻推走路、推到底跑步；单指在其它区域拖动转视角，双指捏合缩放。
- 电脑：WASD / 方向键走路，按住 Shift 跑步；鼠标拖动转视角，滚轮缩放。
- 走路 / 跑步为程序化步态：步频、步幅随速度变化，支撑脚与地面同速后移（不滑步），摆臂、身体前倾、上下起伏、骨盆扭转；跑步时腾空、屈臂。
- 跟随地形高度（沙滩、山坡、码头木板、码头台阶处可上下），碰撞椰子树、小屋、灯塔、礁石、木桩、木箱、篝火、躺椅、吊床等；不能走进深水，浅水可以蹚水（变慢、溅水花）。
- 脚步声随地面不同：沙地、木板、草地、浅水。
- 第三人称跟随相机：走动时慢慢转到身后，手指拖动可自由旋转；有简单的“弹簧臂”，相机不会穿进树干 / 小屋 / 道具。
- 右上角「观景」仍可进入 360° 观景模式。

### 5. 互动
- 椰子树间的吊床：走近后点「睡觉」→ 走到吊床边、转身坐下、躺进去；吊床轻轻摇晃，闭眼、呼吸起伏，草帽放在胸口，头上冒出「z Z z」。点屏幕或「起来」醒来。
- 沙滩毛巾（遮阳伞旁）：点「晒太阳」→ 坐下再躺倒，双手枕在脑后、脚踝交叉、戴墨镜、轻轻呼吸，草帽放在头边。
- 码头尽头（T 形平台）：点「打水漂」进入投掷模式（小男孩会走到平台前沿的空位）。**只有在这里才能扔石子**，岛上其它地方没有投掷按钮。
- 投掷模式里方向仍可任意调整（只会自动避开正对障碍物的方向）；扔完可以继续扔，或点「离开码头」回到自由走动。

### 6. 界面
- 竖屏和横屏分别布局：左下摇杆、右下动作按钮、右上「观景 / 声音 / 姿势 / 离开码头」。
- 竖屏使用单独的相机距离和视角，小男孩在画面里更大。

## 声音文件（全部为 `tools/synth_audio.py` 用 numpy/scipy 合成，无任何第三方录音）
| 文件 | 内容 |
|---|---|
| `audio/ocean_loop.ogg` | 24 秒无缝循环海浪环境声，音量随相机离海岸的距离变化 |
| `audio/whoosh.ogg` | 挥臂破风声 |
| `audio/skip_0..3.ogg` | 每次弹跳的轻拍水声（4 个变体） |
| `audio/sink.ogg` | 最后入水的“咕咚” |
| `audio/hit_wood.ogg` / `hit_rock.ogg` / `hit_sand.ogg` | 撞到木头 / 石头 / 沙滩 |
| `audio/combo.ogg` / `record.ogg` | 连跳 / 新纪录提示音（开始游戏时的“叮”也用它） |
| `audio/step_sand_*.ogg` / `step_wood_*` / `step_grass_*` / `step_water_*` | v4 脚步声：沙地、木板、草地、蹚水 |

## 玩法速览
1. 点「点击开始」（松手时开启声音；iPhone 请关闭侧边静音开关）。
2. 用左下摇杆走到码头尽头，点「打水漂」。
3. 按住屏幕蓄力，左右拖转向、上下拖调角度，松手扔出；角度低、力度大才跳得多。右上角可切换站立 / 半蹲。
4. 「离开码头」后可以去吊床睡觉、去沙滩毛巾晒太阳。

## 目录
- `main.gd`：模式（自由走动 / 投掷 / 观景 / 休息）、移动与碰撞、相机、UI、声音、演示脚本。
- `boy.gd`：小男孩骨架与程序化动画（待机、站立 / 半蹲投掷、走 / 跑步态、反应、坐 / 躺）；`boy_mesh.gd`：小男孩模型（脸、表情、马甲等）。
- `joystick.gd`：虚拟摇杆；`island.gd`：整岛程序化生成（含可摇晃的吊床、毛巾、行走碰撞体）；`mesh_builder.gd`；`shaders/`。
- `web/audio_unlock.js`：iOS 音频解锁脚本（压缩后写在 `export_presets.cfg` 的 head_include 中）。
- `tools/`：音效合成 / 检查、字体子集、浏览器（模拟 iPhone）测试脚本。
- `dev/boy_view.gd`：角色姿势检查（不会被导出）。
- `docs/`：Web 导出结果（GitHub Pages 从这里发布）。

## 命令
```bash
godot --headless --path . --import
godot --headless --path . -- --sim                                    # 站立 / 半蹲物理参数表
python3 tools/synth_audio.py && python3 tools/check_audio.py           # 重新合成并检查音效
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4            # v4 截图
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 585x1266 -- --demo4 --portrait # 竖屏截图
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --write-movie w.avi -- --video4=walk     # 视频片段 walk/throw/sleep/sun
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . -s res://dev/boy_view.gd -- --out=/tmp/pose            # 角色姿势图
godot --headless --path . --export-release "Web" build/web/game_v4.html
python3 tools/browser_check_v4.py "https://dodosann2024.github.io/stone-skipping-godot/?v=4" /tmp/web   # 模拟 iPhone 测试（含真实出声检测）
```

## 素材与许可
- 所有 3D 模型、贴图、着色器均为本项目代码生成，无第三方美术素材。
- 所有声音均由 `tools/synth_audio.py` 程序合成（噪声 + 滤波 + 模态合成），无第三方录音素材。
- 字体：Noto Sans CJK SC Bold（仅子集化项目用到的字符为 `fonts/ui.otf`），SIL Open Font License 1.1，© Google / Adobe。许可文本见 `fonts/NOTO_LICENSE.txt`。
- 引擎：Godot Engine（MIT License）。
