#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# ---------------------------------------------------------------------------
# Only run on Windows (MSYS / MinGW / Cygwin)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        ;;
    *)
        echo "Windows XP sources can only be built from Windows."
        echo "Use MSYS2, Git Bash, or a Razzle command prompt."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Detect the NT source tree
# ---------------------------------------------------------------------------
NT_SRC="Source/XPSP1/NT"

detect_nt_source() {
    [ -f "$NT_SRC/dirs" ] && [ -d "$NT_SRC/tools" ] && [ -d "$NT_SRC/public" ]
}

# ---------------------------------------------------------------------------
# NT build: verify razzle environment, invoke build.exe, collect artifacts
# ---------------------------------------------------------------------------
build_nt_source() {
    echo "=== Detected Windows XP (NT 5.1) source tree ==="
    echo ""

    # --- Verify we are inside a Razzle environment --------------------------
    if [[ -z "${_NTROOT:-}" ]]; then
        echo "ERROR: Not running inside a Razzle environment."
        echo ""
        echo "The NT source tree is present but build.exe requires the"
        echo "Razzle build environment. To build:"
        echo ""
        echo "    cmd /k"
        echo "    cd $NT_SRC\\tools"
        echo "    razzle free"
        echo "    cd /d $(cygpath -w "$ROOT_DIR" 2>/dev/null || echo '<repo-root>')"
        echo "    bash build.sh"
        echo ""
        echo "Cannot proceed without Razzle. Exiting."
        exit 1
    fi

    # --- Locate the DDK build tool ------------------------------------------
    local build_exe=""
    if command -v build &>/dev/null; then
        build_exe="build"
    elif [ -f "$NT_SRC/tools/build.exe" ]; then
        build_exe="$NT_SRC/tools/build.exe"
    fi

    if [[ -z "$build_exe" ]]; then
        echo "ERROR: 'build.exe' not found on PATH or in $NT_SRC/tools."
        echo ""
        echo "Ensure the DDK/WDK is installed and razzle has been run."
        exit 1
    fi

    echo "Using build tool: $build_exe"
    echo "  _NTROOT  = ${_NTROOT}"
    echo "  _NTDRIVE = ${_NTDRIVE:-<auto>}"
    echo ""

    mkdir -p build
    mkdir -p dist

    # --- Run the build ------------------------------------------------------
    echo "=== Running DDK build ==="
    cd "$NT_SRC"
    "$build_exe" -cZ 2>&1 | tee "$ROOT_DIR/build.log" || true
    cd "$ROOT_DIR"

    echo ""
    echo "=== Build log saved to build.log ==="

    # --- Collect build artifacts into dist/ ----------------------------------
    echo "=== Collecting build artifacts ==="

    find "$NT_SRC" \
        -type f \
        \( \
            -name "*.exe" -o \
            -name "*.dll" -o \
            -name "*.sys" -o \
            -name "*.lib" \
        \) \
        -not -path "*/tools/*" \
        -exec cp "{}" dist/ \; \
        2>/dev/null || true

    local count
    count=$(find dist -maxdepth 1 -type f 2>/dev/null | wc -l)
    echo "Copied $count build artifact(s) into dist/"
}

# ---------------------------------------------------------------------------
# Standard build systems (Makefile / configure / CMakeLists.txt)
# ---------------------------------------------------------------------------
build_standard() {
    echo "=== No NT source tree detected — trying standard build systems ==="
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
        echo "No supported build system detected."
        echo "Expected one of: Makefile, configure, CMakeLists.txt, or an NT source tree."
        exit 1
    fi

    mkdir -p dist
    cp -r build/* dist/ 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if detect_nt_source; then
    build_nt_source
else
    build_standard
fi
