#!/bin/bash
# Stack7 probe on the Linux copy (WSL, WSLg). Usage: run.sh <outdir> [build dir] [repo]
# The copy ~/games/bg2ee-stack7 (tools/stack7/linux/make_copy.py of ~/games/bg2ee-full-0.3.0: same mods, installed
# with the WeiDU guards) gets the IEX build, IEX Lua / engine files and the probe; own Documents folder; sound off;
# F11 sent with xdotool (no focus change); the game is killed at the end or after the timeout.
out="$1"; build="${2:-$HOME/iex-build-st7}"; repo="${3:-/mnt/e/Dev/IEX-wt-stack7}"
g="$HOME/games/bg2ee-stack7"
name="Baldur's Gate II - Enhanced Edition (IEX stack7 linux)"
docs="$HOME/.local/share/$name"
save="${IEX_STACK7_SAVE:?set IEX_STACK7_SAVE to the game's Documents folder}"
mkdir -p "$out"
cd "$g" || exit 1
printf 'engine_name = "%s"\nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE\nlang_dir = en_US\n' "$name" > engine.lua
sed -i 's/^LuaVersionExternal=.*/LuaVersionExternal=5.1-LuaJIT/' InfinityLoader.ini
mkdir -p override_off; [ -f override/M_IEXRT.lua ] && mv override/M_IEXRT.lua override_off/
cp "$build/libiex.so" "$g/libiex.so"
mkdir -p IEX/engine
cp "$repo"/lua/*.lua IEX/; cp "$repo"/engine/*.iexd IEX/engine/; cp "$repo"/ui/*.menu override/
cp "$repo"/tools/stack7/probe/M_ST7.lua "$repo"/tools/stack7/probe/ST7.menu override/
rm -rf "$docs/save"; mkdir -p "$docs/save"
cp -r "$save/save/000000099-IEXRT" "$docs/save/"
grep -v -E "Disable Movies|'Language'" "$save/Baldur.lua" > "$docs/Baldur.lua"
printf "SetPrivateProfileString('Program Options','Disable Movies','1')\nSetPrivateProfileString('Language','Text','en_US')\n" >> "$docs/Baldur.lua"
rm -f st7_out.txt st7_status.txt IEX/st7_out.txt IEX/st7_status.txt IEX.log
export IEX_SKIP_INTRO=1 SDL_AUDIODRIVER=dummy
ulimit -f 2000000
./iex-launch.sh > "$out/linux-game.out" 2>&1 &
pid=$!
# only processes whose working directory is this copy (other agents may run games in WSL)
own() { for p in $(pgrep -x BaldursGateII); do [ "$(readlink /proc/$p/cwd)" = "$g" ] && echo $p; done; }
t0=$(date +%s); last=0; result=timeout
while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
  sleep 0.5
  st=$(cat st7_status.txt IEX/st7_status.txt 2>/dev/null | head -1)
  if ! kill -0 $pid 2>/dev/null; then result="exited ($st)"; break; fi
  case "$st" in DONE*) result=done; break;; "save not found"*|"probe load error"*) result="$st"; break;; esac
  now=$(date +%s)
  case "$st" in *"screen ready"*|loading*|"main file"*|opening*)
    if [ $((now - last)) -ge 3 ]; then
      for gp in $(own); do for w in $(xdotool search --pid $gp 2>/dev/null); do xdotool key --window $w F11; done; done
      last=$now
    fi;;
  esac
done
st=$(cat st7_status.txt IEX/st7_status.txt 2>/dev/null | head -1)
for p in $(own); do kill -9 $p; done; sleep 2
cp st7_out.txt "$out/linux-run1.txt" 2>/dev/null || cp IEX/st7_out.txt "$out/linux-run1.txt" 2>/dev/null
cp IEX.log "$out/linux-run1.IEX.log" 2>/dev/null; cp IEX/missing_api.txt "$out/linux-run1.missing_api.txt" 2>/dev/null
echo "linux run: $result, status '$st', $(wc -l < "$out/linux-run1.txt" 2>/dev/null) lines, $(( $(date +%s) - t0 )) s"
