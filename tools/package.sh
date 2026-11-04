#!/bin/sh
# Builds the installable IEX WeiDU mod folder: dist/IEX/ (tp2, Lua runtime, engine descriptions, binaries), plus the
# companion mod dist/SpellSlots/ (spell slots 51-99, install right after IEX).
# Usage: tools/package.sh <out dir>   (copy <out dir>/IEX, <out dir>/SpellSlots and the platform's setup-*.exe next
# to the game)
# Binaries are taken from build/ (Windows, MSVC) and from the WSL build ~/iex-build (Linux) when present.
set -e
cd "$(dirname "$0")/.."
out="${1:-dist}"
rm -rf "$out/IEX" "$out/SpellSlots"
mkdir -p "$out/IEX/engine" "$out/IEX/bin/win64" "$out/IEX/bin/linux64"
cp weidu/IEX/IEX.tp2 VERSION "$out/IEX/"
cp lua/*.lua "$out/IEX/"
mkdir -p "$out/IEX/ui"
cp ui/*.menu "$out/IEX/ui/"
# EEex names IEX defines, for install-time function checks (tools/compat/patch_mod.py rule 7)
python -I tools/compat/api_list.py "$out/IEX/IEX_API.txt"
cp engine/*.iexd "$out/IEX/engine/"
[ -f build/IEX.dll ] && cp build/IEX.dll build/IEXLauncher.exe "$out/IEX/bin/win64/"
if [ -n "$IEX_LINUX_SO" ] && [ -f "$IEX_LINUX_SO" ]; then cp "$IEX_LINUX_SO" "$out/IEX/bin/linux64/libiex.so"; fi
cp tools/linux/iex-launch.sh "$out/IEX/bin/linux64/"
cp -r weidu/SpellSlots "$out/SpellSlots"
# Release archives, one per platform (same IEX/ layout; binaries of the other platform left out).
if command -v zip > /dev/null; then
    ver=$(cat VERSION)
    (cd "$out" && rm -f "IEX-$ver-windows-x64.zip" "IEX-$ver-linux-x64.zip"         && zip -qr "IEX-$ver-windows-x64.zip" IEX SpellSlots -x "IEX/bin/linux64/*"         && zip -qr "IEX-$ver-linux-x64.zip" IEX SpellSlots -x "IEX/bin/win64/*")
fi
echo "packaged $out/IEX and $out/SpellSlots"
