#!/usr/bin/env bash
# Downloads catalog models (Packages/WriterKit/Sources/WritingCore/Resources/models.json)
# into $MODEL_CACHE (default: .models), verifying SHA-256.
#   scripts/fetch-model.sh lfm2.5-1.2b-instruct-q4 lfm2.5-350m-q4
set -euo pipefail
cd "$(dirname "$0")/.."
CACHE="${MODEL_CACHE:-.models}"
mkdir -p "$CACHE"
CATALOG="Packages/WriterKit/Sources/WritingCore/Resources/models.json"
for id in "$@"; do
  read -r file url sha < <(python3 -c 'import json,sys
m=[m for m in json.load(open(sys.argv[1]))["models"] if m["id"]==sys.argv[2]]
if not m: sys.exit("unknown model id: "+sys.argv[2])
print(m[0]["file"], m[0]["url"], m[0]["sha256"])' "$CATALOG" "$id")
  path="$CACHE/$file"
  if [[ -f "$path" ]] && [[ "$(shasum -a 256 "$path" | cut -d' ' -f1)" == "$sha" ]]; then
    echo "$file: cached"
    continue
  fi
  echo "$file: downloading"
  curl -fL --retry 4 --retry-delay 2 -o "$path.part" "$url"
  actual="$(shasum -a 256 "$path.part" | cut -d' ' -f1)"
  [[ "$actual" == "$sha" ]] || { echo "error: $file checksum $actual != $sha" >&2; rm -f "$path.part"; exit 1; }
  mv "$path.part" "$path"
done
