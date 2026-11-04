#!/bin/bash
# Linux (WSL2/WSLg) side of the speed test: run inside WSL.
#   tools/speedtest/run_linux.sh <label> <outdir (Linux path)> <phases> [build dir] ["Section|Key|Value;..."]
# Private copy ~/games/speedtest of the Linux BG2EE base with IEX, own engine_name / save folder, IEX_SKIP_INTRO +
# 'Disable Movies', muted (SDL_AUDIODRIVER=dummy), window moved off screen, F11 sent in the background (xdotool).
# Only the game started here is ever closed.
set -u
LABEL=$1; OUT=$2; PHASES=$3; BUILD=${4:-$HOME/iex-build-speed}; INI=${5:-}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BASE=/mnt/e/Dev/IEX-data/testgame/bg2ee-linux-2.7.3
SAVEFROM="$HOME/.local/share/Baldur's Gate II - Enhanced Edition/save/000000007-Chapter 1 Start"
G=$HOME/games/speedtest
NAME="Baldur's Gate II - Enhanced Edition (IEX speedtest linux)"
DOCS="$HOME/.local/share/$NAME"
TIMEOUT=300
mkdir -p "$OUT"

if [ ! -f "$G/chitin.key" ]; then
  python3 -c "import shutil,sys; shutil.copytree(sys.argv[1], sys.argv[2], symlinks=True)" "$BASE" "$G" || exit 1
fi
cd "$G" || exit 1
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p override_off
for f in M_IEXTST.lua; do [ -f "override/$f" ] && mv -f "override/$f" override_off/; done
cp -f "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp -f "$REPO"/lua/*.lua IEX/
cp -f "$REPO"/engine/*.iexd IEX/engine/
cp -f "$REPO"/ui/*.menu override/
python3 -I "$REPO/tools/compat/api_list.py" IEX/IEX_API.txt > /dev/null
python3 -I "$REPO/tools/speedtest/install_probe.py" override

mkdir -p "$DOCS/save"
rm -rf "$DOCS"/save/*
cp -r "$SAVEFROM" "$DOCS/save/000000097-SPEEDTEST"
{
  [ -f "$HOME/.local/share/Baldur's Gate II - Enhanced Edition/Baldur.lua" ] &&
    grep -v "^SetPrivateProfileString('\(SpeedTest\|PathTest\)'" "$HOME/.local/share/Baldur's Gate II - Enhanced Edition/Baldur.lua" |
    grep -v "^SetPrivateProfileString('EEex','\(Uncap\|VSync\)" | grep -v "^SetPrivateProfileString('IEX','\(Frame\|Keep\)"
  echo "SetPrivateProfileString('Program Options','Disable Movies','1')"
  echo "SetPrivateProfileString('SpeedTest','Phases','$PHASES')"
  IFS=';'; for e in $INI; do IFS='|' read -r s k v <<< "$e"; echo "SetPrivateProfileString('$s','$k','$v')"; done; unset IFS
} > "$DOCS/Baldur.lua.new"
mv -f "$DOCS/Baldur.lua.new" "$DOCS/Baldur.lua"

rm -f speedtest_out.txt speedtest_status.txt IEX/speedtest_out.txt IEX/speedtest_status.txt IEX.log
pkill -f "$G/BaldursGateII" 2>/dev/null; sleep 1
export DISPLAY=:0 SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
T0=$(date +%s)
LD_PRELOAD=$G/libiex.so setsid "$G/BaldursGateII" > game.out 2>&1 < /dev/null &
PID=$!
W=
status() { cat speedtest_status.txt IEX/speedtest_status.txt 2>/dev/null | tail -1; }
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
for f in speedtest_out.txt IEX/speedtest_out.txt; do [ -f "$f" ] && cp -f "$f" "$OUT/$LABEL.txt"; done
cp -f IEX.log "$OUT/$LABEL.IEX.log" 2>/dev/null
echo "linux $LABEL: $RESULT, status '$ST', $(( $(date +%s) - T0 )) s"
cat "$OUT/$LABEL.txt" 2>/dev/null
