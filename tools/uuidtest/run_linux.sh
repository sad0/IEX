#!/bin/bash
# Per-creature UUID test, Linux (run inside WSL, docs/UUID.md): private copy of a Linux game with IEX and the probe
# (tools/uuidtest/probe), one save.
#   bash tools/uuidtest/run_linux.sh first|reload [save name filter] [extra lua file] [tag]
# Mode first loads "Chapter 1 Start" (copied as 000000099-UUIDTEST), spawns, clones, SaveGame(9); mode reload loads
# the save whose name contains the filter (default Quick-Save). steam_appid.txt is disabled in the copy; audio off;
# no startup movies; the game window is moved off screen and only gets background key events (xdotool --window);
# only the game started here is killed. UUID_QUIT=1: after the run the probe quits to the start screen, then shuts
# the game down normally (result "exited (DONE quit: shutting down), exit code N").
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-first}"
FILTER="${2:-}"
EXTRA="${3:-}"
[ -n "$EXTRA" ] && EXTRA="$(cd "$(dirname "$EXTRA")" && pwd)/$(basename "$EXTRA")"
TAG="${4:-}"
BASE="${UUID_LINUX_BASE:-$HOME/games/sadonative}"
SAVE="000000007-Chapter 1 Start"
BUILD="${IEX_LINUX_BUILD:-$HOME/iex-build-uuid}"
COPY="$HOME/games/uuidtest"
OUT=/mnt/e/Dev/IEX-data/uuidtest
DOCSRC="$HOME/.local/share/Baldur's Gate II - Enhanced Edition"
NAME="Baldur's Gate II - Enhanced Edition (IEX uuidtest linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=240
STAMP="linux-$MODE$TAG-$(date +%m%d-%H%M)"
mkdir -p "$OUT"

[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
[ -f steam_appid.txt ] && mv -f steam_appid.txt steam_appid.txt.disabled
mkdir -p override override_off
# SadoEE's M_ files read Windows code addresses and other probes are not under test here: moved out.
for f in override/M_SQ*.lua override/M_PS*.lua override/M_SNTEST.lua override/M_STKPRB.lua override/M_FXT.lua override/M_T13.lua; do
    [ -f "$f" ] && mv -f "$f" override_off/
done
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
cp "$SRC/tools/linux/iex-launch.sh" . && chmod +x iex-launch.sh
# probe (body run inside load() + pcall: a load error never stops the game)
if [ "$MODE" = first ]; then LOADNAME=UUIDTEST; else LOADNAME="${FILTER:-Quick-Save}"; fi
{ printf 'local src = [==========[\n'
  QUITCFG=""; [ -n "${UUID_QUIT:-}" ] && QUITCFG=" UUID_QUIT = true"
  sed "s/-- UUID_CONFIG/UUID_MODE = '$MODE' UUID_SAVE = '$LOADNAME' UUID_SLOT = 9$QUITCFG/" "$SRC/tools/uuidtest/probe/uuid_body.lua"
  [ -n "$EXTRA" ] && { printf '\n'; cat "$EXTRA"; }
  printf '\n]==========]\nlocal fn, err = (loadstring or load)(src, "=uuidt")\nlocal ok = fn ~= nil\n'
  printf 'if fn then ok, err = pcall(fn) end\n'
  printf 'if not ok and IEX_Log then pcall(IEX_Log, "[UUIDT] load error " .. tostring(err)) end\n'; } > override/M_UUIDT.lua
printf 'menu\n{\n\tname "UUIDT_TICK"\n\tignoreesc\n\tlabel\n\t{\n\t\tname "UUIDTLABEL"\n\t\tarea 0 0 0 0\n\t\tenabled "UUIDT_Tick()"\n\t}\n}\n' > override/UUIDT.menu
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p "$DOCS/save"
if [ "$MODE" = first ]; then
    rm -rf "$DOCS/save/"*
    cp -r "$DOCSRC/save/$SAVE" "$DOCS/save/000000099-UUIDTEST"
fi
{ grep -v "Disable Movies\|Auto Pause State" "$DOCSRC/Baldur.lua" 2>/dev/null
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('Game Options','Auto Pause State','0')"; } > "$DOCS/Baldur.lua"
rm -f IEX/uuid_status.txt IEX/uuid_out.txt IEX.log

status() { cat IEX/uuid_status.txt 2>/dev/null | tail -1; }
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
./iex-launch.sh > game.out 2>&1 &
PID=$!
t0=$(date +%s); win=""; last=0; result=timeout
while [ $(( $(date +%s) - t0 )) -lt $TIMEOUT ]; do
    sleep 0.5
    kill -0 $PID 2>/dev/null || { result="exited ($(status))"; wait $PID; result="$result, exit code $?"; break; }
    if [ -z "$win" ]; then
        win=$(xdotool search --pid $PID 2>/dev/null | tail -1)
        [ -n "$win" ] && xdotool windowmove "$win" -6000 -6000 2>/dev/null
    fi
    st=$(status)
    now=$(date +%s)
    case "$st" in
        *"screen ready"*|loading*|"main file loaded"|"opening load screen")
            if [ $((now - last)) -ge 3 ] && [ -n "$win" ]; then xdotool key --window "$win" F11; last=$now; fi ;;
        "DONE quit: shutting down"*) ;;
        "DONE quit"*)
            if [ $((now - last)) -ge 3 ] && [ -n "$win" ]; then xdotool key --window "$win" F11; last=$now; fi ;;
        DONE*) [ -n "${UUID_QUIT:-}" ] || { result=done; break; } ;;
        "save not found"*|*"load error"*) result="$st"; break ;;
    esac
done
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
cp IEX/uuid_out.txt "$OUT/$STAMP.txt" 2>/dev/null
cp IEX.log "$OUT/$STAMP.IEX.log" 2>/dev/null
grep -l '\.cloud:' IEX.log game.out 2>/dev/null && echo "WARNING: .cloud: lines"
echo "$STAMP : $result, status '$(status)', $(( $(date +%s) - t0 )) s -> $OUT/$STAMP.txt"
