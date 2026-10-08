#!/usr/bin/env python3
"""把 Noto Sans TC 子集化，縮小網頁版下載量。

字元集合＝Big5 常用字（第一級，約 5,400 字，涵蓋 AI 產生的一般文字）＋ Big5 符號區
＋ ASCII ＋ 專案原始碼（client/server）中實際出現的所有字元。保留 wght 可變軸（程式用 450／700）。

用法（需要 fonttools：pip install fonttools）：
  python3 server/tools/subset-font.py
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "client/fonts-src/NotoSansTC-full.ttf"
OUT = ROOT / "client/assets/fonts/NotoSansTC.ttf"


def big5_range(lo: int, hi: int) -> set[str]:
    chars: set[str] = set()
    for lead in range(lo >> 8, (hi >> 8) + 1):
        for trail in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            code = (lead << 8) | trail
            if lo <= code <= hi:
                try:
                    chars.add(bytes([lead, trail]).decode("big5"))
                except UnicodeDecodeError:
                    pass
    return chars


chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= big5_range(0xA140, 0xA3BF)  # 標點與符號
chars |= big5_range(0xA440, 0xC67E)  # 常用字
for pattern in ("client/scripts/**/*.gd", "server/src/**/*.ts", "server/src/**/*.json"):
    for f in ROOT.glob(pattern):
        chars |= set(f.read_text(encoding="utf-8"))
chars = {c for c in chars if c.isprintable() or c.isspace()}

text_file = ROOT / ".web-build-chars.txt"
text_file.write_text("".join(sorted(chars)), encoding="utf-8")
cmd = [sys.executable, "-m", "fontTools.subset", str(SRC), f"--text-file={text_file}",
       f"--output-file={OUT}", "--layout-features=*", "--no-hinting", "--desubroutinize"]
try:
    subprocess.run(cmd, check=True)
finally:
    text_file.unlink(missing_ok=True)
print(f"{len(chars)} 字元：{SRC.stat().st_size / 1048576:.1f} MiB → {OUT.stat().st_size / 1048576:.1f} MiB")
