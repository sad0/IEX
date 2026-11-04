"""Static scan of mod source trees: what each mod needs from EEex, compared with what IEX provides.

Usage: python -I scan_mods.py <out.md> <mod folder> [<mod folder> ...]
       python -I scan_mods.py --api-json <out.json>   (what IEX provides, for mod managers)

For every mod folder (any layout: .lua, .menu, .tp2/.tpa/.tph, .baf/.d), reports:
  - EEex_* names used (functions, tables, listeners) and which ones IEX does not define yet
  - methods called on engine objects (obj:method(...)) that look engine-bound (lowercase camelCase)
  - engine fields read (.m_xxx) and whether the IEX type descriptions know the field name
  - EEex opcodes 400-409 used in WeiDU code (opcode = 40x / match_opcode = 40x)
  - "hard" usage that a Lua-API reimplementation cannot cover: x64 asm / hooks / labels / raw writes
Names are matched textually, so the report is a guide, not a proof (dynamic names are missed).
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LUA_EXT = {'.lua', '.menu'}
WEIDU_EXT = {'.tp2', '.tpa', '.tph', '.tpp', '.baf', '.d'}

# A match ending with '_' is the prefix of a name built at runtime ("EEex_Menu_" .. x): not a name, skipped.
# rules_version 5: a match followed by a file extension or a path separator is a file or folder name (EEex_Actionbar.lua,
# EEex_scripts/...), probed by tp2 code: not an API name (mod managers patch those probes, see patch_mod.py).
RX_EEEX = re.compile(r'\b(EEex_[A-Za-z0-9_]*[A-Za-z0-9])\b(?!\.(?i:lua|menu|dll|db|exe|ids|2da|tp2)\b|[/\\])')
RX_METHOD = re.compile(r'[\w\]\)]\s*:\s*([a-z][A-Za-z0-9]+)\s*\(')
RX_FIELD = re.compile(r'\.(m_[A-Za-z0-9_]+)')
RX_OPCODE = re.compile(r'\b(?:opcode|match_opcode|effectID)\s*=\s*(40\d)\b', re.I)
HARD = re.compile(r'\bEEex_(?:JIT\w*|Hook\w*|Label|WriteU?\d+|Write(?:Pointer|Ptr|String|Byte|Word|DWord)\w*|'
                  r'DisableCodeProtection|EnableCodeProtection|AllocNear|Malloc|Memcpy|FlattenTable|GenLuaCall)\b')
LUA_METHODS_BUILTIN = {'format', 'gsub', 'match', 'gmatch', 'find', 'sub', 'upper', 'lower', 'len', 'rep', 'byte',
                       'reverse', 'insert', 'remove', 'concat', 'sort', 'unpack', 'pack', 'close', 'read', 'write',
                       'lines', 'seek', 'char'}


def iex_defined():
    names = set()
    for f in (ROOT / 'lua').glob('*.lua'):
        text = f.read_text(encoding='latin-1')
        names |= set(re.findall(r'^\s*(?:function\s+)?(EEex_\w+)\s*=', text, re.M))
        names |= set(re.findall(r'function\s+(EEex_\w+)', text))
        names |= set(re.findall(r'function\s+\w+[.:](\w+)\s*\(', text))  # methods (CGameSprite.getName)
        names |= set(re.findall(r'^\s*\w+\.(\w+)\s*=\s*EEex_\w+', text, re.M))  # CGameSprite.getX = EEex_...
        # Names built in a loop: for name, x in pairs(T) do _G['EEex_Prefix_' .. name] = ... (keys of T)
        for table, prefix in re.findall(r"for\s+name,\s*\w+\s+in\s+pairs\((\w+)\)\s+do\s+_G\['(EEex_\w+)'\s*\.\.\s*name\]",
                                        text):
            body = re.search(r'\b' + table + r'\s*=\s*\{(.*?)\n\}', text, re.S)
            if body:
                names |= {prefix + key for key in re.findall(r'\b(\w+)\s*=', body.group(1))}
        # Methods added in a loop from a table: for name, fn in pairs(methods) do CGameSprite[name] = fn
        # (and the ...Iterator spelling of ...Itr names).
        for table in re.findall(r'for\s+name,\s*\w+\s+in\s+pairs\((\w+)\)\s+do\s+CGame\w+\[name\]', text):
            body = re.search(r'\b' + table + r'\s*=\s*\{(.*?)\n\s*\}', text, re.S)
            if body:
                keys = re.findall(r'\b(\w+)\s*=', body.group(1))
                names |= set(keys) | {re.sub(r'Itr$', 'Iterator', k) for k in keys}
    for f in (ROOT / 'src').rglob('*.cpp'):  # EEex functions registered from C++ (raw memory API...)
        names |= set(re.findall(r'\bRegister\(L,\s*"(EEex_\w+)"', f.read_text(encoding='latin-1')))
    return names


def iex_script_names():
    """Script-level EEex names IEX adds through IDS entries in weidu/IEX/IEX.tp2 (actions, triggers, objects such as
    EEex_LuaTrigger, EEex_LuaAction, EEex_LuaObject, EEex_Target): provided when used in WeiDU-side files (.baf/.d
    and the scripts tp2 code compiles), not as Lua functions."""
    tp2 = ROOT / 'weidu' / 'IEX' / 'IEX.tp2'
    return set(RX_EEEX.findall(tp2.read_text(encoding='latin-1'))) if tp2.exists() else set()


# A mod defining an EEex_ name itself (its own helper, or a fallback for old EEex versions) does not need it from
# the extender (rules_version 5).
RX_SELF_DEF = re.compile(r'(?:\bfunction\s+(EEex_\w+)|^\s*(?:local\s+)?(EEex_\w+)\s*=(?!=))', re.M)


TEST_DIRS = {'test', 'tests', 'spec', 'specs', 'mock', 'mocks'}


def self_defined(folder):
    """EEex_ names the mod defines itself. Test folders are skipped (their mocks stub the real API), and so are
    guarded fallbacks (EEex_X = EEex_X or ...), which still use the extender's version when it exists."""
    names = set()
    for path in folder.rglob('*'):
        if path.is_file() and path.suffix.lower() in LUA_EXT | WEIDU_EXT and not TEST_DIRS & {part.lower() for part in path.relative_to(folder).parts[:-1]}:
            text = read_code(path)
            for m in RX_SELF_DEF.finditer(text):
                name = m.group(1) or m.group(2)
                if not re.match(r'\s*' + name + r'\s+or\b', text[m.end():m.end() + 80]):
                    names.add(name)
    return names


