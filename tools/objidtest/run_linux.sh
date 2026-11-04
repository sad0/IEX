#!/bin/bash
# Object id test, Linux (run inside WSL): private copy of a Linux game with IEX and the probe
# (tools/objidtest/probe/p10_body.lua), one save. Engine fixes on, or off (IEX_ENGINE_FIXES=0).
#   bash tools/objidtest/run_linux.sh on|off [base game] [save folder name]
# Guards: WeiDU without stdin, file size limit, timeout; audio off; no startup movies; the game window is moved off
# screen and only gets background key events (xdotool --window); only the game started here is killed. Never saves.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
P10BODY="$SRC/tools/objidtest/probe/p10_body.lua"
FIXES="${1:-on}"
BASE="${2:-$HOME/games/sadonative}"
SAVE="${3:-000000007-Chapter 1 Start}"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build}"
COPY="$HOME/games/p10linux"
OUT=/mnt/e/Dev/IEX-data/p10test
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX p10 linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=300
TAG="linux-p10-$FIXES"

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
mkdir -p override
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
python3 - "$P10BODY" override/M_P10.lua <<'EOF'
import sys
body = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write("local src = [==========[\n" + body + "\n]==========]\n"
    "local fn, err = (loadstring or load)(src, '=p10')\nlocal ok = fn ~= nil\n"
    "if fn then ok, err = pcall(fn) end\n"
    "if not ok and IEX_Log then pcall(IEX_Log, '[P10] load error ' .. tostring(err)) end\n")
EOF
printf 'menu
{
	name "P10_TICK"
	ignoreesc
	label
	{
		name "P10LABEL"
		area 0 0 0 0
		enabled "P10_Tick()"
	}
}
' > override/P10.menu
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
rm -rf "$DOCS/save/"*
cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-P10TEST"
{ grep -v "Disable Movies\|Auto Pause State" "$DOCSRC/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua"
rm -f IEX/p10_status.txt IEX/p10_out.txt IEX.log

status() { cat IEX/p10_status.txt 2>/dev/null | tail -1; }
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
cp IEX/p10_out.txt "$OUT/$TAG.txt" 2>/dev/null
cp IEX.log "$OUT/$TAG.IEX.log" 2>/dev/null
echo "$TAG : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$TAG.txt"
