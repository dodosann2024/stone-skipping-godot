# 海岛打水漂 Stone Skipping (Godot 4.7.2) — v3 草帽小男孩 + 海浪声

低多边形热带海岛上的打水漂小游戏。场景、角色、道具全部由 GDScript 代码生成，水面为自写着色器，所有声音均为代码合成。
渲染器：Compatibility（gl_compatibility），Web 导出为单线程版本（无需 SharedArrayBuffer / 跨域隔离头）。

## v3 角色：草帽小男孩（`boy.gd`）
- 大头可爱比例（身高约 1.3 米含草帽）：编织纹草帽（帽檐、帽冠、红色帽带）、红色背心（白色滚边、肩带、胸前小图案）、黄色沙滩裤（小花图案、腰带、白色抽绳）、晒黑的皮肤、蓝色人字拖、短发、眼睛（会眨眼）、腮红、微笑。
- 关节层级：骨盆 → 脊柱 → 头 / 草帽；左右上臂、前臂、手（双骨 IK）；左右大腿、小腿、脚（双骨 IK，脚掌贴地不滑步，换站姿时抬脚迈步）。右手捏着一块扁平石头。
- 待机：呼吸、轻微摇摆、时不时转头看海。
- 投掷（侧抛打水漂）：
  - 蓄力：屈膝下蹲、上身向右后扭转、右臂向后拉到与水面平行、左臂前伸保持平衡；力度越大蹲得越低、扭得越多（按住时实时变化）。
  - 出手（约 0.1 秒）：以左脚为轴、髋部快速前转、右臂侧摆、手腕一甩；石头在出手那一帧从手的位置飞出。
  - 随挥：身体前倾、右臂甩过身前、右腿向后抬起（力度越大抬得越高），草帽随惯性晃动；之后站稳目送石头。
  - 反应：跳得多 / 破纪录时双手举高欢呼；直接沉下去时抱头。
- 投石视角为右后方 3/4 镜头，先拍小男孩的动作，约 0.45 秒后再跟随石头；竖屏有单独的机位。

## 声音（全部为 `tools/synth_audio.py` 用 numpy/scipy 合成，无任何第三方录音）
| 文件 | 内容 |
|---|---|
| `audio/ocean_loop.ogg` | 24 秒无缝循环海浪环境声（涌浪隆隆声、6 次碎浪、退潮泡沫声、码头拍岸、微风）。音量随相机离海岸的距离变化 |
| `audio/whoosh.ogg` | 挥臂破风声（力度越大音调越高、越响） |
| `audio/skip_0..3.ogg` | 每次弹跳的“啪/啦”轻拍水声，4 个变体轮换，音量音调随速度变化并带随机 |
| `audio/sink.ogg` | 最后入水的“咕咚” |
| `audio/hit_wood.ogg` / `hit_rock.ogg` / `hit_sand.ogg` | 撞到木头（码头、木桩、小船、小屋、路牌、椰子树）/ 石头（礁石、灯塔）/ 沙滩 |
| `audio/combo.ogg` / `record.ogg` | 5/10/15 连跳提示音、新纪录提示音 |
- 网页 / iPhone：浏览器必须点一下才允许出声，所以开场有「点击开始」遮罩，点一下即开启海浪声。
- 右上角「声音：开/关」按钮可随时静音。
- 客观检查：`tools/check_audio.py` 解码每个 OGG 并统计峰值、削波、直流偏移、循环接缝跳变，输出频谱图（`screenshots/v3/audio_preview/`）。

## 场景（v2）
整座低多边形热带小岛：中央山丘与红白灯塔、长椅；沙土小路与护栏；南侧 T 形木码头（灯笼、木箱、木桶、鱼竿、救生圈、系泊小船）；
西南钓鱼小屋（茅草顶、门廊、吉他、长凳、晾渔网、吊床）；北侧篝火与火把；东侧礁石群；泻湖里的珊瑚（v3 调得更鲜艳）、海草、贝壳、海星；海鸥、远岛、云。

## 玩法
- 第一次进入先点「点击开始」（开启声音）。
- 按住屏幕（或鼠标左键）开始蓄力，力度条会来回摆动，小男孩随之下蹲扭身。
- 按住时左右拖动调方向，上下拖动调出手角度（向上 = 抬高）。
- 松开扔出石头。预览弧线：绿色 = 入水角合适，红色 = 太陡或太慢会直接沉。
- 角度放低、力度大（石头转得更快）才能多跳几次。浮标标出 20/40/60 米。
- 右上角「观景/投石」切换：观景模式单指拖动 360° 旋转、双指捏合缩放（电脑鼠标拖动 + 滚轮），带惯性。
- 右上角「声音：开/关」开关所有声音。
- 石头砸到沙滩、礁石、码头、小船、小屋等会直接结束（显示原因，并播放对应撞击声）。
- 最高纪录保存在浏览器本地存储中。

## 目录
- `main.gd`：游戏逻辑、相机、UI、声音；`boy.gd`：小男孩模型与程序化动画；`island.gd`：整岛程序化生成；`mesh_builder.gd`；`shaders/`。
- `audio/`：合成好的音效；`tools/synth_audio.py`：音效合成脚本；`tools/check_audio.py`：音频客观检查；`tools/make_font.py`：重建中文字体子集。
- `dev/boy_view.gd`：角色关键姿势检查（不会被导出）。
- `docs/`：Web 导出结果（GitHub Pages 从这里发布）。

## 命令
```bash
godot --headless --path . --import
godot --headless --path . -- --sim                                   # 打印物理参数表
python3 tools/synth_audio.py && python3 tools/check_audio.py          # 重新合成并检查音效
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 -- --demo3              # 角色特写 + 投掷截图
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --fixed-fps 30 --write-movie t.avi -- --video   # 投掷视频
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . -s res://dev/boy_view.gd                # 角色姿势图
godot --headless --path . --export-release "Web" build/web/game_v3.html
```

## 素材与许可
- 所有 3D 模型、贴图、着色器均为本项目代码生成，无第三方美术素材。
- 所有声音均由 `tools/synth_audio.py` 程序合成（噪声 + 滤波 + 模态合成），无第三方录音素材。
- 字体：Noto Sans CJK SC Bold（仅子集化项目用到的字符为 `fonts/ui.otf`），SIL Open Font License 1.1，© Google / Adobe。许可文本见 `fonts/NOTO_LICENSE.txt`。
- 引擎：Godot Engine（MIT License）。
