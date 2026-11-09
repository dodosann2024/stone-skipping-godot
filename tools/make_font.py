"""Rebuild fonts/ui.otf: Noto Sans CJK SC Bold subset to every character used by the game's scripts."""
import glob, os, subprocess
from fontTools.ttLib import TTFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
chars = set(chr(c) for c in range(0x20, 0x7f)) | set("·°→、，。！？：；（）「」%“”—…×")
for f in glob.glob(os.path.join(ROOT, "*.gd")):
    chars |= set(open(f, encoding="utf-8").read())
chars = sorted(c for c in chars if ord(c) >= 0x20)
txt = os.path.join(ROOT, "tools", "_chars.txt")
open(txt, "w", encoding="utf-8").write("".join(chars))
out = os.path.join(ROOT, "fonts", "ui.otf")
subprocess.run(["pyftsubset", SRC, "--font-number=2", f"--text-file={txt}", f"--output-file={out}", "--layout-features=*", "--no-hinting"], check=True)
cmap = TTFont(out).getBestCmap()
missing = [c for c in chars if ord(c) > 0x7f and ord(c) not in cmap and not c.isspace()]
print("chars", len(chars), "size", os.path.getsize(out), "missing", missing)