def iex_fields():
    fields = set()
    for f in (ROOT / 'engine').glob('*.iexd'):
        for line in f.read_text(encoding='utf-8').splitlines():
            if line.startswith('field '):
                fields.add(line.split()[1])
    return fields


def iex_features():
    """Capability flags IEX provides (IEX_Features.<name>), as documented in docs/API_SPEC.md and docs/FRAMERATE.md. A flag can still be
    false at runtime (e.g. a site already patched by another mod): mods test the Lua value."""
    found = set()
    for doc in ('API_SPEC.md', 'FRAMERATE.md'):
        path = ROOT / 'docs' / doc
        if not path.exists():
            continue
        text = path.read_text(encoding='utf-8')
        # Every documented flag, in tables or in text (`IEX_Features.stickHooks` = ...).
        found.update(re.findall(r'`IEX_Features\.(\w+)', text))
        for row in re.findall(r'^\|\s*(`IEX_Features\.[^|]*)\|', text, re.M):
            # A table of sub-flags: `IEX_Features.nativeHooks` = `{ keepAmmo, groundMoveClick, ... }`
            sub = re.match(r'`IEX_Features\.(\w+)`\s*=\s*`\{([^}]*)\}`', row)
            if sub:
                found.update(sub.group(1) + '.' + n.strip() for n in sub.group(2).split(',') if n.strip())
                continue
            # Several flags in one cell: `IEX_Features.sadoAmmo`, `sadoAttackMove`, ...
            found.update(re.findall(r'`(\w+)`', row))
    # Hook points (docs/NATIVE_HOOK_POINTS.md): IEX_Features.nativeHooks[point] has one entry per point of the
    # registry, src/core/hook_points.cpp kPoints ({"name", "category", Kind::..., ...}).
    path = ROOT / 'src' / 'core' / 'hook_points.cpp'
    if path.exists():
        text = path.read_text(encoding='utf-8')
        found.update('nativeHooks.' + name for name in re.findall(r'\{"(\w+)",\s*"\w+",\s*Kind::', text))
    return found


