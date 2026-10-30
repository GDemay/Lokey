#!/usr/bin/env bash
# Benchmarks catalog models with an official llama.cpp `llama-server` build (any OS).
#   LLAMA_SERVER=/path/llama-server MODEL_CACHE=.models scripts/ci/eval-server.sh <model-id>...
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${LLAMA_SERVER:?path to llama-server}"
CACHE="${MODEL_CACHE:-.models}"
OUT="${EVAL_OUT:-artifacts/eval}"
THREADS="${THREADS:-4}"
JFLEG_N="${JFLEG_N:-150}"
mkdir -p "$OUT"
python3 eval/fetch_jfleg.py eval/data/jfleg_test.json
for id in "$@"; do
  read -r file fmt < <(python3 -c 'import json,sys
m=[m for m in json.load(open(sys.argv[1]))["models"] if m["id"]==sys.argv[2]][0]
print(m["file"], m["format"])' Packages/WriterKit/Sources/WritingCore/Resources/models.json "$id")
  "$LLAMA_SERVER" -m "$CACHE/$file" -c 4096 -t "$THREADS" --port 8089 --no-webui >"$OUT/$id.server.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 120); do curl -sf http://127.0.0.1:8089/health >/dev/null && break; sleep 1; done
  python3 eval/bench.py --server http://127.0.0.1:8089 --model "$CACHE/$file" --format "$fmt" \
    --jfleg eval/data/jfleg_test.json --jfleg-n "$JFLEG_N" --out "$OUT/$id.json" 2>"$OUT/$id.log" | tee "$OUT/$id.summary.json"
  kill "$pid"; wait "$pid" 2>/dev/null || true
done
python3 eval/report.py "$OUT"/*.json > "$OUT/REPORT.md"
cat "$OUT/REPORT.md"
