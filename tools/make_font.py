#!/usr/bin/env python3
"""Rebuild fonts/ui.otf from Noto Sans CJK SC Bold.

Scans EVERY project .gd / .tscn / .tres (plus web/*.html loader strings) and
subsets every character used. Exits non-zero if any used CJK/symbol char is
missing from the built subset (see also tools/check_font_glyphs.py).
"""
from __future__ import annotations

import glob
import os
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SRC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
OUT = ROOT / "fonts" / "ui.otf"
CHARS_TXT = ROOT / "tools" / "_chars.txt"

# Always keep basic Latin + common punctuation / symbols used in UI/readouts.
# Greek Δ (debug HUD maxΔ) and friends must stay even if a source scan is stale.
BASE = set(chr(c) for c in range(0x20, 0x7F)) | set(
	"·°→←↑↓、，。！？：；（）「」『』【】%“”‘’—…×÷±≤≥≈≠"
	"Δδµπ∞√∑∂∇"
)

SKIP_DIRS = {
	".git", ".godot", "docs", "screenshots", "artifacts", "build",
	"node_modules", "__pycache__",
}


def iter_source_files() -> list[Path]:
	files: list[Path] = []
	for pat in ("**/*.gd", "**/*.tscn", "**/*.tres"):
		for p in ROOT.glob(pat):
			if any(part in SKIP_DIRS for part in p.parts):
				continue
			files.append(p)
	# Loader / shell Chinese strings live in HTML, not .gd.
	for p in (ROOT / "web").glob("*.html"):
		files.append(p)
	return sorted(set(files))


def collect_chars() -> set[str]:
	chars = set(BASE)
	for p in iter_source_files():
		try:
			text = p.read_text(encoding="utf-8", errors="ignore")
		except OSError:
			continue
		chars |= set(text)
	# Drop controls / unused whitespace noise; keep NBSP etc. out.
	return {c for c in chars if ord(c) >= 0x20 and c not in "\u200b\ufeff"}


def build(chars: set[str]) -> list[str]:
	ordered = "".join(sorted(chars, key=lambda c: ord(c)))
	CHARS_TXT.write_text(ordered, encoding="utf-8")
	if not os.path.isfile(SRC):
		print(f"ERROR: Noto source missing: {SRC}", file=sys.stderr)
		sys.exit(2)
	OUT.parent.mkdir(parents=True, exist_ok=True)
	# font-number=2 → Noto Sans CJK SC Bold in the Debian TTC.
	subprocess.run(
		[
			"pyftsubset", SRC,
			"--font-number=2",
			f"--text-file={CHARS_TXT}",
			f"--output-file={OUT}",
			"--layout-features=*",
			"--no-hinting",
		],
		check=True,
	)
	cmap = TTFont(str(OUT)).getBestCmap() or {}
	missing = sorted(
		{c for c in chars if ord(c) > 0x7F and not c.isspace() and ord(c) not in cmap},
		key=lambda c: ord(c),
	)
	print(f"sources={len(iter_source_files())} chars={len(chars)} "
		  f"size={OUT.stat().st_size} missing={len(missing)}")
	if missing:
		print("MISSING:", "".join(missing), file=sys.stderr)
		print("codepoints:", " ".join(hex(ord(c)) for c in missing), file=sys.stderr)
		sys.exit(1)
	return missing


def main() -> int:
	chars = collect_chars()
	# Sanity: known UI strings that previously tofu'd must be present as inputs.
	for sample in ("固定视角", "复制数据", "正在加载", "网络较慢", "maxΔ", "gnd"):
		for c in sample:
			if c not in chars and ord(c) > 0x7F:
				print(f"ERROR: expected char {c!r} from {sample!r} not found in scan", file=sys.stderr)
				return 1
	build(chars)
	print(f"wrote {OUT}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
