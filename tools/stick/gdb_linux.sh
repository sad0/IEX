#!/bin/bash
# Runs the Linux test copy under gdb once (crash backtrace into ~/games/stick/gdb.out).
cd "$HOME/games/stick" || exit 1
export SDL_AUDIODRIVER=dummy IEX_SKIP_INTRO=1
timeout 120 gdb -batch -ex "set environment LD_PRELOAD=$PWD/libiex.so" -ex run -ex bt -ex "info registers" ./BaldursGateII > gdb.out 2>&1
grep -B2 -A30 "SIGSEGV" gdb.out | head -60
