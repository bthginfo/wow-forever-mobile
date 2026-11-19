#!/usr/bin/env bash
set -euo pipefail

# Build with Meson, Ninja, glslang and LLVM-MinGW (UCRT).
# Use a DXVK v2.4.1 checkout with its submodules initialized.
if [[ $# -ne 2 ]]; then
    echo "Usage: bash $0 DXVK_SOURCE LLVM_MINGW_BIN" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
dxvk_source="$(cd "$1" && pwd)"
mingw_bin="$(cd "$2" && pwd)"
base_revision=0cf05780abd7250c2cd713b7749cf32180157cf5
if [[ "$(git -C "$dxvk_source" rev-parse HEAD)" != "$base_revision" ]]; then
    echo "Use DXVK revision $base_revision." >&2
    exit 2
fi

build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT
mkdir -p "$build_root/source" "$build_root/package/system32"
git -C "$dxvk_source" archive HEAD | tar -xf - -C "$build_root/source"
for dependency in include/vulkan include/spirv subprojects/libdisplay-info; do
    mkdir -p "$build_root/source/$dependency"
    cp -RL "$dxvk_source/$dependency/." "$build_root/source/$dependency/"
done
git -C "$build_root/source" apply --unidiff-zero "$script_dir/2.4.1-powervr.patch"

cat > "$build_root/arm64.ini" <<EOF
[binaries]
c = '$mingw_bin/aarch64-w64-mingw32-clang'
cpp = '$mingw_bin/aarch64-w64-mingw32-clang++'
ar = '$mingw_bin/llvm-ar'
strip = '$mingw_bin/llvm-strip'
windres = '$mingw_bin/aarch64-w64-mingw32-windres'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

meson setup --cross-file "$build_root/arm64.ini" --buildtype=release --wrap-mode=nodownload \
    -Denable_d3d8=false -Denable_d3d9=false -Denable_d3d10=false "$build_root/build" "$build_root/source"
ninja -C "$build_root/build" src/d3d11/d3d11.dll src/dxgi/dxgi.dll

package="$build_root/package"
for dll in d3d11 dxgi; do
    "$mingw_bin/llvm-strip" --strip-unneeded "$build_root/build/src/$dll/$dll.dll" -o "$package/system32/$dll.dll"
done
cp "$build_root/source/LICENSE" "$package/LICENSE.dxvk"
cp "$build_root/source/subprojects/libdisplay-info/LICENSE" "$package/LICENSE.libdisplay-info"
cat > "$package/profile.json" <<'EOF'
{
  "type": "DXVK",
  "versionName": "2.4.1-wow-powervr",
  "versionCode": 1,
  "description": "Windows ARM64 DXVK 2.4.1 with a BGRA8 storage-view workaround based on GameNative DXVK.",
  "files": [
    { "source": "system32/dxgi.dll", "target": "${system32}/dxgi.dll" },
    { "source": "system32/d3d11.dll", "target": "${system32}/d3d11.dll" }
  ]
}
EOF

destination="$script_dir/../../app/src/pixelTest/assets/bundled_components"
mkdir -p "$destination"
archive="$build_root/dxvk-2.4.1-wow-powervr.wcp"
tar --zstd -cf "$archive" -C "$package" \
    profile.json LICENSE.dxvk LICENSE.libdisplay-info system32
mv "$archive" "$destination/"
