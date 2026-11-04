#!/bin/sh
# Run one or more IEX GhidraScripts headless, read-only, against the analyzed Linux 2.7.3 project.
# Usage: tools/ghidra/run.sh <Script.java> [args...] [-- <Script2.java> [args...]]
# Env overrides: GHIDRA_HOME, GPROJ_DIR, GPROJ_NAME, GPROGRAM
# Note: analyzeHeadless.bat breaks on paths containing parentheses; keep all paths paren-free.
GHIDRA_HOME="${GHIDRA_HOME:?set GHIDRA_HOME to your Ghidra install}"
GPROJ_DIR="${GPROJ_DIR:?set GPROJ_DIR to a Ghidra project folder}"
GPROJ_NAME="${GPROJ_NAME:-IEX_linux273}"
GPROGRAM="${GPROGRAM:-BaldursGateII}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"

post=""
first=1
for a in "$@"; do
  if [ "$a" = "--" ]; then first=1; continue; fi
  if [ $first = 1 ]; then post="$post -postScript $a"; first=0; else post="$post $a"; fi
done

exec cmd //c "$(cygpath -w "$GHIDRA_HOME/support/analyzeHeadless.bat") $(cygpath -w "$GPROJ_DIR") $GPROJ_NAME -process $GPROGRAM -noanalysis -readOnly -scriptPath $(cygpath -w "$SCRIPT_DIR") $post"
