#!/usr/bin/env python3
"""Patches llama.cpp's build-xcframework.sh for Lokey (see scripts/bootstrap.sh and docs/INFERENCE.md).

Fails loudly if upstream changed the script, so a llama.cpp bump never silently loses the patch.
Usage: patch_llama_xcframework.py path/to/build-xcframework.sh
"""
import sys

ARM_ARCH = "armv8.4-a+dotprod+fp16"  # A13+ (iOS 26 minimum) and every Apple Silicon Mac

path = sys.argv[1]
script = open(path, encoding="utf-8").read()


def sub(old, new):
    global script
    if old not in script:
        sys.exit(f"patch_llama_xcframework: pattern not found (llama.cpp changed?): {old[:70]!r}")
    script = script.replace(old, new, 1)


# iOS 26 minimum: guarantees DotProd-capable chips.
sub("IOS_MIN_OS_VERSION=16.4", "IOS_MIN_OS_VERSION=26.0")
# No Accelerate BLAS backend.
sub("GGML_BLAS_DEFAULT=ON", "GGML_BLAS_DEFAULT=OFF")
sub("    -DGGML_NATIVE=OFF\n", "    -DGGML_NATIVE=OFF\n    -DGGML_BLAS=OFF\n")
# arm64-only slices with ARM kernels and DotProd/fp16.
sub('-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \\\n        -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator',
    f'-DCMAKE_OSX_ARCHITECTURES="arm64" \\\n        -DGGML_CPU_ARM_ARCH={ARM_ARCH} \\\n        -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator')
sub("-DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \\\n",
    f"-DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \\\n        -DGGML_CPU_ARM_ARCH={ARM_ARCH} \\\n")
sub('-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOS_MIN_OS_VERSION} \\\n        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \\',
    f'-DCMAKE_OSX_DEPLOYMENT_TARGET=${{MACOS_MIN_OS_VERSION}} \\\n        -DCMAKE_OSX_ARCHITECTURES="arm64" \\\n        -DGGML_CPU_ARM_ARCH={ARM_ARCH} \\')
sub('sdk="iphonesimulator"\n                archs="arm64 x86_64"', 'sdk="iphonesimulator"\n                archs="arm64"')
sub('sdk="macosx"\n            archs="arm64 x86_64"', 'sdk="macosx"\n            archs="arm64"')
# Combine only the static libraries that were actually built (no libggml-blas.a now).
sub("    # Create temporary directory for processing\n",
    "    local built=()\n    for lib in \"${libs[@]}\"; do [[ -f \"$lib\" ]] && built+=(\"$lib\"); done\n    libs=(\"${built[@]}\")\n\n"
    "    # Create temporary directory for processing\n")

open(path, "w", encoding="utf-8").write(script)
print(f"patched {path}: arm64-only {ARM_ARCH}, BLAS off, iOS 26 minimum")
