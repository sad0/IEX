# Contributing

Bug reports and "mod X doesn't work" reports are the most useful contribution: open an issue with `IEX.log`,
`IEX/missing_api.txt`, `WeiDU.log` and the steps to reproduce.

Code contributions are welcome under GPL-3.0. Before opening a pull request, please confirm in its description that:

- you have not read, copied or adapted code from EEex, InfinityLoader, EEex-Torment or InfinityEngine-Enhancer, and
  have not disassembled code they generate at run time ([docs/CLEAN_ROOM.md](docs/CLEAN_ROOM.md));
- engine knowledge in your change comes from the game binaries, the IESDP or other public documentation;
- no game files (BIF, 2DA, BAM, executables...) or other authors' mod files are included.

Match the style of the surrounding code (C++17, comments in English, one feature per file under `src/core/`).
