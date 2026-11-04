#!/bin/bash
# Linux (WSL2/WSLg) side of the HD tiles test: run inside WSL.
#   tools/hdtiles/run_linux.sh <build dir> <dir of test files (*.TIS *.PVRZ *.WED *.BMP copied to override), or "none">
#                              [<steps file>]
#   tools/hdtiles/run_linux.sh --stop      closes the game started here (and nothing else)
# Steps file: one step per line, "sleep <s>" or a Lua chunk written to IEX/hd_cmd.lua. After the steps the game is
# closed (HD_KEEP=1 leaves it running for screenshots; close it with --stop). Never more than one game: a running one
# is closed first.
# Private copy ~/games/hd-linux of the Linux BG2EE base with IEX, own engine_name / save folder, no intro, muted
# (SDL_AUDIODRIVER=dummy). Loads "Chapter 1 Start" through the probe's command channel (IEX/hd_cmd.lua) and leaves
# the game running for screenshots; only the game started here is ever closed (next run, or `pkill -f hd-linux`).
set -u
G=$HOME/games/hd-linux
stop_game() {
  # the game and the setsid session it runs in; [G] keeps pkill from matching this script's own command line
  pkill -TERM -f "games/hd-linux/Baldurs[G]ateII" 2>/dev/null
  for i in 1 2 3 4 5; do pgrep -f "games/hd-linux/Baldurs[G]ateII" > /dev/null || return 0; sleep 1; done
  pkill -KILL -f "games/hd-linux/Baldurs[G]ateII" 2>/dev/null; sleep 1
}
if [ "${1:-}" = --stop ]; then stop_game; exit 0; fi
BUILD=$1; HDFILES=$2; STEPS=${3:-}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BASE=/mnt/e/Dev/IEX-data/testgame/bg2ee-linux-2.7.3
SAVEFROM="$HOME/.local/share/Baldur's Gate II - Enhanced Edition/save/000000007-Chapter 1 Start"
NAME="Baldur's Gate II - Enhanced Edition (IEX hd linux)"
DOCS="$HOME/.local/share/$NAME"
stop_game
if [ ! -f "$G/chitin.key" ]; then
  python3 -c "import shutil,sys; shutil.copytree(sys.argv[1], sys.argv[2], symlinks=True)" "$BASE" "$G" || exit 1
fi
cd "$G" || exit 1
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\n' "$NAME" > engine.lua
mkdir -p override_off
for f in M_IEXTST.lua M_SQFPS.lua; do [ -f "override/$f" ] && mv -f "override/$f" override_off/; done
# test files of the previous run (listed in override/hd_test_files.txt) out, this run's in
if [ -f override/hd_test_files.txt ]; then (cd override && xargs -r rm -f < hd_test_files.txt); fi
rm -f override/AR0602.TIS override/A0602*.PVRZ override/hd_test_files.txt
if [ "$HDFILES" != none ]; then
  for f in "$HDFILES"/*.TIS "$HDFILES"/*.PVRZ "$HDFILES"/*.WED "$HDFILES"/*.BMP; do
    [ -f "$f" ] && cp -f "$f" override/ && basename "$f" >> override/hd_test_files.txt
  done
fi
cp -f "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp -f "$REPO"/lua/*.lua IEX/
cp -f "$REPO"/engine/*.iexd IEX/engine/
cp -f "$REPO"/ui/*.menu override/
cp -f "$REPO"/tools/hdtiles/probe/M_HDTEST.lua override/
python3 -I "$REPO/tools/compat/api_list.py" IEX/IEX_API.txt > /dev/null
mkdir -p "$DOCS/save"
rm -rf "$DOCS"/save/*
cp -r "$SAVEFROM" "$DOCS/save/"
cat > "$DOCS/Baldur.lua" <<'EOF'
SetPrivateProfileString('Language','Text','en_US')
SetPrivateProfileString('Program Options','Disable Movies','1')
SetPrivateProfileString('Window','Full Screen','0')
SetPrivateProfileString('Window','w','1280')
SetPrivateProfileString('Window','h','800')
SetPrivateProfileString('Graphics','Use Nearest Neighbour Scaling','0')
EOF
rm -f IEX.log IEX/hd_out.txt
export DISPLAY=:0 SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
LD_PRELOAD=$G/libiex.so setsid "$G/BaldursGateII" > game.out 2>&1 < /dev/null &
sleep 20
echo "HD_Load('Chapter 1')" > IEX/hd_cmd.lua
for i in $(seq 1 40); do
  sleep 2
  echo "local a=EEex_Area_GetVisible() if a then HD_Out('AREA', a.m_resref:get(), HD_State()) end" > IEX/hd_cmd.lua
  grep -q '^AREA' IEX/hd_out.txt 2>/dev/null && break
done
cat IEX/hd_out.txt 2>/dev/null
grep -E "HD tiles|hdTiles" IEX.log
if [ -n "$STEPS" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "sleep "*) sleep "${line#sleep }" ;;
      "") ;;
      *) printf '%s
' "$line" > IEX/hd_cmd.lua ;;
    esac
  done < "$STEPS"
  cat IEX/hd_out.txt 2>/dev/null
  grep -E "HD tiles: (longest|mips of)" IEX.log | tail -4
fi
[ "${HD_KEEP:-0}" = 1 ] || stop_game
