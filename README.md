# 海岛打水漂 Stone Skipping (Godot 4.7.2) — v2 小海岛码头

低多边形热带海岛上的打水漂小游戏。场景、角色、道具全部由 GDScript 代码生成，水面为自写着色器。
渲染器：Compatibility（gl_compatibility），Web 导出为单线程版本（无需 SharedArrayBuffer / 跨域隔离头）。

## v2 场景
整座低多边形热带小岛：中央山丘与红白灯塔、长椅；沙土小路与护栏；南侧 T 形木码头（灯笼、木箱、木桶、鱼竿、救生圈、系泊小船）；
西南钓鱼小屋（茅草顶、门廊、吉他、长凳、晾渔网、吊床）；北侧篝火与火把；东侧礁石群；泻湖里的珊瑚、海草、贝壳、海星；海鸥、远岛、云。
水面：按水深渐变、透明可见沙底、多层法线小波纹、菲涅尔、沿岸推进/退去的破碎浪花、湿沙带、木桩礁石泡沫环、石头涟漪写入水面着色器；沙底焦散。

## 玩法
- 按住屏幕（或鼠标左键）开始蓄力，力度条会来回摆动。
- 按住时左右拖动调方向，上下拖动调出手角度（向上 = 抬高）。
- 松开扔出石头。预览弧线：绿色 = 入水角合适，红色 = 太陡或太慢会直接沉。
- 角度放低、力度大（石头转得更快）才能多跳几次。浮标标出 20/40/60 米。
- 右上角「观景/投石」切换：观景模式单指拖动 360° 旋转、双指捏合缩放（电脑鼠标拖动 + 滚轮），带惯性。
- 投石模式左右拖动可转一整圈；切回投石会朝当前视角方向，若正对岛屿会自动转到最近的开阔海面。
- 石头砸到沙滩、礁石、码头、小船、小屋等会直接结束（显示原因）。
- 最高纪录保存在浏览器本地存储中。

## 目录
- `main.gd`：游戏逻辑、轨道相机、UI；`island.gd`：整岛程序化生成（合并网格）；`mesh_builder.gd`；`shaders/`：水面、沙地焦散、植被摆动。
- `docs/`：Web 导出结果（GitHub Pages 从这里发布）。
- `tools/browser_check.py`：无头浏览器加载检查。

## 命令
```bash
godot --headless --path . --import
godot --headless --path . -- --sim            # 打印物理参数表
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --rendering-method gl_compatibility -- --demo  # 自动投掷并截图
godot --headless --path . --export-release "Web" build/web/index.html
```

## 素材与许可
- 所有 3D 模型、贴图、着色器均为本项目代码生成，无第三方美术素材。
- 字体：Noto Sans CJK SC Bold（仅子集化项目用到的字符为 `fonts/ui.otf`），SIL Open Font License 1.1，© Google / Adobe。许可文本见 `fonts/NOTO_LICENSE.txt`。
- 引擎：Godot Engine（MIT License）。
