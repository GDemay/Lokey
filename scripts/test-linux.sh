#!/usr/bin/env bash
# Builds and tests WriterKit on Linux against a llama.cpp shared library.
#
#   LLAMA_PREFIX  directory containing include/llama.h and lib/libllama.so
#                 (a `pip install llama-cpp-python` site-packages dir works)
#   LOKEY_TEST_MODEL / LOKEY_TEST_FORMAT / LOKEY_EVAL_CASES  enable the integration tests
set -euo pipefail
cd "$(dirname "$0")/../Packages/WriterKit"
: "${LLAMA_PREFIX:?set LLAMA_PREFIX to a dir with include/llama.h and lib/libllama.so}"
FLAGS=(-Xcc "-I$LLAMA_PREFIX/include" -Xlinker "-L$LLAMA_PREFIX/lib" -Xlinker -rpath -Xlinker "$LLAMA_PREFIX/lib")
swift build --build-tests "${FLAGS[@]}"
swift test --skip-build "${FLAGS[@]}" "$@"
