#!/bin/bash
# Engine-fix test, Linux (run inside WSL): private copy of a Linux game with IEX, the probe (tools/fixtest/probe) and
# its test resources (make_res.py), one save. Engine fixes off (IEX_ENGINE_FIXES=0: the engine bugs) or on.
#   bash tools/fixtest/run_linux.sh on|off [base game] [save folder name]
# Guards: WeiDU without stdin, file size limit, timeout; audio off; no startup movies; the game window is moved off
# screen and only gets background key events (xdotool --window); only the game started here is killed. Never saves.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
FIXES="${1:-on}"
BASE="${2:-$HOME/games/sadonative}"
SAVE="${3:-000000007-Chapter 1 Start}"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-fixes}"
COPY="$HOME/games/fixtest"
OUT=/mnt/e/Dev/IEX-data/fixtest
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX fixtest linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=240
TAG="linux-fixes$FIXES"

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
mkdir -p override
if ! ls override | grep -qi '^splprot.2da$'; then
    ( ulimit -f 200000; timeout 120 "$HOME/bin/weidu" --game . --noautoupdate --no-exit-pause --biff-get splprot.2da \
        --out override < /dev/null > fixtest_weidu.out 2>&1 )
fi
python3 -I "$SRC/tools/fixtest/make_res.py" override || exit 1
# SadoEE's M_ files read Windows code addresses (its build probe) and are not under test here: moved out.
mkdir -p override_off
for f in override/M_SQ*.lua override/M_PS*.lua override/M_SNTEST.lua override/M_STKPRB.lua; do
    [ -f "$f" ] && mv -f "$f" override_off/
done
# IEX build + runtime files
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh
# probe
python3 - "$SRC/tools/fixtest/probe/fxt_body.lua" override/M_FXT.lua <<'EOF'
import sys
body = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write("local src = [==========[\n" + body + "\n]==========]\n"
    "local fn, err = (loadstring or load)(src, '=fxt')\nlocal ok = fn ~= nil\n"
    "if fn then ok, err = pcall(fn) end\n"
    "if not ok and IEX_Log then pcall(IEX_Log, '[FXT] load error ' .. tostring(err)) end\n")
EOF
cp "$SRC/tools/fixtest/probe/FXT.menu" override/
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
rm -rf "$DOCS/save/"*
cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-FIXTEST"
{ grep -v "Disable Movies\|Auto Pause State" "$DOCSRC/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua"
rm -f IEX/fixtest_status.txt IEX/fixtest_out.txt IEX.log

status() { cat IEX/fixtest_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
if [ "$FIXES" = off ]; then export IEX_ENGINE_FIXES=0; else unset IEX_ENGINE_FIXES; fi
./iex-launch.sh > game.out 2>&1 &
PID=$!
t0=$(date +%s); win=""; last=0; result=timeout
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
        DONE*) result=done; break ;;
        "save not found"*|*"load error"*) result="$st"; break ;;
    esac
done
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
cp IEX/fixtest_out.txt "$OUT/$TAG.txt" 2>/dev/null
cp IEX.log "$OUT/$TAG.IEX.log" 2>/dev/null
echo "$TAG : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$TAG.txt"
