#!/usr/bin/env bash
set -euo pipefail

if (( $# != 4 )); then
    printf 'Usage: %s <NDK LLVM bin directory> <MinGW UCRT include directory> <bundled Proton .wcp> <output.exe>\n' "$0" >&2
    exit 2
fi

bridge_dir=$(cd -- "$(dirname -- "$0")" && pwd)
toolchain=$1
headers=$2
runtime=$3
output=$4
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
mkdir -p -- "$(dirname -- "$output")"

prefix=lib/wine/aarch64-windows
runtime_libs=(compiler-rt advapi32 crypt32 iphlpapi kernel32 ntdll ucrtbase shell32 user32 ws2_32)
archive_entries=()
link_inputs=()
for library in "${runtime_libs[@]}"; do
    entry="$prefix/lib$library.a"
    archive_entries+=("$entry")
    link_inputs+=("$build_dir/$entry")
done
tar --zstd -xf "$runtime" -C "$build_dir" -- "${archive_entries[@]}"

flags=(--target=aarch64-w64-windows-gnu -std=c11 -Os -Wall -Wextra -fno-ident
       -D__USE_MINGW_ANSI_STDIO=0 -isystem "$headers" -ffile-prefix-map="$bridge_dir"=.)
for source in bridge protocol win32-entry; do
    "$toolchain/clang" "${flags[@]}" -Werror -c "$bridge_dir/$source.c" -o "$build_dir/$source.o"
done
"$toolchain/clang" "${flags[@]}" -Dprintf=bridge_device_printf -Dputs=bridge_device_puts \
    -c "$bridge_dir/device_id.c" -o "$build_dir/device_id.o"
"$toolchain/lld-link" /machine:arm64 /subsystem:windows /entry:mainCRTStartup /nodefaultlib \
    /timestamp:0 /out:"$output" "$build_dir"/{bridge,protocol,device_id,win32-entry}.o "${link_inputs[@]}"
