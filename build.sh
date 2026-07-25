#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
# NT build: set up razzle-style environment and invoke build.exe
# ---------------------------------------------------------------------------
build_nt_source() {
    echo "=== Detected Windows XP (NT 5.1) source tree ==="
    echo ""

    # --- If not already in a Razzle env, set up a minimal one ---------------
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

        # SDK / DDK paths
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

        # Target architecture: i386 free build (matches buildx.cmd "retail" mode)
        export PROCESSOR_ARCHITECTURE=x86
        export _BuildArch=x86
        export _BUILDARCH=x86
        export BUILD_TYPE=fre
        export _BuildType=fre
        export FREEBUILD=1
        export NTDEBUG=ntsdnodbg
        export NTDEBUGTYPE=windbg
        export BUILD_ALT_DIR=""

        # Critical: 386=1 must be set for x86 builds (buildx.cmd sets this)
        export 386=1

        # Build defaults from buildx.cmd
        export BUILD_DEFAULT_TARGETS=-x86
        export BUILD_DEFAULT="daytona -e -E -w -nmake -i"
        export NTBBT=1
        export NO_MAPSYM=1
        export BINPLACE_FLAGS=-xa

        # Output directories (buildx.cmd sets these)
        local drive_letter="${NT_ABS%%:*}"
        export _NTTREE="${drive_letter}:\\binaries.x86fre"
        export _NTPOSTBLD="$_NTTREE"
        export LOGS="$_NTTREE/Build_Logs"
        export _NTx86TREE="$_NTTREE"

        # Makefile build output directories
        export _OBJ_DIR=obj
        export TARGET_DIRECTORY=i386

        # Add DDK / SDK / tools bin to PATH
        local ddk_bin="$OAK_PATH/binr"
        [ -d "$ddk_bin" ] && export PATH="$ddk_bin:$PATH"
        local sdk_bin="$SDK_PATH/bin"
        [ -d "$sdk_bin" ] && export PATH="$sdk_bin:$PATH"
        [ -d "$NT_ABS/tools" ] && export PATH="$NT_ABS/tools:$PATH"
        # Add tools/x86 helper tools to PATH
        [ -d "$NT_ABS/tools/x86" ] && export PATH="$NT_ABS/tools/x86:$PATH"

        echo "  _NTROOT      = $_NTROOT"
        echo "  _NTDRIVE     = $_NTDRIVE"
        echo "  NTMAKEENV    = $NTMAKEENV"
        echo "  TARGET       = i386 free"
        echo "  _NTTREE      = $_NTTREE"
        echo "  386          = $386"
        echo "  SDK_INC_PATH = $SDK_INC_PATH"
        echo "  DDK_INC_PATH = $DDK_INC_PATH"
        echo ""
    else
        echo "Using existing Razzle environment"
        echo "  _NTROOT  = $_NTROOT"
        echo "  _NTDRIVE = ${_NTDRIVE:-<auto>}"
        echo ""
    fi

    # --- Locate build.exe ---------------------------------------------------
    local build_exe=""
    if command -v build &>/dev/null; then
        build_exe="build"
    elif [ -f "$NTMAKEENV/build.exe" ]; then
        build_exe="$NTMAKEENV/build.exe"
    elif [ -f "$NT_SRC/tools/build.exe" ]; then
        build_exe="$NT_SRC/tools/build.exe"
    fi

    if [[ -z "$build_exe" ]]; then
        echo "ERROR: 'build.exe' not found on PATH or in $NT_SRC/tools."
        echo ""
        echo "The NT build system requires build.exe from the Windows DDK/WDK."
        echo "This tool is not included in the source tree."
        echo "Set PATH to include the DDK bin directory, or place build.exe"
        echo "in $NT_SRC/tools/."
        exit 1
    fi

    echo "Build tool: $build_exe"
    echo ""

    mkdir -p build
    mkdir -p dist

    # --- Run the build ------------------------------------------------------
    # Tutorial: build /cZP -M 4
    #   /c = clean build
    #   /Z = suppress default output (quieter)
    #   /P = print build.exe location
    #   -M 4 = max 4 threads (recommended)
    echo "=== Running DDK build: build /cZP -M 4 ==="
    cd "$NT_SRC"
    "$build_exe" /cZP -M 4 2>&1 | tee "$ROOT_DIR/build.log" || true

    # Also save build.err if it was created
    if [ -f build.err ]; then
        cp build.err "$ROOT_DIR/build.err"
    fi
    cd "$ROOT_DIR"

    echo ""
    echo "=== Build log saved to build.log ==="
    if [ -f "$ROOT_DIR/build.err" ]; then
        echo "=== Build errors saved to build.err ==="
        echo "Error count: $(wc -l < "$ROOT_DIR/build.err") lines"
    fi

    # --- Collect build artifacts into dist/ ----------------------------------
    echo "=== Collecting build artifacts ==="

    # Primary: check binaries directory (set by razzle/buildx)
    local binaries_dir=""
    if [[ -n "${_NTTREE:-}" ]]; then
        binaries_dir="${_NTTREE}"
    fi

    if [[ -n "$binaries_dir" ]] && [ -d "$binaries_dir" ]; then
        echo "Collecting from binaries directory: $binaries_dir"
        find "$binaries_dir" \
            -type f \
            \( \
                -name "*.exe" -o \
                -name "*.dll" -o \
                -name "*.sys" -o \
                -name "*.lib" \
            \) \
            -exec cp "{}" dist/ \; \
            2>/dev/null || true
    fi

    # Fallback: also search the source tree for any built artifacts
    echo "Also scanning source tree for artifacts..."
    find "$NT_SRC" \
        -type f \
        \( \
            -name "*.exe" -o \
            -name "*.dll" -o \
            -name "*.sys" \
        \) \
        -not -path "*/tools/*" \
        -not -path "*/public/*" \
        -newer "$NT_SRC/dirs" \
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
