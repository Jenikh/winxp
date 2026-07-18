#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# ---------------------------------------------------------------------------
# Detect the NT source tree
# ---------------------------------------------------------------------------
NT_SRC="Source/XPSP1/NT"

detect_nt_source() {
    [ -f "$NT_SRC/dirs" ] && [ -d "$NT_SRC/tools" ] && [ -d "$NT_SRC/public" ]
}

# ---------------------------------------------------------------------------
# NT build: set up the razzle-style environment and run build.exe / nmake
# ---------------------------------------------------------------------------
build_nt_source() {
    echo "=== Detected Windows XP (NT 5.1) source tree ==="
    echo ""

    # --- Locate the DDK build tool -------------------------------------------
    local build_exe=""
    if command -v build &>/dev/null; then
        build_exe="build"
    elif [ -f "$NT_SRC/tools/build.exe" ]; then
        build_exe="$NT_SRC/tools/build.exe"
    fi

    # --- Locate nmake (fallback) --------------------------------------------
    local nmake_cmd=""
    if command -v nmake &>/dev/null; then
        nmake_cmd="nmake"
    fi

    if [ -z "$build_exe" ] && [ -z "$nmake_cmd" ]; then
        echo "ERROR: Neither 'build' (DDK) nor 'nmake' found on PATH."
        echo ""
        echo "This source tree requires the Windows DDK/WDK build tools."
        echo "Please install the Windows Server 2003 DDK or a compatible WDK,"
        echo "then run this script from a razzle command window:"
        echo ""
        echo "  1.  Open a Command Prompt as Administrator"
        echo "  2.  cd $NT_SRC/tools"
        echo "  3.  razzle"
        echo "  4.  cd <repo-root>"
        echo "  5.  build.sh"
        echo ""
        echo "Alternatively, you can compile individual components manually:"
        echo "  cd $NT_SRC/<subdir>/<component>"
        echo "  nmake -f makefile.def"
        exit 1
    fi

    # --- Set up minimal environment variables --------------------------------
    # These mirror what razzle.cmd / setenv.bat normally provide.
    export BASEDIR="$(pwd)/$NT_SRC"
    export _NTDRIVE="${BASEDIR%%:*}"
    export _NTROOT="/${BASEDIR#*:}"
    [ -z "$_NTROOT" ] && _NTROOT="/nt"
    export NTMAKEENV="$NT_SRC/tools"
    export RAZZLETOOLPATH="$NT_SRC/tools"

    # Tool paths used by makefile.plt / makefile.def
    export SDK_PATH="$NT_SRC/public/sdk"
    export SDK_INC_PATH="$SDK_PATH/inc"
    export SDK_LIB_PATH="$SDK_PATH/lib/*"
    export DDK_PATH="$NT_SRC/public/ddk"
    export DDK_INC_PATH="$DDK_PATH/inc"
    export DDK_LIB_PATH="$DDK_PATH/lib/*"
    export OAK_INC_PATH="$NT_SRC/public/oak/inc"
    export CRT_INC_PATH="$SDK_INC_PATH/crt"
    export CRT_LIB_PATH="$SDK_LIB_PATH"
    export WDM_INC_PATH="$DDK_INC_PATH/wdm"
    export PUBLIC_INTERNAL_PATH="$NT_SRC/public/internal"
    export WPP_CONFIG_PATH="$NT_SRC/tools/WppConfig"

    # Default target: i386 free build
    export 386=1
    export AMD64=0
    export IA64=0
    export FREEBUILD=1
    export NTDEBUG="ntsdnodbg"
    export BUILD_TYPE="fre"
    export TARGET_DIRECTORY="i386"
    export _OBJ_DIR="obj"

    # Add DDK and SDK bin directories to PATH
    local ddk_bin="$NT_SRC/public/oak/binr"
    [ -d "$ddk_bin" ] && export PATH="$ddk_bin:$PATH"
    local sdk_bin="$NT_SRC/public/sdk/bin"
    [ -d "$sdk_bin" ] && export PATH="$sdk_bin:$PATH"

    echo "Environment:"
    echo "  BASEDIR      = $BASEDIR"
    echo "  NTMAKEENV    = $NTMAKEENV"
    echo "  TARGET       = i386 (free)"
    echo "  SDK_INC_PATH = $SDK_INC_PATH"
    echo "  DDK_INC_PATH = $DDK_INC_PATH"
    echo ""

    mkdir -p build
    mkdir -p dist

    # --- Try build.exe first, then fall back to nmake -----------------------
    if [ -n "$build_exe" ]; then
        echo "=== Running DDK build ==="
        cd "$NT_SRC"
        $build_exe -cZ -w -j . 2>&1 | tee "$ROOT_DIR/build.log" || true
        cd "$ROOT_DIR"
    else
        echo "=== Running nmake on makefile.def ==="
        cd "$NT_SRC"
        $nmake_cmd -f makefile.def 2>&1 | tee "$ROOT_DIR/build.log" || true
        cd "$ROOT_DIR"
    fi

    echo ""
    echo "=== Build log saved to build.log ==="

    # --- Collect output into dist/ -------------------------------------------
    echo "=== Collecting build artifacts ==="
    # The NT build places output under obj/i386/ directories scattered
    # throughout the source tree. Gather them.
    find "$NT_SRC" -type f \( -name "*.exe" -o -name "*.dll" -o -name "*.sys" -o -name "*.lib" \) \
        -not -path "*/tools/*" 2>/dev/null | head -200 > dist/manifest.txt || true

    local count
    count=$(wc -l < dist/manifest.txt 2>/dev/null || echo 0)
    echo "Found $count build artifact(s). See dist/manifest.txt"
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
