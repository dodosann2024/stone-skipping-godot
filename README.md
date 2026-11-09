# 海岛打水漂 Stone Skipping (Godot 4.7.2)

低多边形热带海岛上的打水漂小游戏。场景、角色、道具全部由 GDScript 代码生成，水面为自写着色器。
渲染器：Compatibility（gl_compatibility），Web 导出为单线程版本（无需 SharedArrayBuffer / 跨域隔离头）。

## 玩法
- 按住屏幕（或鼠标左键）开始蓄力，力度条会来回摆动。
- 按住时左右拖动调方向，上下拖动调出手角度（向上 = 抬高）。
- 松开扔出石头。预览弧线：绿色 = 入水角合适，红色 = 太陡或太慢会直接沉。
- 角度放低、力度大（石头转得更快）才能多跳几次。浮标标出 20/40/60 米。
- 最高纪录保存在浏览器本地存储中。

## 目录
- `main.gd`：全部游戏逻辑与场景生成；`water.gdshader`：水面渐变、浪花与波动。
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
