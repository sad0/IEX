#!/bin/bash
# SadoEE native bridge check, Linux (run inside WSL): a private copy of a Linux game with SadoEE installed, the
# current IEX build and Lua, started to the main menu with no save loaded; prints the SadoEE bridge lines of
# IEX.log (one per component: "native IEX hook" or the reason it is not available) and the hook-point states.
#   bash tools/sadonative/run_linux.sh [base game with SadoEE] [build dir]
# Guards: audio off (SDL_AUDIODRIVER=dummy), no startup movies (IEX_SKIP_INTRO=1 + 'Disable Movies'), the window is
# moved off screen, only the game started here is killed. Nothing is saved.
set -u
SRC="${IEX_SRC:-$(cd "$(dirname "$0")/../.." && pwd)}"   # IEX tree whose lua/ and engine/ are used
BASE="${1:-$HOME/games/sadonative}"
BUILD="${2:-${IEX_LINUX_BUILD:-$HOME/iex-build-hookpts}}"
TAG="${IEX_TEST_TAG:-hp}"
COPY="$HOME/games/sadonative-$TAG"
OUT=/mnt/e/Dev/IEX-data/sadonative
WAIT="${IEX_WAIT:-45}"
mkdir -p "$OUT"
[ -f "$COPY/chitin.key" ] || python3 -I "$SRC/tools/difftest/make_copy.py" "$BASE" "$COPY" || exit 1
cd "$COPY" || exit 1
cp "$BUILD/libiex.so" .
mkdir -p IEX/engine
cp "$SRC"/lua/*.lua IEX/ && cp "$SRC"/engine/*.iexd IEX/engine/ && cp "$SRC"/ui/*.menu override/
rm -f override/M_SNTEST.lua IEX/cmd.lua
# Hook-point state dump once the game state is initialized (the bridges run then).
cat > override/M_HPDUMP.lua <<'EOF'
local function dump()
	local ok, err = pcall(function()
		for name, p in pairs(IEX_NativeHook_Points()) do
			if p.installed or p.active then
				IEX_Log(string.format('HPDUMP %s installed=%s active=%s sites=%d', name, tostring(p.installed),
					tostring(p.active), p.sites or 0))
			end
		end
		for _, f in ipairs({ 'sadoAmmo', 'sadoAttackMove', 'sadoKeepGear', 'sadoRespec', 'sadoCamp', 'sadoStash',
				'sadoChests', 'sadoContainers', 'sadoFootprint', 'sadoModes', 'sadoCampMerchant' }) do
			IEX_Log('HPDUMP feature ' .. f .. '=' .. tostring(IEX_Features[f]))
		end
		IEX_Log('HPDUMP done')
	end)
	if not ok then IEX_Log('HPDUMP error ' .. tostring(err)) end
end
if EEex_GameState_AddInitializedListener then EEex_GameState_AddInitializedListener(dump) end
EOF
for p in $(pgrep BaldursGateII); do [ "$(readlink /proc/$p/cwd)" = "$COPY" ] && kill "$p"; done
export DISPLAY=:0 SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
rm -f IEX.log
LD_PRELOAD=$COPY/libiex.so setsid ./BaldursGateII > game.out 2>&1 < /dev/null &
PID=$!
for i in $(seq 1 40); do
	W=$(xdotool search --pid $PID 2>/dev/null | tail -1)
	[ -n "$W" ] && break
	sleep 0.5
done
[ -n "${W:-}" ] && xdotool windowmove "$W" 3000 3000 2>/dev/null
for i in $(seq 1 "$WAIT"); do grep -q 'HPDUMP done' IEX.log 2>/dev/null && break; sleep 1; done
kill "$PID" 2>/dev/null; sleep 1; kill -9 "$PID" 2>/dev/null
stamp=$(date +%m%d-%H%M)
cp -f IEX.log "$OUT/linux-$TAG-$stamp.IEX.log"
grep -E 'SadoEE|HPDUMP|\[hooks\]|Native hook' IEX.log | sed 's/^\[[0-9:]*\] //'
