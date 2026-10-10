#!/usr/bin/env python3
"""Generate server/src/s2t-map.json: Simplified -> Taiwan Traditional character map for AI output.

Only characters that cannot appear in Taiwan Traditional text (not encodable in Big5/cp950) are
converted, so names and words like 宿舍、范、杰、了、面、里程 are never changed. A short curated list
of Big5-valid but simplified-only-in-practice characters (体、听、万…) is added on top.

Usage (needs opencc-python-reimplemented: pip install opencc-python-reimplemented):
  python3 server/tools/gen-s2t.py
"""
import json
import pathlib

from opencc import OpenCC

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "server/src/s2t-map.json"
# Big5-valid, but in Taiwan writing these only appear as simplified forms
EXTRA = "万与丰优体儿党厂吨听坏复宁尸岭异怀怜惊愿扰挂据晒极构气确离种筑网苹荐蚕蜡触赶"

cc = OpenCC("s2tw")


def big5(ch: str) -> bool:
    try:
        ch.encode("cp950")
        return True
    except UnicodeEncodeError:
        return False


out: dict[str, str] = {}
for code in list(range(0x3400, 0x4DC0)) + list(range(0x4E00, 0xA000)):
    ch = chr(code)
    t = cc.convert(ch)
    if len(t) == 1 and t != ch and (not big5(ch) or ch in EXTRA) and big5(t):
        out[ch] = t
OUT.write_text(json.dumps(dict(sorted(out.items())), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(out)} characters -> {OUT} ({OUT.stat().st_size} bytes)")
