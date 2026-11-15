#!/usr/bin/env bash
# Teste do coop: anfitrião e cliente em dois processos (ENet em 127.0.0.1).
# Uso: GODOT=/caminho/godot tools/run_coop_test.sh
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${TMPDIR:-/tmp}/horda_coop"
mkdir -p "$OUT"
"$GODOT" --headless res://tests/coop_test.tscn -- --role=host > "$OUT/host.log" 2>&1 &
HOST=$!
"$GODOT" --headless res://tests/coop_test.tscn -- --role=client > "$OUT/client.log" 2>&1 &
CLIENT=$!
wait $HOST; H=$?
wait $CLIENT; C=$?
grep -hE "PASS|FAIL|SCRIPT ERROR|==" "$OUT/host.log" "$OUT/client.log" | grep -v "Parameter"
echo "anfitrião=$H cliente=$C"
[ $H -eq 0 ] && [ $C -eq 0 ]
