#!/bin/bash
# Linux (WSL2/WSLg) side of the pathfinding test: run inside WSL.
#   tools/pathtest/run_linux.sh <side: vanilla|iex> <outdir (Linux path)> [stress ms] [build dir] [refresh]
# Private copy ~/games/pathtest-path of the Linux BG2EE base (IEX + BG Pathfinding Redux installed with WeiDU and
# tools/compat/patch_mod.py), its own engine_name / save folder, IEX_SKIP_INTRO + 'Disable Movies', muted
# (SDL_AUDIODRIVER=dummy), window moved off screen, F11 sent to the game window in the background (xdotool).
# Only the game started here is ever closed.
set -u
SIDE=$1; OUT=$2; STRESS=${3:-120000}; BUILD=${4:-$HOME/iex-build-path}; REFRESH=${5:-}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BASE=/mnt/e/Dev/IEX-data/testgame/bg2ee-linux-2.7.3
MOD=/mnt/e/Dev/IEX-data/mods/pathfinding-redux/src/zach-hopkins-bg-pathfinding-redux-35cc0a9/bg-redux-movement
SAVEFROM="$HOME/.local/share/Baldur's Gate II - Enhanced Edition/save/000000007-Chapter 1 Start"
TAG=${IEX_TEST_TAG:-path}   # private copy / docs folder name (parallel test runs)
G=$HOME/games/pathtest-$TAG
NAME="Baldur's Gate II - Enhanced Edition (IEX pathtest $TAG linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=$((300 + STRESS / 1000))
mkdir -p "$OUT"

if [ -n "$REFRESH" ] || [ ! -f "$G/chitin.key" ]; then
  rm -rf "$G"
  python3 -c "import shutil,sys; shutil.copytree(sys.argv[1], sys.argv[2], symlinks=True)" "$BASE" "$G" || exit 1
fi
cd "$G" || exit 1
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p override_off
for f in M_IEXTST.lua M_SQFPS.lua; do [ -f "override/$f" ] && mv -f "override/$f" override_off/; done
cp -f "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp -f "$REPO"/lua/*.lua IEX/
cp -f "$REPO"/engine/*.iexd IEX/engine/
cp -f "$REPO"/ui/*.menu override/
python3 -I "$REPO/tools/compat/api_list.py" IEX/IEX_API.txt > /dev/null
# BG Pathfinding Redux, once (WeiDU guards: weidu.conf, language 0, no pause / auto-update, stdin /dev/null,
# 64 MB file size limit, 10 min timeout).
if [ ! -f override/M_BGREDX.lua ]; then
  rm -rf bg-redux-movement
  cp -r "$MOD" bg-redux-movement
  python3 -I "$REPO/tools/compat/patch_mod.py" bg-redux-movement
  echo 'lang_dir = en_us' > weidu.conf
  ( ulimit -f 131072; timeout 600 "$HOME/bin/weidu" --language 0 --force-install 0 --no-exit-pause --noautoupdate \
      --log pathtest_weidu.debug bg-redux-movement/bg-redux-movement.tp2 < /dev/null > pathtest_weidu.log 2>&1 )
  [ -f override/M_BGREDX.lua ] || { tail -20 pathtest_weidu.log; echo "mod install failed"; exit 1; }
  echo "  BG Pathfinding Redux installed in $G"
fi
python3 -I "$REPO/tools/pathtest/install_probe.py" override

# Documents: the save and Baldur.lua (no movies, probe settings).
mkdir -p "$DOCS/save"
rm -rf "$DOCS"/save/*
cp -r "$SAVEFROM" "$DOCS/save/000000098-PATHTEST"
{
  [ -f "$HOME/.local/share/Baldur's Gate II - Enhanced Edition/Baldur.lua" ] &&
    grep -v "^SetPrivateProfileString('PathTest'" "$HOME/.local/share/Baldur's Gate II - Enhanced Edition/Baldur.lua"
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('PathTest','StressMs','$STRESS')"
} > "$DOCS/Baldur.lua.new"
mv -f "$DOCS/Baldur.lua.new" "$DOCS/Baldur.lua"

rm -f pathtest_out.txt pathtest_status.txt IEX/pathtest_out.txt IEX/pathtest_status.txt IEX.log
pkill -f "$G/BaldursGateII" 2>/dev/null; sleep 1
export DISPLAY=:0 SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
if [ "$SIDE" = vanilla ]; then export IEX_PATHFINDING=0; else export IEX_PATHFINDING=1; fi
T0=$(date +%s)
LD_PRELOAD=$G/libiex.so setsid "$G/BaldursGateII" > game.out 2>&1 < /dev/null &
PID=$!
W=
status() { cat pathtest_status.txt IEX/pathtest_status.txt 2>/dev/null | tail -1; }
RESULT=timeout; LASTKEY=0
while [ $(( $(date +%s) - T0 )) -lt $TIMEOUT ]; do
  sleep 0.5
  if ! kill -0 $PID 2>/dev/null; then RESULT="exited ($(status))"; break; fi
  if [ -z "$W" ]; then
    W=$(xdotool search --pid $PID 2>/dev/null | tail -1)
    [ -n "$W" ] && xdotool windowmove "$W" 3000 3000 2>/dev/null
  fi
  ST=$(status)
  case "$ST" in
    *"screen ready"*|loading*)
      NOW=$(date +%s)
      if [ -n "$W" ] && [ $((NOW - LASTKEY)) -ge 3 ]; then xdotool key --window "$W" F11 2>/dev/null; LASTKEY=$NOW; fi ;;
    DONE*) RESULT=done; break ;;
    "save not found"*|"probe load error"*|"tick error"*) RESULT=$ST; break ;;
  esac
done
ST=$(status)
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
for f in pathtest_out.txt IEX/pathtest_out.txt; do [ -f "$f" ] && cp -f "$f" "$OUT/linux-$SIDE.txt"; done
cp -f IEX.log "$OUT/linux-$SIDE.IEX.log" 2>/dev/null
cp -f game.out "$OUT/linux-$SIDE.game.out" 2>/dev/null
echo "linux $SIDE: $RESULT, status '$ST', $(wc -l < "$OUT/linux-$SIDE.txt" 2>/dev/null || echo 0) lines, $(( $(date +%s) - T0 )) s"
