#!/bin/bash
# Event-trigger object test, Linux (run inside WSL, ENGINE_FIXES.md #13): private copy of a Linux game with IEX, the
# test creature and script (make_res.py) and the probe (tools/trigtest/probe), one save.
#   bash tools/trigtest/run_linux.sh on|off [base game] [save folder name]
# on = default fixes, off = IEX_ENGINE_FIXES_OFF=eventTriggerObjects (the engine bug).
# Guards: WeiDU without stdin, timeout; audio off; no startup movies; the game window is moved off screen and only
# gets background key events (xdotool --window); only the game started here is killed. Never saves.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="${1:-on}"
BASE="${2:-$HOME/games/sadonative}"
SAVE="${3:-000000007-Chapter 1 Start}"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-fixes}"
COPY="$HOME/games/trigtest"
OUT=/mnt/e/Dev/IEX-data/trigtest
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX trigtest linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=240
TAG="linux-fix$FIX-$(date +%m%d-%H%M)"
mkdir -p "$OUT"

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
mkdir -p override
( ulimit -f 200000; python3 -I "$SRC/tools/trigtest/make_res.py" "$COPY" "$HOME/bin/weidu" ) || exit 1
# SadoEE's M_ files read Windows code addresses (its build probe) and are not under test here: moved out.
mkdir -p override_off
for f in override/M_SQ*.lua override/M_PS*.lua override/M_SNTEST.lua override/M_STKPRB.lua override/M_FXT.lua; do
    [ -f "$f" ] && mv -f "$f" override_off/
done
# IEX build + runtime files
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh
# probe (body run inside load() + pcall: a load error never stops the game)
{ printf 'local src = [==========[\n'; cat "$SRC/tools/trigtest/probe/t13_body.lua"
  printf '\n]==========]\nlocal fn, err = (loadstring or load)(src, "=t13")\nlocal ok = fn ~= nil\n'
  printf 'if fn then ok, err = pcall(fn) end\n'
  printf 'if not ok and IEX_Log then pcall(IEX_Log, "[T13] load error " .. tostring(err)) end\n'; } > override/M_T13.lua
cp "$SRC/tools/trigtest/probe/T13.menu" override/
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
rm -rf "$DOCS/save/"*
cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-TRIGTEST"
{ grep -v "Disable Movies\|Auto Pause State" "$DOCSRC/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua"
rm -f IEX/trig_status.txt IEX/trig_out.txt IEX.log

status() { cat IEX/trig_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1 IEX_FIX_DEBUG=1
unset IEX_ENGINE_FIXES
if [ "$FIX" = off ]; then export IEX_ENGINE_FIXES_OFF=eventTriggerObjects; else unset IEX_ENGINE_FIXES_OFF; fi
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
cp IEX/trig_out.txt "$OUT/$TAG.txt" 2>/dev/null
cp IEX.log "$OUT/$TAG.IEX.log" 2>/dev/null
echo "$TAG : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$TAG.txt"