RX_LUA_STRIP = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\\n])*"|' + r"'(?:\\.|[^'\\\n])*'",
                          re.S)


def lua_code(text):
    """Lua text without comments and string literals (approximate): a script name such as EEex_LuaTrigger inside a
    script string or a comment is not a Lua call."""
    return RX_LUA_STRIP.sub(' ', text)


# Comments (rules_version 5): commented-out code does not count. Strings are kept (they can hold Lua or script
# code); a comment marker inside a string is not a comment.
RX_LUA_COMMENT = re.compile(r'"(?:\\.|[^"\\\n])*"|' + r"'(?:\\.|[^'\\\n])*'" +
                            r'|\[(=*)\[.*?\]\1\]|(--\[(=*)\[.*?\]\3\]|--[^\n]*)', re.S)
RX_WEIDU_COMMENT = re.compile(r'~~~~~.*?~~~~~|~[^~]*~|"[^"]*"|(/\*.*?\*/|//[^\n]*)', re.S)


def strip_comments(text, ext):
    rx = RX_LUA_COMMENT if ext in LUA_EXT else RX_WEIDU_COMMENT
    group = 2 if ext in LUA_EXT else 1
    return rx.sub(lambda m: ' ' if m.group(group) else m.group(0), text)


def read_code(path):
    return strip_comments(path.read_text(encoding='latin-1', errors='replace'), path.suffix.lower())


def scan(folder):
    use, lua_use = collections.Counter(), collections.Counter()
    methods, fields, opcodes, hard = collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter()
    for path in folder.rglob('*'):
        if not path.is_file():
            continue
        ext = path.suffix.lower()
        if ext not in LUA_EXT and ext not in WEIDU_EXT:
            continue
        text = read_code(path)
        for n in RX_EEEX.findall(text):
            use[n] += 1
        for n in HARD.findall(text):
            hard[n] += 1
        if ext in LUA_EXT:
            for n in RX_EEEX.findall(lua_code(text)):
                lua_use[n] += 1
            for m in RX_METHOD.findall(text):
                if m not in LUA_METHODS_BUILTIN:
                    methods[m] += 1
            for m in RX_FIELD.findall(text):
                fields[m] += 1
        else:
            for op in RX_OPCODE.findall(text):
                opcodes[op] += 1
    return use, lua_use, methods, fields, opcodes, hard


RX_BEGIN = re.compile(r'^\s*BEGIN\b', re.M | re.I)
RX_DESIGNATED = re.compile(r'\bDESIGNATED\s+(\d+)', re.I)
RX_LABEL = re.compile(r'\bLABEL\s+[~"]([^~"]+)[~"]', re.I)
RX_PATH = re.compile(r'[~"]([^~"\r\n]+\.(?:lua|menu))[~"]', re.I)
RX_INCLUDE = re.compile(r'\b(?:INCLUDE|ACTION_INCLUDE|PATCH_INCLUDE|REINCLUDE)\s+[~"]([^~"]+)[~"]', re.I)
# A quoted source that could hold Lua the scan cannot see: a %variable% path, or a folder path (has a / and its last
# segment has no extension).
RX_OPAQUE = re.compile(r'[~"]([^~"\r\n]*%[^~"\r\n]*|[^~"\r\n]*/[^~"./\r\n]+/?)[~"]')
RX_IEX_DECLARED = re.compile(r'IEX/IEX\.TP2|\bIEX_[A-Z][A-Za-z]+\s*\(', re.I)


