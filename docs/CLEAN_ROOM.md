# Clean-room rule

IEX is an independent engine extender. **No line of EEex, InfinityLoader or EEex-Torment** (sad0/EEex-Torment,
the PST:EE port of Bubb13's code) may end up in IEX. These projects have no license: their code is all rights
reserved.

## Allowed

- Reproducing the **API surface** that mods use: Lua function names (`EEex_*`), their signatures and their
  documented or observable behavior, listener names, opcode numbers, IDS entries, INI keys mods write.
- Public user documentation (e.g. eeex-docs.readthedocs.io), read for behavior only and described in our own words.
- Mods' own code (e.g. SadoEE) to see how the API is called.
- Our own reverse engineering of the game binaries (Linux symbols, Windows matching, decompilation),
  public file-format documentation (IESDP), and third-party libraries under compatible licenses.

## Not allowed

- Copying or adapting implementation from those projects: code, comments, pattern database entries,
  generated bindings or headers, struct dumps, hook lists, file or module layouts.
- Opening their sources while working on IEX (including local clones such as `EEex-PSTEE/ref/`) to look up
  how something is done. Engine knowledge comes from the game binaries.
- Disassembling or dumping code EEex generates or installs at run time (its stubs, hooks, JIT output, patched
  engine bytes) to learn its internals. Running EEex is allowed only to observe behaviour: return values, Lua
  results, game effects, screenshots, files it writes (rule added 2026-10-29, after the asm/JIT work).

## History

The phase 1 study (2026-10-27, not part of this repository) summarised EEex's architecture from its sources to scope the
project. That summary was reduced to a high-level description, and the one technique IEX had taken from it
(the launcher's start-address redirection) was replaced by an independent method (early APC injection).
No code was ever copied. Audit: 2026-10-28.

2026-10-28 (opcodes work): the EEex-compatible IDS entries in IEX.tp2 were read from the IDS files of a game where
EEex is installed. Kept: action / trigger / object numbers and signatures (EEex_LuaAction 472, EEex_LuaTrigger
0x410E, EEex_LuaObject 115...), because they are the interface compiled mod scripts depend on, like function names.
Removed: X-MATOBJ.IDS (EEex's own flag list for EEex_MatchObjectEx, not used by any tested mod and not found in
public docs) and the two EEex_MatchObjectEx entries that reference it. Rule going forward: data files are written
from mods' usage and public docs only, never copied from an EEex install.

2026-10-29: an early assembly / JIT API was checked against code EEex generates at run time. That work broke the
rule above (which was written because of it) and was removed in 0.3.0; IEX has had no assembly API since, and none
of that code is in this repository, whose history starts at 0.4.0.
