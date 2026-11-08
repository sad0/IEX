#!/bin/bash
# Kit-limit test, Linux (run inside WSL; docs/KIT_LIMIT.md). Game: a copy of the Windows test game
# E:/Dev/IEX-data/testgame/kits-bg2ee (vanilla BG2EE + IEX + KitLimitTest) on the WSL disk with the Linux 2.7.3
# executable; probe tools/kitlimit/probe as in run.ps1.
#   bash tools/kitlimit/run_linux.sh <new|reload> <kit> <control kit> <on|off> <tag>
# Guards: audio off, no startup movies, window off screen, background key events only (xdotool --window), only the
# game started here is killed.
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-new}"; KIT="${2:-KLT260}"; CONTROL="${3:-KLT208}"; FEATURE="${4:-on}"; TAG="${5:-linux}"
BASE=/mnt/e/Dev/IEX-data/testgame/kits-bg2ee
EXE=/mnt/e/Dev/IEX-data/linux-2.7.3/bg2ee
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-kits}"
COPY="$HOME/games/kits"
OUT=/mnt/e/Dev/IEX-data/kitlimit
NAME="Baldur's Gate II - Enhanced Edition (IEX kits linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=400
mkdir -p "$OUT"

if [ ! -f "$COPY/chitin.key" ]; then
    mkdir -p "$COPY"
    for d in chitin.key data lang movies music override scripts IEX; do cp -r "$BASE/$d" "$COPY/"; done
    cp "$EXE/BaldursGateII" "$EXE/libsteam_api.so" "$COPY/"
fi
cd "$COPY" || exit 1
cp "$BUILD/libiex.so" .
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh BaldursGateII
{ printf "KLT_MODE = '%s'\nKLT_KIT = '%s'\nKLT_CONTROL = '%s'\n" "$MODE" "$KIT" "$CONTROL"
  printf 'local src = [==========[\n'; cat "$SRC/tools/kitlimit/probe/klt_body.lua"
  printf '\n]==========]\nlocal fn, err = (loadstring or load)(src, "=klt")\nlocal ok = fn ~= nil\n'
  printf 'if fn then ok, err = pcall(fn) end\n'
  printf 'if not ok and IEX_Log then pcall(IEX_Log, "[KLT] load error " .. tostring(err)) end\n'; } > override/M_KLT.lua
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
[ "$MODE" = new ] && rm -rf "$DOCS/save/"*
{ grep -v "Disable Movies\|Auto Pause State\|'Language'\|Skip Intro" "$DOCS/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Language','Text','en_US')"
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('IEX','Skip Intro Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua.new"
mv "$DOCS/Baldur.lua.new" "$DOCS/Baldur.lua"
rm -f IEX/kitlimit_status.txt IEX/kitlimit_out.txt IEX.log

status() { cat IEX/kitlimit_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
if [ "$FEATURE" = off ]; then export IEX_KIT_LIMIT=0; else unset IEX_KIT_LIMIT; fi
if [ -n "${GDB:-}" ]; then
    # crash diagnosis: the game under gdb, backtrace on a fault (game.out)
    gdb -q -batch -ex 'handle SIGPIPE nostop noprint' -ex "set environment LD_PRELOAD=$COPY/libiex.so"         -ex run -ex bt -ex 'info registers rip' --args ./BaldursGateII > game.out 2>&1 &
    sleep 2; PID=$(pgrep -n -x BaldursGateII || echo $!)
else
    ./iex-launch.sh > game.out 2>&1 &
    PID=$!
fi
t0=$(date +%s); win=""; last=0; since=0; result=timeout
while [ $(( $(date +%s) - t0 )) -lt $TIMEOUT ]; do
    sleep 0.3
    kill -0 $PID 2>/dev/null || { result="exited ($(status))"; break; }
    if [ -z "$win" ] || [ $(( $(date +%s) % 5 )) -eq 0 ]; then
        w=$(xdotool search --pid $PID 2>/dev/null | tail -1)
        if [ -n "$w" ] && [ "$w" != "$win" ]; then win=$w; xdotool windowmove "$win" -6000 -6000 2>/dev/null; fi
    fi
    st=$(status)
    now=$(date +%s)
    case "$st" in
        *"- keys")
            [ $since -eq 0 ] && since=$now
            if [ $((now - since)) -ge 5 ] && [ $((now - last)) -ge 1 ] && [ -n "$win" ]; then
                xdotool key --window "$win" F11; last=$now
            fi ;;
        DONE*) result=done; break ;;
        "save not found"*|*"load error"*|"chargen stuck"*) result="$st"; break ;;
        *) since=0 ;;
    esac
done
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
cp IEX/kitlimit_out.txt "$OUT/$TAG.txt" 2>/dev/null
cp IEX.log "$OUT/$TAG.IEX.log" 2>/dev/null
cp game.out "$OUT/$TAG.game.out" 2>/dev/null
echo "$TAG : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$TAG.txt"
