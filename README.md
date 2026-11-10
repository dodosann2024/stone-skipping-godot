# 海岛打水漂 Stone Skipping (Godot 4.7.2) — v6 写实骨骼角色 + 参考图画风

低多边形热带海岛小游戏。场景、道具由 GDScript 代码生成；小男孩由 Blender 脚本（`art/boy/`）建模、绑定骨骼、制作动画后导出 glTF；水面为自写着色器，所有声音均为代码合成。
渲染器：Compatibility（gl_compatibility），Web 导出为单线程版本（无需 SharedArrayBuffer / 跨域隔离头）。

## v6 改动
在线试玩：<https://dodosann2024.github.io/stone-skipping-godot/>（导出文件改名为 `game_v6.*`）。参考图分析见 `docs/STYLE_v6.md`，截图与视频见 `screenshots/v6/`。

### 1. 修复：晒太阳 / 吊床起身后不能走
- 原因：起身结束时没有刷新 UI，摇杆一直是隐藏状态。现在起身结束统一调用 `_update_ui()`，并且每帧检查「摇杆可见 ⇔ 自由走动模式」。
- 回归测试 `dev/selftest.gd`（`godot --headless --path . --fixed-fps 30 -- --selftest`）：毛巾四个方向、吊床两侧、码头站立 / 半蹲投掷（欢呼 / 失望）、进出码头、观景模式之后，都用真实触摸事件推摇杆，要求小男孩能走且播放走路动画。

### 2. 新小男孩（`art/boy/*.py` → `boy/boy.glb`）
- 用 Blender 4.5 + MPFB2（MakeHuman，CC0 资产）脚本生成约 13 岁、约 6.4 头身的少年（身高 1.23 m），53 根骨骼（game_engine 骨架），约 1.9 万三角形，无贴图（顶点色 AO + 着色器）。
- 衣服是贴合身体的壳网格：白背心、敞开的红马甲、黄色沙滩短裤（裤脚外扩）、人字拖；独立的头发；草帽（编织纹理 + 红带，往后戴，俯视也能看到脸）。
- 脸由 `shaders/boy.gdshader` 画出（眨眼、笑、咬牙、惊讶、睡着），柔和包裹光照 + 暖色明暗交界 + 轻微边缘光。

### 3. 动画（Blender 中用 IK 姿势工具 `posekit.py` 生成，烘焙为 17 个片段）
- 走路：接触 / 下沉 / 经过 / 上升，脚跟着地 → 滚过前脚掌 → 脚尖离地，骨盆下沉与旋转，肩膀反向转动，手臂反向摆动。跑步：腾空期、更大前倾和摆臂。
- 待机、站立投掷、半蹲投掷、欢呼、失望、吊床（坐 → 躺 → 睡 → 起 → 站）、晒太阳（坐 → 躺 → 休息 → 起 → 站）。
- Godot 里 `AnimationTree` 作为混合器：走 / 跑按速度混合，步态相位按实际移动距离 ÷ 步幅推进，支撑脚不滑。

### 4. 画面（对照参考图）
- 相机：自由走动时约 56° 高俯视、长焦（窄视角），树冠挡住时在相机到人物之间做网点镂空。
- 光照：太阳更低、阴影更长更柔，冷色天光，轻雾，整体降低饱和度与对比度。
- 沙滩：细颗粒、低频明暗、脚印（走过的地方留下人字拖脚印，45 秒后消失），水线上方一条更暗更冷的湿沙带。
- 海水：乳白玉绿色、几乎不透明的渐变，高光很少；沙滩上一条细、亮、波浪形的泡沫线随浪上下；后面一条淡的第二道线，近岸漂浮的泡沫点。
- 椰子树：更多环节、暖灰褐色、节间更深的沟。吊床降低，坐上去脚能接近沙面。

## v5 改动
在线试玩：<https://dodosann2024.github.io/stone-skipping-godot/>（导出文件改名为 `game_v5.*`，旧缓存不会干扰）。截图与视频见 `screenshots/v5/`（`00_compare_v4_v5.png` 为前后对比，`demo.mp4` 为走路 / 投掷 / 吊床 / 晒太阳片段）。

### 1. 小男孩新形象（`boy_mesh.gd`、`shaders/character.gdshader`）
- 从方块拼接改为平滑曲面：头、身体、四肢、短裤、草帽都由带平滑法线的网格（放样 / 车削 / 圆管 / 胶囊）生成，轮廓圆润，从高处 3/4 俯视也清楚。
- 比例更“Q 版小男孩”：大头、圆下巴、略带婴儿肥的脸颊；粗眉、大眼（贴图式画在脸上，带高光）、露齿笑、雀斑和创可贴保留；刺刺短发、鬓角、后脑碎发从草帽下露出。
- 服装保留：草帽（车削帽冠 + 红色帽带 + 微卷帽檐 + 编织纹理）、敞开的红色无袖马甲（白色滚边、内外两面）、白色背心（露肩、肩带、圆领）、黄色沙滩短裤（小花图案）、人字拖。
- 新的角色着色：包裹式漫反射（阴影更柔）、皮肤暗部偏暖、柔和高光与轮廓光；脚下加了一个柔和的接触阴影，站在沙滩上更“落地”。
- 面数约 1.9 万三角形（v4 约 1 万），绘制调用数不变（27）。

