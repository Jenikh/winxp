#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        ;;
    *)
        echo "Windows XP sources can only be built from Windows."
        exit 1
        ;;
esac

NT_SRC="Source/XPSP1/NT"

detect_nt_source() {
    [ -f "$NT_SRC/dirs" ] && [ -d "$NT_SRC/tools" ] && [ -d "$NT_SRC/public" ]
}

build_nt_source() {
    echo "=== Detected Windows XP (NT 5.1) source tree ==="
    echo ""

    if [[ -z "${_NTROOT:-}" ]]; then
        echo "No Razzle environment detected - setting up minimal NT build env"
        echo ""

        local NT_ABS
        NT_ABS="$(cd "$NT_SRC" && pwd -W 2>/dev/null || pwd)"

        export _NTDRIVE="${NT_ABS%%/*}"
        export _NTROOT="${NT_ABS#$_NTDRIVE}"
        export _NTDRIVE="${_NTDRIVE}/"

        export NTMAKEENV="$NT_ABS/tools"
        export RAZZLETOOLPATH="$NT_ABS/tools"
        export BASEDIR="$NT_ABS"
        export _NTOBJDIR="obj"
        export _NTLIBDIR="lib"

        export SDK_PATH="$NT_ABS/public/sdk"
        export SDK_INC_PATH="$SDK_PATH/inc"
        export SDK_LIB_PATH="$SDK_PATH/lib"
        export DDK_PATH="$NT_ABS/public/ddk"
        export DDK_INC_PATH="$DDK_PATH/inc"
        export DDK_LIB_PATH="$DDK_PATH/lib"
        export OAK_PATH="$NT_ABS/public/oak"
        export OAK_INC_PATH="$OAK_PATH/inc"
        export CRT_INC_PATH="$SDK_INC_PATH/crt"
        export CRT_LIB_PATH="$SDK_LIB_PATH"
        export WDM_INC_PATH="$DDK_PATH/inc/wdm"
        export PUBLIC_INTERNAL_PATH="$NT_ABS/public/internal"
        export WPP_CONFIG_PATH="$NT_ABS/tools/WppConfig"

        export PROCESSOR_ARCHITECTURE=x86
        export _BUILDARCH=x86
        export BUILD_TYPE=fre
        export FREEBUILD=1
        export NTDEBUG=ntsdnodbg
        export BUILD_ALT_DIR=""

        export _OBJ_DIR=obj
        export TARGET_DIRECTORY=i386

        local ddk_bin="$OAK_PATH/binr"
        [ -d "$ddk_bin" ] && export PATH="$ddk_bin:$PATH"
        local sdk_bin="$SDK_PATH/bin"
        [ -d "$sdk_bin" ] && export PATH="$sdk_bin:$PATH"
        [ -d "$NT_ABS/tools" ] && export PATH="$NT_ABS/tools:$PATH"
        [ -d "$NT_ABS/tools/x86" ] && export PATH="$NT_ABS/tools/x86:$PATH"

        echo "  _NTROOT      = $_NTROOT"
        echo "  _NTDRIVE     = $_NTDRIVE"
        echo "  NTMAKEENV    = $NTMAKEENV"
        echo "  TARGET       = i386 free"
        echo "  SDK_INC_PATH = $SDK_INC_PATH"
        echo "  DDK_INC_PATH = $DDK_INC_PATH"
        echo ""
    else
        echo "Using existing Razzle environment"
        echo "  _NTROOT  = $_NTROOT"
        echo "  _NTDRIVE = ${_NTDRIVE:-<auto>}"
        echo ""
    fi

    local build_exe=""
    if command -v build &>/dev/null; then
        build_exe="build"
    elif [ -f "$NTMAKEENV/build.exe" ]; then
        build_exe="$NTMAKEENV/build.exe"
    elif [ -f "$NT_SRC/tools/build.exe" ]; then
        build_exe="$NT_SRC/tools/build.exe"
    fi

    if [[ -z "$build_exe" ]]; then
        echo "ERROR: build.exe not found on PATH or in $NT_SRC/tools."
        echo ""
        echo "The NT build system requires build.exe from the Windows DDK/WDK."
        echo "Set PATH to include the DDK bin directory."
        exit 1
    fi

    echo "Build tool: $build_exe"
    echo ""

    mkdir -p build
    mkdir -p dist

    echo "=== Running DDK build ==="
    cd "$NT_SRC"
    "$build_exe" -cZ 2>&1 | tee "$ROOT_DIR/build.log" || true
    cd "$ROOT_DIR"

    echo ""
    echo "=== Build log saved to build.log ==="

    echo "=== Collecting build artifacts ==="
    find "$NT_SRC" -type f \( -name "*.exe" -o -name "*.dll" -o -name "*.sys" -o -name "*.lib" \) -not -path "*/tools/*" -exec cp "{}" dist/ \; 2>/dev/null || true

    local count
    count=$(find dist -maxdepth 1 -type f 2>/dev/null | wc -l)
    echo "Copied $count build artifact(s) into dist/"
}

build_standard() {
    echo "=== No NT source tree detected - trying standard build systems ==="
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
        exit 1
    fi

    mkdir -p dist
    cp -r build/* dist/ 2>/dev/null || true
}

if detect_nt_source; then
    build_nt_source
else
    build_standard
fi
