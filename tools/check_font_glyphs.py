#!/usr/bin/env python3
"""Fail if any character used in .gd/.tscn/.tres/web HTML is missing from fonts/ui.otf.

Intended for CI / pre-export. Reuses the same scan as tools/make_font.py.
"""
from __future__ import annotations

import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from make_font import OUT, collect_chars  # noqa: E402


def main() -> int:
	if not OUT.is_file():
		print(f"ERROR: font missing: {OUT}", file=sys.stderr)
		return 2
	chars = collect_chars()
	cmap = TTFont(str(OUT)).getBestCmap() or {}
	missing = sorted(
		{c for c in chars if ord(c) > 0x7F and not c.isspace() and ord(c) not in cmap},
		key=lambda c: ord(c),
	)
	print(f"checked chars={len(chars)} font_glyphs={len(cmap)} missing={len(missing)}")
	if missing:
		print("MISSING GLYPHS:", "".join(missing), file=sys.stderr)
		print(" ".join(f"U+{ord(c):04X}" for c in missing), file=sys.stderr)
		print("Run: python3 tools/make_font.py", file=sys.stderr)
		return 1
	# Explicit regression checks for the v30 tofu bugs.
	for s in ("固定视角", "复制数据"):
		bad = [c for c in s if ord(c) not in cmap]
		if bad:
			print(f"ERROR: {s!r} still missing {bad}", file=sys.stderr)
			return 1
	print("OK")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