### 2. 动画全部重做（`boy.gd`）
- 脚锚定在世界坐标里：着地的脚绝不滑动（`dev/gait_view.gd` 实测走、跑、转弯、急停时支撑脚滑移为 0）。
- 步态循环按真实地面速度计算步频与步幅；摆动脚落在身体“将要到达”的位置（含转弯预测）；脚跟着地 → 全脚掌 → 脚尖蹬离；手臂与对侧腿反向摆动（走路自然下垂、跑步屈肘）；骨盆扭转、重心左右转移、起伏、加速前倾 / 减速后仰、转弯内倾；跑步有腾空期。
- 起步 / 停步平滑：先迈靠后的那只脚，停下时收脚站稳；待机时重心在两脚间缓慢转移、呼吸、四处张望。
- 投掷：髋 → 胸 → 手臂依次发力（动力链），出手后手臂甩过身前随挥，站姿投掷后右脚向前迈一步稳住重心，再回到准备姿势；半蹲同样有随挥。
- 欢呼（三连跳、双手举高）、失手、坐下 / 躺下（吊床、毛巾）之间全部为平滑混合过渡，没有跳变。
- 自由走动的加速、减速、转身略微放缓（`main.gd`），配合步态更像小孩真实起步、跑起来。

### 3. 海面（`shaders/water.gdshader`、`terrain.gdshader`、`common.gdshaderinc`）
- 浅水清澈：沙质海床在浅滩清晰可见，随深度由浅绿松石 → 碧绿 → 蓝（海床本身做吸收着色），礁缘外深蓝不透明。
- 海床有沙纹与更细腻的焦散光纹。
- 岸边泡沫改为多层细线：一道道细白浪线平行于海岸线向岸推进、断续而不呆板，后方留下网状泡沫；每到岸一道，海水沿沙滩上冲再缓慢退回（按等高线推进，所以始终贴合岸线），退后留下深色湿沙。
- 水与沙交界处不再是硬切边，而是柔和渐隐 + 细泡沫边。
- 性能：噪声采样数与 v4 基本持平（远离岸边的像素跳过泡沫计算），仍为 Compatibility 渲染器可用的写法。

### 4. 其它修复
- 吊床视角：相机会在默认角度附近自动寻找一条不被椰子树干挡住的视线。
- 竖屏下投掷结束后相机从远处回来时会短暂把小男孩切出画面：现在先把画面中心移回小男孩、再拉近，全程不会越过他。
- iOS 声音解锁逻辑（`export_presets.cfg` 的 `html/head_include`）未改动。

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
- `boy.gd`：加载 `boy/boy.glb`，用 AnimationTree 混合动画片段（步态相位按移动距离推进）、表情、草帽 / 墨镜 / 石头道具。
- `art/boy/`：Blender 脚本——`build_boy.py`（建模 + 骨骼 + 衣服 + 道具）、`posekit.py`（IK 姿势工具）、`clips.py`（所有动画）、`export_boy.py`（AO 烘焙、动画烘焙、glTF 导出）、`test_*.py`（预览图）。
- `joystick.gd`：虚拟摇杆；`island.gd`：整岛程序化生成（含可摇晃的吊床、毛巾、行走碰撞体）；`mesh_builder.gd`；`shaders/`。
- `web/audio_unlock.js`：iOS 音频解锁脚本（压缩后写在 `export_presets.cfg` 的 head_include 中）。
- `tools/`：音效合成 / 检查、字体子集、浏览器（模拟 iPhone）测试脚本。
- `dev/boy_view.gd`：角色姿势检查；`dev/gait_view.gd`：步态检查（走 / 跑 / 转弯 / 急停，输出支撑脚滑移量）；`dev/selftest.gd`：起身后能否行走的回归测试；均不会被导出。
- `docs/`：Web 导出结果（GitHub Pages 从这里发布）。

## 命令
```bash
godot --headless --path . --import
godot --headless --path . -- --sim                                    # 站立 / 半蹲物理参数表
python3 tools/synth_audio.py && python3 tools/check_audio.py           # 重新合成并检查音效
blender -b --python art/boy/build_boy.py -- --export boy                # 重新生成小男孩（需要 Blender 4.5 + MPFB2 扩展）
godot --headless --path . --fixed-fps 30 -- --selftest                 # 回归测试：每个动作结束后都能用摇杆走
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4            # v6 截图（screenshots/v6）
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4 --from=explore # 游戏相机下走 / 跑
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4 --from=shore # 海岸 / 浅海截图
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --resolution 585x1266 -- --demo4 --portrait # 竖屏截图
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --write-movie w.avi -- --video4=walk     # 视频片段 walk/throw/sleep/sun/getup/gait
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . -s res://dev/boy_view.gd -- --out=/tmp/pose            # 角色姿势图
godot --headless --path . --fixed-fps 30 -s res://dev/gait_view.gd                                    # 步态滑步检查（加 --out=/tmp/g 输出帧）
godot --headless --path . --export-release "Web" build/web/game_v6.html   # 然后复制到 docs/，index.html = game_v6.html
python3 tools/browser_check_v4.py "https://dodosann2024.github.io/stone-skipping-godot/?v=6" /tmp/web   # 模拟 iPhone 测试（含真实出声检测）
```

## 素材与许可
- 场景、道具、着色器均为本项目代码生成。小男孩的基础人体网格（male1591 代理网格）、体型目标和 game_engine 骨架来自 MakeHuman / MPFB2 资产，CC0 协议；衣服、草帽、动画等由 `art/boy/` 脚本生成。
- 所有声音均由 `tools/synth_audio.py` 程序合成（噪声 + 滤波 + 模态合成），无第三方录音素材。
- 字体：Noto Sans CJK SC Bold（仅子集化项目用到的字符为 `fonts/ui.otf`），SIL Open Font License 1.1，© Google / Adobe。许可文本见 `fonts/NOTO_LICENSE.txt`。
- 引擎：Godot Engine（MIT License）。