def text_stats(text, defined, known_fields):
    """missing EEex names, unknown fields and hard matches in one Lua text."""
    missing = {n for n in RX_EEEX.findall(text) if n not in defined}
    unknown = {f for f in RX_FIELD.findall(text) if f not in known_fields}
    return missing, unknown, set(HARD.findall(text))


def component_blocks(folder):
    """The tp2 BEGIN blocks of a mod: (tp2 path, id, label, block text plus its includes one level deep, the .lua /
    .menu files the block names). Shared by components() and inventory.py."""
    by_name = {p.name.lower(): p for p in folder.rglob('*') if p.suffix.lower() in LUA_EXT}
    for tp2 in folder.rglob('*.tp2'):
        text = read_code(tp2)
        starts = [m.start() for m in RX_BEGIN.finditer(text)] + [len(text)]
        for i in range(len(starts) - 1):
            block = text[starts[i]:starts[i + 1]]
            for inc in RX_INCLUDE.findall(block):
                inc_path = next((p for p in folder.rglob(pathlib.PurePath(inc).name) if p.is_file()), None)
                if inc_path:
                    block += read_code(inc_path)
            files = {by_name[pathlib.PurePath(p).name.lower()] for p in RX_PATH.findall(block)
                     if pathlib.PurePath(p).name.lower() in by_name}
            d = RX_DESIGNATED.search(block)
            lab = RX_LABEL.search(block)
            yield tp2, d.group(1) if d else str(i), lab.group(1) if lab else '', block, files


def components(folder, defined, known_fields):
    """Per-component verdicts: for each tp2 BEGIN block, the .lua/.menu files it names (directly or through one
    level of INCLUDE) are scanned. Verdict without files: unknown (a folder or %variable% source could hold Lua) or
    no_lua (= compatible); with files: unsupported (hard usage) > partial (missing names or unknown fields) >
    compatible."""
    result = []
    for tp2, comp_id, comp_label, block, files in component_blocks(folder):
        missing, unknown, hard = set(), set(), set()
        for f in files:
            m, u, h = text_stats(read_code(f), defined, known_fields)
            missing |= m
            unknown |= u
            hard |= h
        if not files:
            # No Lua file named: unknown if Lua could still come from a folder or %variable% copy, else none at all.
            # A block that mentions EEex is never no_lua: it may install its Lua through a function call.
            verdict = 'unknown' if (RX_OPAQUE.search(block) or 'eeex' in block.lower()) else 'no_lua'
        else:
            verdict = 'unsupported' if hard else 'partial' if (missing or unknown) else 'compatible'
        result.append({'tp2': tp2.name, 'component': comp_id, 'label': comp_label,
                       'files': len(files), 'verdict': verdict, 'missing': sorted(missing),
                       'unknown_fields': sorted(unknown), 'hard': sorted(hard)})
    return result


def declares_iex(folder):
    for path in folder.rglob('*'):
        if path.is_file() and path.suffix.lower() in LUA_EXT | WEIDU_EXT:
            if RX_IEX_DECLARED.search(path.read_text(encoding='latin-1', errors='replace')):
                return True
    return False


def label(folder):
    # Downloaded mods sit in <name>/src: name the row after the mod, not after "src".
    return folder.parent.name if folder.name.lower() == 'src' else folder.name


