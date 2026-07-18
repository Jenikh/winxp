#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

mkdir -p build

if [ -f Makefile ]; then
    make -j"$(nproc)"
elif [ -f configure ]; then
    ./configure
    make -j"$(nproc)"
elif [ -f CMakeLists.txt ]; then
    cmake -S . -B build
    cmake --build build --parallel
else
    echo "No supported build system detected (Makefile/configure/CMakeLists.txt)."
    exit 1
fi

mkdir -p dist
cp -r build/* dist/ 2>/dev/null || true
