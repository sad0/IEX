#!/bin/bash
# StickLuaFunctions native-hook test, Linux (run inside WSL): private copy of a Linux game with IEX, the mod
# installed by WeiDU (tp2 patched by tools/compat/patch_mod.py), the probe (tools/stick/probe), one save.
#   bash tools/stick/run_linux.sh [base game] [save folder name]
# Guards: WeiDU without stdin, file size limit, timeout; audio off (SDL_AUDIODRIVER=dummy); no startup movies
# (IEX_SKIP_INTRO=1 + 'Disable Movies' in the copy's Baldur.lua); the game window is moved off screen and only gets
# background key events (xdotool --window); only the game started here is killed. Never saves.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="${1:-$HOME/games/sadonative}"
SAVE="${2:-000000007-Chapter 1 Start}"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-stick}"
MOD=/mnt/e/Dev/IEX-data/mods/stick-lua-functions/src/xbigxiangx-dot-StickLuaFunctions-5872ed0/StickLuaFunctions_v0.11.0-Alpha
TAG="${IEX_TEST_TAG:-}"   # private copy / docs folder suffix (parallel test runs)
COPY="$HOME/games/stick$TAG"
OUT=/mnt/e/Dev/IEX-data/stick
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX stick linux$TAG)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=300

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
if ! grep -qi STICKLUAFUNCTIONS WeiDU.log; then
    rm -rf StickLuaFunctions && cp -r "$MOD/StickLuaFunctions" .
    python3 -I "$SRC/tools/compat/patch_mod.py" StickLuaFunctions
    echo 'lang_dir = en_US' > weidu.conf
    ( ulimit -f 200000; timeout 300 "$HOME/bin/weidu" --game . --language 0 --no-exit-pause --noautoupdate \
        --skip-at-view --log stick.debug --force-install 0 StickLuaFunctions/Setup-StickLuaFunctions.tp2 \
        < /dev/null > stick_install.out 2>&1 )
    tail -2 stick_install.out
    grep -qi STICKLUAFUNCTIONS WeiDU.log || { echo "StickLuaFunctions not installed"; exit 1; }
fi
# SadoEE's M_ files read Windows code addresses (its build probe) and are not under test here: moved out.
mkdir -p override_off
for f in override/M_SQ*.lua override/M_PS*.lua override/M_SNTEST.lua; do [ -f "$f" ] && mv -f "$f" override_off/; done
# IEX build + runtime files
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh
# probe
python3 - "$SRC/tools/stick/probe/stkprb_body.lua" override/M_STKPRB.lua <<'EOF'
import sys
body = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write("local src = [==========[\n" + body + "\n]==========]\n"
    "local fn, err = (loadstring or load)(src, '=stkprb')\nlocal ok = fn ~= nil\n"
    "if fn then ok, err = pcall(fn) end\n"
    "if not ok and IEX_Log then pcall(IEX_Log, '[STKPRB] load error ' .. tostring(err)) end\n")
EOF
cp "$SRC/tools/stick/probe/STKPRB.menu" override/
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
rm -rf "$DOCS/save/"*
cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-STICKTEST"
{ grep -v "Disable Movies\|Auto Pause State" "$DOCSRC/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua"
rm -f IEX/stick_status.txt IEX/stick_out.txt stick_status.txt stick_out.txt IEX.log

status() { cat IEX/stick_status.txt stick_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
./iex-launch.sh > game.out 2>&1 &
PID=$!
t0=$(date +%s); win=""; last=0; result=timeout; shot=""
while [ $(( $(date +%s) - t0 )) -lt $TIMEOUT ]; do
    sleep 0.5
    kill -0 $PID 2>/dev/null || { result="exited ($(status))"; break; }
    if [ -z "$win" ]; then
        win=$(xdotool search --pid $PID 2>/dev/null | tail -1)
        [ -n "$win" ] && xdotool windowmove "$win" -6000 -6000 2>/dev/null
    fi
    st=$(status)
    now=$(date +%s)
    case "$st" in
        *"screen ready"*|loading*|"main file loaded"|"opening load screen")
            if [ $((now - last)) -ge 3 ] && [ -n "$win" ]; then xdotool key --window "$win" F11; last=$now; fi ;;
        observe|forceHit|forceMiss|cancel|spells)
            if [ $((now - last)) -ge 3 ] && [ -n "$win" ]; then xdotool key --window "$win" 1 Return; last=$now; fi ;;
        DONE*) result=done; break ;;
        "save not found"*|*"load error"*) result="$st"; break ;;
    esac
done
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
stamp=$(date +%m%d-%H%M)
cp IEX/stick_out.txt "$OUT/linux$TAG-$stamp.txt" 2>/dev/null || cp stick_out.txt "$OUT/linux$TAG-$stamp.txt" 2>/dev/null
cp IEX.log "$OUT/linux$TAG-$stamp.IEX.log" 2>/dev/null
echo "linux : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/linux$TAG-$stamp.txt"
