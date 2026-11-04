"""Make an EEex-dependent WeiDU mod accept IEX at install time.

Usage: python -I patch_mod.py <mod folder copy> [--dry-run]

Rewrites, in every .tp2 / .tpa / .tph / .tpp of the folder:
  MOD_IS_INSTALLED ~EEex.tp2~ 0  (any quoting, with or without the EEEX/ folder)
      -> (MOD_IS_INSTALLED <same> OR MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~)
  FILE_EXISTS_IN_GAME ~EEex_<x>.lua~ / FILE_EXISTS ~override/EEex_<x>.lua~
      -> (<same> OR FILE_EXISTS ~IEX/IEX_Main.lua~)   (not the early-EEex files EEex_Brd / EEex_Cra / EEex_Modules)
  REQUIRE_COMPONENT ~EEex.tp2~ ~0~ @msg
      -> REQUIRE_PREDICATE (MOD_IS_INSTALLED ~EEex.tp2~ ~0~ OR MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~) @msg
  FILE_EXISTS(_IN_GAME) ~(override/)M___EEex.lua~ / ~M__EEex.lua~ (EEex's start files)
      -> (<same> OR FILE_EXISTS ~IEX/IEX_Main.lua~)
  FILE_CONTAINS(_EVALUATED) ~EEex_scripts/EEex_X.lua~ / ~override/EEex_X.lua~ ~...EEex_Name...~ (a function test)
      -> (<same> OR FILE_CONTAINS_EVALUATED (~IEX/IEX_API.txt~ ~^EEex_Name$~))   (IEX_API.txt: the EEex names IEX defines)
  FILE_EXISTS ~lua51.dll~ / ~LuaProvider.dll~ (EEex's LuaJIT mode)
      -> (<same> OR FILE_EXISTS ~IEX/IEX_Main.lua~)   (IEX's Lua libraries come with InfinityLoader.ini LuaPatchMode)
  FILE_EXISTS ~EEex.dll~ (EEex's loader library)
      -> (<same> OR FILE_EXISTS ~IEX/IEX_Main.lua~)
Rule numbers: docs/COMPAT_RULES.md.
Only install-time checks change; the mod's game content is untouched. Prints one line per change, so the same
rules can be reviewed and offered to the mod authors (or applied by a mod manager).
"""
import pathlib
import re
import sys

IEX_INSTALLED = 'MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~'
IEX_FILE = 'FILE_EXISTS ~IEX/IEX_Main.lua~'
IEX_API = '~IEX/IEX_API.txt~'

