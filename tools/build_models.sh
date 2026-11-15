#!/usr/bin/env bash
# Pipeline dos modelos 3D gerados por IA:
#   assets/concepts/*.jpg  (conceito gerado na ARK / Seedream)
#   -> image-to-3D (Higgsfield SAM 3D)  -> assets/models/raw/<nome>.glb
#   -> tools/fix_glb.py  (normais, base em y=0, centralizado)
#   -> tools/bake_models.gd (decimação + LODs + textura) -> assets/models/<nome>.res + textures/<nome>.jpg
# Uso: GODOT=/caminho/godot tools/build_models.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
declare -A TRIS=([hero]=14000 [zombie]=5000 [zombie_fast]=5000 [zombie_brute]=7000 [wall]=6000 [gate]=3000 \
  [tree]=2500 [rock]=1500 [house]=9000 [cart]=4000 [tower]=9000 [keep]=20000)
JOBS=()
for n in "${!TRIS[@]}"; do
  [ -f "assets/models/raw/$n.glb" ] || continue
  python3 tools/fix_glb.py "assets/models/raw/$n.glb" "$TMP/$n.glb"
  JOBS+=("$n:$TMP/$n.glb:${TRIS[$n]}")
done
"$GODOT" --headless --script res://tools/bake_models.gd -- "${JOBS[@]}"
python3 - <<'PY'
from PIL import Image; import glob, os
for f in glob.glob("assets/models/textures/*.png"):
    Image.open(f).convert("RGB").save(f[:-4] + ".jpg", quality=90); os.remove(f)
PY
