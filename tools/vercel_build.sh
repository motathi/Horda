#!/usr/bin/env bash
# Build da versão web no Vercel: baixa o Godot 4.3 (headless), importa os
# assets e exporta o preset "Web" para build/web (servido como site estático).
set -euo pipefail
cd "$(dirname "$0")/.."
VER="4.3-stable"
BIN="Godot_v${VER}_linux.x86_64"
TMP="${TMPDIR:-/tmp}/godot-build"
mkdir -p "$TMP"
if [ ! -x "$TMP/$BIN" ]; then
  echo ">> baixando Godot $VER"
  curl -fsSL -o "$TMP/godot.zip" "https://github.com/godotengine/godot/releases/download/${VER}/${BIN}.zip"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$TMP/godot.zip" -d "$TMP"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMP/godot.zip" "$TMP"
  else
    (cd "$TMP" && npx --yes extract-zip godot.zip "$TMP")
  fi
  chmod +x "$TMP/$BIN"
fi
GODOT="$TMP/$BIN"
mkdir -p build/web
echo ">> importando assets"
"$GODOT" --headless --import >/dev/null 2>&1 || true
echo ">> exportando Web"
"$GODOT" --headless --export-release "Web" build/web/index.html
test -s build/web/index.pck && test -s build/web/index.wasm
ls -la build/web