RULES = [
    # MOD_IS_INSTALLED ~EEex.tp2~ (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)  (component found by its label)
    (re.compile(r'MOD_IS_INSTALLED\s+([~"])(?:EEEX/)?EEEX\.TP2\1\s+\(\s*ID_OF_LABEL\s+([~"])(?:EEEX/)?EEEX\.TP2\2'
                r'\s+([~"])B3-EEex-Main\3\s*\)', re.I),
     lambda m: f'({m.group(0)} OR {IEX_INSTALLED})'),
    # MOD_IS_INSTALLED ~EEEX/EEEX.TP2~ ~0~ | "EEex.tp2" 0 | ~EEex.tp2~ ~0~
    (re.compile(r'MOD_IS_INSTALLED\s+([~"])(?:EEEX/)?EEEX\.TP2\1\s+(?:([~"])0\2|0)', re.I),
     lambda m: f'({m.group(0)} OR {IEX_INSTALLED})'),
    # FILE_EXISTS_IN_GAME ~EEex_Actionbar.lua~. Not the files of early EEex versions (EEex_Brd.lua, EEex_Cra.lua):
    # mods that find them go on to COPY_EXISTING / patch them (B_Kits, Proficiencies), and no current extender has
    # them. Not EEex_Modules.lua: mods that test it go on to edit EEex's own module switches, which IEX does not have.
    (re.compile(r'FILE_EXISTS_IN_GAME\s+([~"])EEex_(?!(?:Brd|Cra|Modules)\b)\w+\.lua\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
    # FILE_EXISTS ~override/EEex_Sprite.lua~ (the EEex Lua files live in override). Same exclusions.
    (re.compile(r'FILE_EXISTS\s+([~"])override/EEex_(?!(?:Brd|Cra|Modules)\b)\w+\.lua\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
    # 4. REQUIRE_COMPONENT ~EEex.tp2~ ~0~ @msg (Olvyn's mods, Epic Thieving): same test as a predicate, either extender.
    (re.compile(r'REQUIRE_COMPONENT\s+([~"])((?:EEEX/)?EEEX\.TP2)\1\s+([~"])0\3', re.I),
     lambda m: f'REQUIRE_PREDICATE (MOD_IS_INSTALLED ~{m.group(2)}~ ~0~ OR {IEX_INSTALLED})'),
    # 5. EEex's start file override/M___EEex.lua (v0.10+; BuffBot, BG2 Narrator, the chriz mods, Remote Console), by
    # path or in game.
    (re.compile(r'FILE_EXISTS(?:_IN_GAME)?\s+([~"])(?:override/)?M___EEex\.lua\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
    # 6. The start file of early EEex, M__EEex.lua (B_Kits, Proficiencies). Their EEex_Brd.lua branches stay off.
    (re.compile(r'FILE_EXISTS(?:_IN_GAME)?\s+([~"])(?:override/)?M__EEex\.lua\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
    # 7. A function looked up in EEex's Lua sources (chriz mods, BuffBot): true under IEX when IEX defines that name
    # (IEX/IEX_API.txt, one EEex_ name per line). Other conditions of the same check (DIRECTORY_EXISTS
    # EEex_scripts/extra_pattern_dbs: EEex native pattern files) are left as they are.
    (re.compile(r'FILE_CONTAINS(?:_EVALUATED)?\s*(\()?\s*([~"])(?:EEex_scripts|override)/EEex_[\w-]+\.lua\2\s+'
                r'([~"])[^~"]*?\b(EEex_\w+)\b[^~"]*\3\s*(?(1)\))', re.I),
     lambda m: f'({m.group(0)} OR FILE_CONTAINS_EVALUATED ({IEX_API} ~^{m.group(4)}$~))'),
    # 8. EEex's LuaJIT mode DLLs in the game folder (BuffBot): IEX gives the same Lua libraries (io, os, bit) when
    # InfinityLoader.ini says LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL (IEX.tp2 component 2); mods still check
    # that line themselves.
    (re.compile(r'FILE_EXISTS\s+([~"])(?:lua51|LuaProvider)\.dll\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
    # 9. EEex's loader library in the game folder (BG Pathfinding Redux: "Install EEex first"): IEX is the loader.
    (re.compile(r'FILE_EXISTS\s+([~"])EEex\.dll\1', re.I),
     lambda m: f'({m.group(0)} OR {IEX_FILE})'),
]


def patch_text(text):
    changes = []
    for rx, repl in RULES:
        def sub(m, repl=repl):
            new = repl(m)
            changes.append((m.group(0), new))
            return new
        text = rx.sub(sub, text)
    return text, changes


def main():
    root = pathlib.Path(sys.argv[1])
    dry = '--dry-run' in sys.argv
    total = 0
    for path in sorted(root.rglob('*')):
        if path.suffix.lower() not in ('.tp2', '.tpa', '.tph', '.tpp') or not path.is_file():
            continue
        raw = path.read_bytes()
        text = raw.decode('latin-1')  # byte-preserving
        if IEX_INSTALLED in text or IEX_FILE in text or IEX_API in text:
            continue  # already patched
        new, changes = patch_text(text)
        if not changes:
            continue
        total += len(changes)
        for old, rep in changes:
            print(f'{path.relative_to(root)}: {old}  ->  {rep}')
        if not dry:
            path.write_bytes(new.encode('latin-1'))
    print(f'{total} change(s){" (dry run)" if dry else ""}')


if __name__ == '__main__':
    main()
