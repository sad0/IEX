#!/bin/bash
# Engine-fix test 2, Linux (run inside WSL): private copy of the vanilla Linux BG2EE 2.7.3 test game with IEX, the
# probe (tools/fixtest2/probe) and its test resources (make_res.py), the "Chapter 1 Start" save. Engine fixes off
# (IEX_ENGINE_FIXES=0), on, or some off (IEX_ENGINE_FIXES_OFF); the process memory is sampled at the probe's
# 'mem <tag>' marks (VmRSS, VmData).
#   bash tools/fixtest2/run_linux.sh on|off [main|op248|startup2da|rest] [off list] [tag]
# Guards: audio off, no startup movies, the window is moved off screen and only gets background key events
# (xdotool --window); only the game started here is killed. Never saves.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
FIXES="${1:-on}"
MODE="${2:-main}"
OFFLIST="${3:-}"
BASE=/mnt/e/Dev/IEX-data/testgame/bg2ee-linux-2.7.3
SAVE="000000007-Chapter 1 Start"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-fixes2}"
COPY="$HOME/games/fixes2"
OUT=/mnt/e/Dev/IEX-data/fixtest2
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX fixes2 linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=600
TAG="${4:-linux-$MODE-fixes$FIXES${OFFLIST:+-off-${OFFLIST//,/+}}}"

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
mkdir -p override override_off
for f in override/M_*.lua; do
    case "$f" in override/M_FX2*.lua) ;; *) [ -f "$f" ] && mv -f "$f" override_off/ ;; esac
done
python3 -I "$SRC/tools/fixtest2/make_res.py" override "$MODE" || exit 1
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh
python3 - "$SRC/tools/fixtest2/probe/fx2_body.lua" override/M_FX2.lua <<'EOF'
import sys
body = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write("local src = [==========[\n" + body + "\n]==========]\n"
    "local fn, err = (loadstring or load)(src, '=fx2')\nlocal ok = fn ~= nil\n"
    "if fn then ok, err = pcall(fn) end\n"
    "if not ok and IEX_Log then pcall(IEX_Log, '[FX2] load error ' .. tostring(err)) end\n")
EOF
cp "$SRC/tools/fixtest2/probe/FX2.menu" override/
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
rm -rf "$DOCS/save/"*
cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-FIXTEST2"
cat > "$DOCS/Baldur.lua" <<'EOF'
SetPrivateProfileString('Language','Text','en_US')
SetPrivateProfileString('Program Options','Disable Movies','1')
SetPrivateProfileString('IEX','Skip Intro Movies','1')
SetPrivateProfileString('MOVIES','BLACKPIT','1')
SetPrivateProfileString('MOVIES','INTRO15F','1')
SetPrivateProfileString('MOVIES','LOGO','1')
SetPrivateProfileString('MOVIES','INTRO','1')
SetPrivateProfileString('Game Options','Auto Pause State','0')
EOF
rm -f IEX/fixtest2_status.txt IEX/fixtest2_out.txt IEX.log

status() { cat IEX/fixtest2_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1 IEX_FIX_DEBUG=1
if [ "$FIXES" = off ]; then export IEX_ENGINE_FIXES=0; else unset IEX_ENGINE_FIXES; fi
if [ -n "$OFFLIST" ]; then export IEX_ENGINE_FIXES_OFF="$OFFLIST"; else unset IEX_ENGINE_FIXES_OFF; fi
./iex-launch.sh > game.out 2>&1 &
PID=$!
t0=$(date +%s); win=""; last=0; result=timeout; MEM=""; seen=""
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
        "mem "*)
            case "$seen" in *"|$st|"*) ;; *)
                seen="$seen|$st|"
                MEM="$MEM$st t=$((now - t0))s $(grep -E 'VmRSS|VmData' /proc/$PID/status | tr -s ' \t' ' ' | tr '\n' ' ')
" ;; esac ;;
        DONE*) result=done; break ;;
        "save not found"*|*"load error"*) result="$st"; break ;;
    esac
done
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
{ echo "run $TAG : $result, status '$(status)'"; printf '%s' "$MEM"; cat IEX/fixtest2_out.txt 2>/dev/null; } > "$OUT/$TAG.txt"
cp IEX.log "$OUT/$TAG.IEX.log" 2>/dev/null
echo "$TAG : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$TAG.txt"
