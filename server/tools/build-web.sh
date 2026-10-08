#!/usr/bin/env bash
# 匯出 Godot 網頁版到 ../web 並壓縮（Workers 單檔 25 MiB 限制）。
# 可用 GODOT 環境變數指定 Godot 執行檔路徑。
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
  if command -v godot >/dev/null 2>&1; then GODOT_BIN=godot
  elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  else echo "找不到 Godot，請設定 GODOT=/path/to/godot" >&2; exit 1; fi
fi
# 先匯出並壓縮到暫存資料夾，完成後才換進 ../web：
# 避免 wrangler dev 監看到尚未壓縮的 38 MiB wasm 而中止，也保留 ../web 資料夾本身
STAGE=../.web-build
rm -rf "$STAGE" && mkdir -p "$STAGE" ../web
"$GODOT_BIN" --headless --path ../client --export-release "Web" "$STAGE/index.html"
node tools/pack-web.mjs "$STAGE"
find ../web -mindepth 1 -delete
cp -R "$STAGE"/. ../web/
rm -rf "$STAGE"
