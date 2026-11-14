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
	# Cover EVERY non-space used char (Latin, CJK, Greek Δ, punctuation) — not only >0x7F.
	missing = sorted(
		{c for c in chars if not c.isspace() and ord(c) not in cmap},
		key=lambda c: ord(c),
	)
	print(f"checked chars={len(chars)} font_glyphs={len(cmap)} missing={len(missing)}")
	if missing:
		print("MISSING GLYPHS:", "".join(missing), file=sys.stderr)
		print(" ".join(f"U+{ord(c):04X}" for c in missing), file=sys.stderr)
		print("Run: python3 tools/make_font.py", file=sys.stderr)
		return 1
	# Explicit regression checks for past tofu bugs (CJK + HUD symbols).
	for s in ("固定视角", "复制数据", "maxΔ", "gnd 0.0cm"):
		bad = [c for c in s if not c.isspace() and ord(c) not in cmap]
		if bad:
			print(f"ERROR: {s!r} still missing {bad}", file=sys.stderr)
			return 1
	# Δ must be present even if a future HUD rename drops the literal from sources.
	if ord("Δ") not in cmap:
		print("ERROR: Greek Δ (U+0394) missing from font subset", file=sys.stderr)
		return 1
	# Latin/Greek companion (Godot shapes these via FontFile.fallbacks).
	latin = ROOT / "fonts" / "ui_latin.otf"
	if not latin.is_file():
		print(f"ERROR: latin fallback missing: {latin}", file=sys.stderr)
		return 1
	lcmap = TTFont(str(latin)).getBestCmap() or {}
	if ord("Δ") not in lcmap:
		print("ERROR: Greek Δ missing from fonts/ui_latin.otf", file=sys.stderr)
		return 1
	print("OK")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