def main():
    if sys.argv[1] == '--api-json':
        import json
        api = {'schema': 1, 'rules_version': 5, 'version': (ROOT / 'VERSION').read_text().strip(), 'eeex_names': sorted(iex_defined()),
               'script_names': sorted(iex_script_names()), 'fields': sorted(iex_fields()), 'features': sorted(iex_features()),
               'hard_unsupported': 'x64 asm / hooks / labels / raw memory writes bound to one exe (regex HARD)'}
        pathlib.Path(sys.argv[2]).write_text(json.dumps(api, indent=1), encoding='utf-8')
        print(f"{len(api['eeex_names'])} names, {len(api['fields'])} fields -> {sys.argv[2]}")
        return
    out = pathlib.Path(sys.argv[1])
    folders = [pathlib.Path(p) for p in sys.argv[2:]]
    defined, known_fields, script_names = iex_defined(), iex_fields(), iex_script_names()
    lines = ['# Mod scan: EEex usage vs IEX', '', f'IEX defines {len(defined)} EEex names/methods; '
             f'descriptions know {len(known_fields)} field names.', '',
             '| Mod | badge | EEex names | missing in IEX | fields | unknown fields | EEex opcodes | hard (asm/raw memory) |',
             '|---|---|---|---|---|---|---|---|']
    details = []
    all_missing = collections.Counter()
    mods_using = collections.defaultdict(set)  # missing name -> mods that use it
    for folder in folders:
        use, lua_use, methods, fields, opcodes, hard = scan(folder)
        own = self_defined(folder)
        # Script names (IDS) count as provided unless the name is also used from Lua files.
        missing = {n: c for n, c in use.items()
                   if n not in defined and n not in own and not (n in script_names and not lua_use[n])}
        for n in own:
            hard.pop(n, None)
        unknown = {n: c for n, c in fields.items() if n not in known_fields}
        for n, c in missing.items():
            all_missing[n] += c
            mods_using[n].add(label(folder))
        badge = 'unsupported' if hard else ('partial' if missing or unknown else 'compatible')
        lines.append(f'| {label(folder)} | {badge} | {len(use)} | {len(missing)} | {len(fields)} | {len(unknown)} | '
                     f'{", ".join(sorted(opcodes)) or "-"} | {sum(hard.values()) or "-"} |')
        details += ['', f'## {label(folder)}', '',
                    '**Missing EEex names:** ' + (', '.join(f'`{n}`({c})' for n, c in sorted(missing.items(), key=lambda x: -x[1])) or 'none'),
                    '', '**Defined by the mod itself (not needed from the extender):** ' +
                    (', '.join(f'`{n}`' for n in sorted(own & set(use))[:80]) or 'none'),
                    '', '**Unknown fields:** ' + (', '.join(f'`{n}`({c})' for n, c in sorted(unknown.items(), key=lambda x: -x[1])[:60]) or 'none'),
                    '', '**Engine-object methods called:** ' + (', '.join(f'`{n}`({c})' for n, c in methods.most_common(40)) or 'none'),
                    '', '**Hard usage:** ' + (', '.join(f'`{n}`({c})' for n, c in hard.most_common()) or 'none'),
                    '', '**Declares IEX support:** ' + ('yes' if declares_iex(folder) else 'no')]
        comps = components(folder, defined | own | script_names, known_fields)
        if comps:
            counts = collections.Counter(c['verdict'] for c in comps)
            details += ['', f'**Components:** {counts["compatible"]} compatible, {counts["partial"]} partial, '
                        f'{counts["unsupported"]} unsupported, {counts["unknown"]} unknown (Lua may come from a folder or %variable% copy: '
                        f'use the mod-level result), {counts["no_lua"]} no_lua (= compatible)', '', '| tp2 | # | label | files | verdict | why |',
                        '|---|---|---|---|---|---|']
            for c in comps:
                why = ', '.join(c['hard'][:4]) or ', '.join(c['missing'][:4] + c['unknown_fields'][:2])
                details.append(f"| {c['tp2']} | {c['component']} | {c['label']} | {c['files']} | {c['verdict']} | {why} |")
    lines += ['', '## Missing EEex names across all scanned mods', '',
              ', '.join(f'`{n}`({c})' for n, c in all_missing.most_common()) or 'none']
    ranked = sorted(mods_using.items(), key=lambda x: (-len(x[1]), -all_missing[x[0]], x[0]))
    lines += ['', '## Missing EEex names ranked by number of mods', '', '| name | mods | uses | hard | used by |',
              '|---|---|---|---|---|']
    lines += [f"| `{n}` | {len(m)} | {all_missing[n]} | {'yes' if HARD.fullmatch(n) else ''} | {', '.join(sorted(m))} |"
              for n, m in ranked]
    out.write_text('\n'.join(lines + details) + '\n', encoding='utf-8')
    print(f'{len(folders)} mods scanned -> {out}; {len(all_missing)} distinct EEex names missing overall')


if __name__ == '__main__':
    main()
