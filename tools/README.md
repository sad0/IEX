# tools

Generators (`engine/`, `match/`, `elfsyms/`, `compat/`, `hdtiles/`), packaging (`package.sh`) and the maintainer's
test harnesses (`difftest/`, `fixtest/`, `trigtest/`, `pathtest/`, `speedtest/`, `stack7/`, `atkm/`, ...).

The test harnesses drive private copies of the game and expect the maintainer's folder layout (paths such as
`E:/Dev/IEX-data/...` or `~/games/...`). Point them at your own game copies before use; never run them on a game you
play.
