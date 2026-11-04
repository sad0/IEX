#!/bin/sh
# Starts the native Linux game with IEX preloaded (libiex.so next to this script).
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here" || exit 1
export LD_PRELOAD="$here/libiex.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec ./BaldursGateII "$@"
