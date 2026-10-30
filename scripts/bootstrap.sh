#!/usr/bin/env bash
# Provides llama.xcframework in Packages/WriterKit/Vendor.
#
# Default: builds it from source (iOS device + iOS Simulator + macOS slices). Since
# llama.cpp PR #27252 (Aug 2026) the official release zip only contains macOS and
# iOS-device slices, so it cannot link Simulator builds.
#
# The source build patches llama.cpp's build-xcframework.sh (docs/INFERENCE.md, item 1):
#  - arm64-only Apple slices with -march=armv8.4-a+dotprod+fp16. Upstream builds the iOS
#    slice for baseline armv8 (no SDOT) and the Simulator/macOS slices as arm64;x86_64, for
#    which ggml compiles no ARM kernels at all. A13+ (iOS 26's minimum) supports DotProd.
#  - Accelerate BLAS off: it dequantizes whole weight matrices into buffers of up to 64 MiB+,
#    which the keyboard extension cannot afford.
#   LLAMA_PREBUILT=1 scripts/bootstrap.sh   # download the official zip instead (device-only builds)
# LFM3 needs llama.cpp b11960 or newer.
set -euo pipefail
cd "$(dirname "$0")/.."
LLAMA_TAG="${LLAMA_TAG:-b12015}"
DEST="Packages/WriterKit/Vendor"
STAMP="$LLAMA_TAG-$([[ "${LLAMA_PREBUILT:-0}" == 1 ]] && echo prebuilt || echo source-dotprod)"

if [[ -d "$DEST/llama.xcframework" && "$(cat "$DEST/.llama-tag" 2>/dev/null)" == "$STAMP" ]]; then
  echo "llama.xcframework $STAMP already present"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ "${LLAMA_PREBUILT:-0}" == 1 ]]; then
  url="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-xcframework.zip"
  echo "Downloading $url"
  curl -fL --retry 4 --retry-delay 2 -o "$tmp/llama.zip" "$url"
  echo "sha256 $(shasum -a 256 "$tmp/llama.zip" | cut -d' ' -f1)"
  if [[ -n "${LLAMA_SHA256:-}" && "$(shasum -a 256 "$tmp/llama.zip" | cut -d' ' -f1)" != "$LLAMA_SHA256" ]]; then
    echo "error: checksum mismatch (expected $LLAMA_SHA256)" >&2
    exit 1
  fi
  unzip -q "$tmp/llama.zip" -d "$tmp/x"
  framework="$(find "$tmp/x" -type d -name 'llama.xcframework' -prune | head -n 1)"
else
  echo "Building llama.xcframework $LLAMA_TAG from source (ios-device, ios-sim, macos)…"
  git clone --quiet --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$tmp/llama.cpp"
  python3 "$(dirname "$0")/patch_llama_xcframework.py" "$tmp/llama.cpp/build-xcframework.sh"
  (cd "$tmp/llama.cpp" && ./build-xcframework.sh ios-device ios-sim macos > "$tmp/build.log" 2>&1) || {
    tail -n 80 "$tmp/build.log"
    exit 1
  }
  framework="$tmp/llama.cpp/build-apple/llama.xcframework"
fi

[[ -d "$framework" ]] || { echo "error: llama.xcframework not found" >&2; exit 1; }

# Binary audit: the iOS slices must contain DotProd (SDOT) instructions.
if [[ "${LLAMA_PREBUILT:-0}" != 1 ]] && command -v xcrun >/dev/null; then
  for slice in "$framework"/ios-arm64 "$framework"/ios-arm64-simulator; do
    bin="$(find "$slice" -type f -name llama -not -path '*dSYM*' | head -n 1)"
    count="$(xcrun llvm-objdump -d --mattr=+dotprod "$bin" | grep -cw sdot || true)"
    echo "audit: $(basename "$slice") sdot=$count"
    [[ "$count" -gt 0 ]] || { echo "error: $(basename "$slice") has no SDOT instructions" >&2; exit 1; }
  done
fi
rm -rf "$DEST/llama.xcframework"
mkdir -p "$DEST"
mv "$framework" "$DEST/llama.xcframework"
echo "$STAMP" > "$DEST/.llama-tag"
ls "$DEST/llama.xcframework"
echo "Installed $DEST/llama.xcframework ($STAMP)"
