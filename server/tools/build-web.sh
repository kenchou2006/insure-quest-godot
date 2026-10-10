#!/usr/bin/env bash
# Export Godot web build to ../web and compress (Workers single-file 25 MiB limit).
# Use GODOT environment variable to specify Godot binary path if needed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
  if command -v godot >/dev/null 2>&1; then GODOT_BIN=godot
  elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  else echo "找不到 Godot，請設定 GODOT=/path/to/godot" >&2; exit 1; fi
fi
# Export and compress into staging directory first, then swap into ../web:
# Prevents wrangler dev from aborting on uncompressed 38 MiB wasm, and preserves ../web directory itself
STAGE=../.web-build
rm -rf "$STAGE" && mkdir -p "$STAGE" ../web
"$GODOT_BIN" --headless --path ../client --export-release "Web" "$STAGE/index.html"
# Export build version so both Godot web export and pack-web share it
export IQ_BUILD="${IQ_BUILD:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)-$(date +%s)}"
# Try generating maskable icon if sharp is installed (safe to ignore failure)
node tools/gen-maskable.mjs 2>/dev/null || true
# Guest solo practice runs in the browser: bundle the game engine as a standalone script (see src/local/local-room.ts)
npx esbuild src/local/local-room.ts --bundle --format=iife --platform=browser --target=es2022 --minify --outfile="$STAGE/local-room.js"
# Must match BASE_PATH in wrangler.jsonc (production)
export IQ_BASE_PATH="${IQ_BASE_PATH:-/insure-quest}"
ASSET_DIR="${IQ_BASE_PATH#/}"
node tools/pack-web.mjs "$STAGE"
# Assets live under the BASE_PATH folder so the asset router matches /insure-quest/* without running the Worker.
# _headers must sit at the assets root, so move it there (pack-web already prefixed its paths).
find ../web -mindepth 1 -delete
mkdir -p "../web/$ASSET_DIR"
mv "$STAGE/_headers" ../web/_headers
cp -R "$STAGE"/. "../web/$ASSET_DIR/"
rm -rf "$STAGE"
