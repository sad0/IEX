"""Static inventory of everything EEex-using mods depend on, compared with what IEX provides.

Usage: python -I inventory.py --corpus <corpus.json> --mods <mods dir> --json <out.json> --md <out.md>

Companion of scan_mods.py (same file reading, comment rules and component blocks; no verdict of its own, so no
rules_version change). For every mod folder of <mods dir> listed in corpus.json, and for every tp2 component, it
extracts:
  eeex        EEex_* functions / tables / constants: uses, argument shapes, string arguments, example lines
  listener    EEex_*Add*Listener registrations (callback parameter names)
  method      engine-object methods obj:method(...) with the receiver class when it can be inferred
  field       engine fields .m_xxx (chains) with the class when it can be inferred
  opcode      EEex opcodes 400-409 in WeiDU / Lua effect data, with their parameters
  ids         script names (EEex_LuaTrigger / LuaAction / LuaObject / Target / LuaDecode...) and IDS appends
              (STATS.IDS ids > 202 = extended stats, X-*.2DA / X-*.IDS rows)
  datafile    EEex data / Lua files the mod probes, reads or patches (X-*.2DA, EEex_*.lua, B3*.lua, EEex.dll...)
  menu        .menu names the mod uses (marked when the mod defines them itself)
  module_flag EEex_Modules switches the mod sets
  setting     option keys: Infinity_GetINIValue / SetINIValue, EEex_Options_*, EEex.ini / InfinityLoader.ini keys
              written by tp2 code, Baldur.lua keys written by tp2 code
  hard        x64 asm / hooks / labels / raw memory (scan_mods.HARD) with the engine labels they target
  requirement how the mod checks for EEex (REQUIRE_COMPONENT, MOD_IS_INSTALLED, FILE_EXISTS, Lua checks) and
              whether tools/compat/patch_mod.py rewrites the check for IEX
and gives each item an IEX status (provided / partial / missing / unsupported / script / unknown).
Downloaded mods are data: nothing in them is executed.
"""
import bisect
import collections
import datetime
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import patch_mod  # noqa: E402
import scan_mods as sm  # noqa: E402

ROOT = sm.ROOT
DOC_EXT = {'.md', '.txt', '.html', '.htm'}
MAX_EXAMPLES = 6
MAX_STRARGS = 40

# ---------------------------------------------------------------------------------------------------------------
# Reading


def blank_comments(text, ext):
    """scan_mods.strip_comments, but comments become spaces of the same length (newlines kept): offsets and line
    numbers stay those of the original file."""
    lua = ext in sm.LUA_EXT
    rx = sm.RX_LUA_COMMENT if lua else sm.RX_WEIDU_COMMENT
    group = 2 if lua else 1
    return rx.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)) if m.group(group) else m.group(0), text)


RX_LUA_STR = re.compile(r'"(?:\\.|[^"\\\n])*"|' + r"'(?:\\.|[^'\\\n])*'" + r'|\[(=*)\[.*?\]\1\]', re.S)


class Source:
    """One file: original text, comment-free text, line index, Lua string spans."""

    def __init__(self, path, rel, text=None, ext=None):
        self.path, self.rel = path, rel
        self.ext = ext or path.suffix.lower()
        self.raw = text if text is not None else path.read_text(encoding='latin-1', errors='replace')
        self.code = self.raw if text is not None else blank_comments(self.raw, self.ext)
        self.nl = [i for i, c in enumerate(self.code) if c == '\n']
        self.lua = self.ext in sm.LUA_EXT
        self.spans = [(m.start(), m.end()) for m in RX_LUA_STR.finditer(self.code)] if self.lua else []
        self.span_starts = [s for s, _ in self.spans]

    def line(self, pos):
        return bisect.bisect_left(self.nl, pos) + 1

    def line_text(self, pos):
        a = self.code.rfind('\n', 0, pos) + 1
        b = self.code.find('\n', pos)
        return self.raw[a:b if b >= 0 else len(self.raw)].strip()[:220]

    def in_string(self, pos):
        i = bisect.bisect_right(self.span_starts, pos) - 1
        return i >= 0 and self.spans[i][0] < pos < self.spans[i][1]


# ---------------------------------------------------------------------------------------------------------------
# Argument shapes


def balanced(text, i, limit=1500):
    """text[i] is '(' or '{': the text up to its matching closer (exclusive), or None."""
    pairs = {'(': ')', '{': '}', '[': ']'}
    depth, j, n = 0, i, min(len(text), i + limit)
    while j < n:
        c = text[j]
        if c in '"\'':
            k = j + 1
            while k < n and text[k] != c and text[k] != '\n':
                k += 2 if text[k] == '\\' else 1
            j = k
        elif c == '[' and j + 1 < n and text[j + 1] in '[=':
            m = re.match(r'\[(=*)\[', text[j:])
            if m:
                end = text.find(']' + m.group(1) + ']', j)
                j = end + len(m.group(1)) + 1 if end >= 0 else n
            else:
                depth += 1
        elif c in pairs:
            depth += 1
        elif c in ')}]':
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
        j += 1
    return None


def split_top(args):
    out, depth, cur, i = [], 0, [], 0
    while i < len(args):
        c = args[i]
        if c in '"\'':
            k = i + 1
            while k < len(args) and args[k] != c:
                k += 2 if args[k] == '\\' else 1
            cur.append(args[i:k + 1])
            i = k + 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    last = ''.join(cur).strip()
    if last or out:
        out.append(last)
    return out


def table_keys(t):
    inner = RX_LUA_STR.sub('""', t)
    prev = None
    while prev != inner:
        prev, inner = inner, re.sub(r'\{[^{}]*\}', '{}', inner)
    keys = re.findall(r'(?:\[\s*["\']([A-Za-z_]\w*)["\']\s*\]|(?<![\w.])([A-Za-z_]\w*))\s*=(?!=)', inner)
    return [a or b for a, b in keys]


def arg_shape(a):
    a = a.strip()
    if not a:
        return 'empty'
    if re.fullmatch(r'-?(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)', a):
        return 'num'
    if a[0] in '"\'' or a.startswith('[['):
        return 'str'
    if a in ('nil', 'true', 'false'):
        return a if a == 'nil' else 'bool'
    if a.startswith('{'):
        body = balanced(a, 0)
        keys = table_keys(body or a[1:])
        return 'table{' + ','.join(sorted(set(keys))[:12]) + '}' if keys else 'table'
    m = re.match(r'function\s*\(([^)]*)\)', a)
    if m:
        return 'fn(' + ','.join(p.strip() for p in m.group(1).split(',') if p.strip()) + ')'
    m = re.match(r'(EEex_\w+|Infinity_\w+|IEX_\w+)\s*\(', a)
    if m:
        return 'call:' + m.group(1)
    if re.fullmatch(r'[A-Za-z_]\w*', a):
        return 'var'
    if re.fullmatch(r'[A-Za-z_][\w.]*(?:\[[^\]]*\])*', a):
        return 'field'
    if '..' in a:
        return 'concat'
    return 'expr'


def str_value(a):
    a = a.strip()
    if a[:1] in '"\'' and a[-1:] == a[:1]:
        return a[1:-1]
    if a.startswith('[['):
        return a[2:-2]
    return None


# ---------------------------------------------------------------------------------------------------------------
# What IEX provides


RX_PARTIAL = re.compile(r'not (?:drawn|supported|tracked|implemented)\b|does nothing|always (?:false|nil|0)\b|'
                        r'not supported by IEX|IEX does not|no-op|\bgap\b|kept, never needed', re.I)


def iex_side():
    defined = sm.iex_defined()
    side = {'version': (ROOT / 'VERSION').read_text().strip(), 'defined': defined, 'script': sm.iex_script_names(),
            'fields': sm.iex_fields(), 'features': sm.iex_features(), 'partial': {}, 'method_class': collections.defaultdict(set)}
    # Partial: the comment block above a definition (or its body) says it is incomplete.
    for f in sorted((ROOT / 'lua').glob('*.lua')):
        lines = f.read_text(encoding='latin-1').splitlines()
        for i, line in enumerate(lines):
            m = re.match(r'\s*(?:function\s+([\w.:]+)|(EEex_\w+)\s*=)', line)
            if not m:
                continue
            name = re.split(r'[.:]', m.group(1) or m.group(2))[-1]
            j, comment = i - 1, []
            while j >= 0 and lines[j].lstrip().startswith('--'):
                comment.insert(0, lines[j].strip())
                j -= 1
            body = []
            for k in range(i + 1, min(len(lines), i + 12)):
                if re.match(r'(?:function|end\b|\S+\s*=)', lines[k]):
                    break
                body.append(lines[k])
            hit = RX_PARTIAL.search(' '.join(comment + body))
            if hit and name in defined:
                text = ' '.join(c.lstrip('- ') for c in comment) or ' '.join(b.strip() for b in body)
                side['partial'][name] = f'{f.name}: {text[:160]}'
            cm = re.match(r'\s*function\s+(C\w+|ui\w+)[.:](\w+)', line)
            if cm:
                side['method_class'][cm.group(2)].add(cm.group(1))
    for line in (ROOT / 'engine' / 'methods.txt').read_text(encoding='utf-8').splitlines():
        p = line.split()
        if len(p) >= 3 and not line.startswith('#'):
            side['method_class'][p[1]].add(p[0])
            side['defined'].add(p[1])
    # Engine types: fields per class, bases.
    types, bases = collections.defaultdict(dict), {}
    for f in sorted((ROOT / 'engine').glob('*.iexd')):
        cur = None
        for line in f.read_text(encoding='utf-8').splitlines():
            p = line.split()
            if not p:
                continue
            if p[0] == 'type':
                cur = p[1]
                for x in p[3:]:
                    if x.startswith('base='):
                        bases[cur] = x[5:].split('@')[0]
            elif p[0] == 'field' and cur:
                types[cur][p[1]] = p[3] if len(p) > 3 else ''
    side['types'], side['bases'] = types, bases
    # Engine symbols as Class::method (from the Itanium-mangled names of the engine descriptions), to tell whether a
    # label a mod names is an engine function IEX knows.
    side['symbols'] = set()
    for f in sorted((ROOT / 'engine').glob('*.iexd')):
        for line in f.read_text(encoding='utf-8').splitlines():
            if line.startswith('symbol '):
                name = line.split()[1]
                side['symbols'].add(name)
                m = re.match(r'_ZN(?:K)?((?:\d+\w+?)+)E', name)
                if m:
                    parts, s = [], m.group(1)
                    while s:
                        n = re.match(r'(\d+)', s)
                        if not n:
                            break
                        k = int(n.group(1))
                        parts.append(s[len(n.group(1)):len(n.group(1)) + k])
                        s = s[len(n.group(1)) + k:]
                    if len(parts) >= 2:
                        side['symbols'].add('::'.join(parts))
    side['field_classes'] = collections.defaultdict(set)
    for t, fs in types.items():
        for fname in fs:
            side['field_classes'][fname].add(t)
    opc = (ROOT / 'src' / 'core' / 'opcodes.cpp').read_text(encoding='latin-1')
    side['opcodes'] = set(re.findall(r'case\s+(40\d)\s*:', opc)) | set(re.findall(r'==\s*(40\d)\b', opc))
    tp2 = (ROOT / 'weidu' / 'IEX' / 'IEX.tp2').read_text(encoding='latin-1')
    side['datafiles'] = {x.upper() for x in re.findall(r'~override/([^~]+)~', tp2)}
    side['ids_appends'] = {(f.upper(), n) for f, n in re.findall(r'APPEND\s+~(\w+\.ids)~\s+~\S+\s+(\w+)', tp2, re.I)}
    side['lua_files'] = {f.name.upper() for f in (ROOT / 'lua').glob('*.lua')}
    src = ' '.join(p.read_text(encoding='latin-1') for p in list((ROOT / 'src').rglob('*.cpp')) + list((ROOT / 'lua').glob('*.lua')))
    side['reads_eeex_ini'] = bool(re.search(r'EEex\.ini', src))
    side['reads_loader_ini'] = bool(re.search(r'InfinityLoader\.ini', src))
    opt = (ROOT / 'lua' / 'EEex_Options.lua').read_text(encoding='latin-1')
    sig = re.search(r'function EEex_Options_NumberLuaStorage:read\(([^)]*)\)', opt)
    wsig = re.search(r'function EEex_Options_NumberLuaStorage:write\(([^)]*)\)', opt)
    side['options_storage'] = ('Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue '
                               f"(lua/EEex_Options.lua; storage:read({sig.group(1) if sig else '?'}) / "
                               f"storage:write({wsig.group(1) if wsig else '?'}))")
    return side


def class_chain(side, cls):
    out = []
    while cls and cls not in out:
        out.append(cls)
        cls = side['bases'].get(cls)
    return out


def field_type(side, cls, fname):
    """Type of cls.fname, through its bases; else through its subclasses (EEex_GameObject_Get returns the concrete
    object, so a CGameObject receiver is often a sprite)."""
    for c in class_chain(side, cls):
        if fname in side['types'].get(c, {}):
            return side['types'][c][fname]
    for c, fields in side['types'].items():
        if fname in fields and cls in class_chain(side, c):
            return fields[fname]
    return None


# ---------------------------------------------------------------------------------------------------------------
# Class inference

PREFIX_CLASS = {'Sprite': 'CGameSprite', 'GameObject': 'CGameObject', 'Area': 'CGameArea', 'Projectile': 'CProjectile',
                'AIBase': 'CGameAIBase', 'Action': 'CAIAction', 'GameState': 'CInfGame', 'Trigger': 'CGameTrigger',
                'Container': 'CGameContainer', 'Door': 'CGameDoor', 'Effect': 'CGameEffect', 'Opcode': 'CGameEffect',
                'Menu': 'uiItem', 'Object': 'CAIObjectType', 'Resource': 'CRes'}
NAME_CLASS = [(r'sprite|actor|creature|^cre$|caster|^target|^source|^member|^char|^pc\d*$|^npc|^leader|^me$|^attacker|^victim', 'CGameSprite'),
              (r'effect|^eff|^op\d+', 'CGameEffect'), (r'area', 'CGameArea'), (r'proj', 'CProjectile'),
              (r'stats', 'CDerivedStats'), (r'aibase', 'CGameAIBase'), (r'object|^obj', 'CGameObject'),
              (r'action', 'CAIAction'), (r'^game$|infgame', 'CInfGame'), (r'container', 'CGameContainer'),
              (r'door', 'CGameDoor'), (r'trigger', 'CGameTrigger'), (r'item', 'CItem'), (r'button', 'CButtonData'),
              (r'chitin', 'CBaldurChitin')]


def class_of_call(name):
    m = re.match(r'EEex_(\w+?)_(Get\w*|Find\w*)$', name)
    if m and not re.search(r'All|Iterator|Itr|IDs?$|Count|Num|Stat|Level|Name|Res|Type|Index', m.group(2)):
        return PREFIX_CLASS.get(m.group(1))
    return {'EEex_GameObject_Get': 'CGameObject', 'EEex_Sprite_GetSelected': 'CGameSprite',
            'EEex_Area_GetVisible': 'CGameArea', 'EEex_GameObject_GetUnderCursor': 'CGameObject'}.get(name)


def class_of_receiver(recv, assigns):
    base = re.split(r'[.\[]', recv)[0]
    if base in assigns:
        return assigns[base]
    low = base.lower()
    for rx, cls in NAME_CLASS:
        if re.search(rx, low):
            return cls
    return None


RX_ASSIGN_CALL = re.compile(r'(?:local\s+)?([A-Za-z_]\w*)\s*=\s*(EEex_\w+)\s*\(')
RX_METHOD_CALL = re.compile(r'([A-Za-z_]\w*(?:\.[A-Za-z_]\w*|\[[^\]\n]*\])*)\s*:\s*([A-Za-z_]\w*)\s*\(')
RX_MOD_METHODS = re.compile(r'function\s+[\w.]+[:.](\w+)\s*\(|(\w+)\s*=\s*function\b|\[["\'](\w+)["\']\]\s*=\s*function\b')
SKIP_RECEIVERS = {'self', 'string', 'table', 'math', 'io', 'os', 'coroutine', 'bit', 'bit32', 'debug', 'utf8', 'ffi', 'jit'}
RX_FIELD_TOKEN = re.compile(r'[\w.\[\]"\'#]*\.m_\w+[\w.\[\]]*')

# ---------------------------------------------------------------------------------------------------------------
# Patterns of the other categories

SCRIPT_LIKE = re.compile(r'EEex_(?:Lua(?:Trigger|Action|Object|Decode)|Target|MatchObject\w*|SetTarget|'
                         r'HasDispellableEffect|IsImmuneToOpcode|\w*SpellObjectOffset\w*)$')
RX_OPCODE_ANY = re.compile(r'\b(?:opcode|match_opcode|effectID|m_effectId)\s*["\']?\]?\s*=\s*(40\d)\b', re.I)
RX_EFF_PARAM = re.compile(r'\b(parameter[1-4]|param[1-4]|special|timing|duration|resource[23]?|res[23]?|power|'
                          r'target|probability[12]|dicenumber|dicesize|savingthrow|savebonus|match_\w+|m_\w+|'
                          r'effectAmount|dwFlags|durationType|sourceRes)\s*["\']?\]?\s*=\s*(~[^~]*~|"[^"]*"|\'[^\']*\'|[^\s,}]+)', re.I)
RX_IDS_APPEND = re.compile(r'APPEND\s+[~"]((?:stats|action|trigger|object|spell|splstate|x-\w+)\.(?:ids|2da))[~"]\s+'
                           r'[~"]([^~"\r\n]+)[~"]', re.I)
RX_ADD_IDS = re.compile(r'ADD_IDS_ENTRY\b[^~]*?STR_VAR[^~]*?(?:idsfile|ids)\s*=\s*~(\w+)~[^~]*?(?:identifier|entry)\s*=\s*~([^~]+)~', re.I | re.S)
RX_DATAFILE = re.compile(r'\b((?:X-[A-Z0-9#_-]+\.(?:2DA|IDS))|(?:\w*EEex\w*|B3\w*)\.(?:lua|menu)|EEex\.(?:dll|db|exe|ini)|'
                         r'InfinityLoader\.(?:exe|db|ini|dll)|EEex_\w+\.lua)\b', re.I)
RX_FILEOP = re.compile(r'(FILE_EXISTS_IN_GAME|FILE_EXISTS|COPY_EXISTING_REGEXP|COPY_EXISTING|COPY_LARGE|COPY|APPEND|'
                       r'EXTEND_TOP|EXTEND_BOTTOM|FILE_CONTAINS_EVALUATED|FILE_CONTAINS|RESOURCE_CONTAINS|INCLUDE|'
                       r'Infinity_DoFile|dofile|require|EEex_Menu_LoadFile|DELETE)\b', re.I)
RX_MENU_DEF = re.compile(r'\bmenu\s*\{\s*name\s*["\']([^"\']+)["\']', re.I)
RX_MENU_USE = re.compile(r'\b(EEex_Menu_\w+|Infinity_(?:PushMenu|PopMenu|IsMenuOnStack|GetMenuArea|SetArea|'
                         r'InstanceAnimation|DestroyAnimation|GetMenuItemByName))\s*\(\s*["\']([^"\']+)["\']')
RX_MODULE_FLAG = re.compile(r'\[\s*["\'](\w+)["\']\s*\]\s*=\s*(true|false)')
RX_INI_CALL = re.compile(r'\bInfinity_(Get|Set)INIValue\b\s*(?:,\s*|\()')
RX_EEEX_INI_REF = re.compile(r'(EEex\.ini|InfinityLoader\.ini)', re.I)
RX_INI_SECTION = re.compile(r'\\?\[([A-Za-z][^\]\r\n~%\\]{0,60})\\?\]')
RX_INI_KEY = re.compile(r'^[ \t]*([A-Za-z][\w .]{0,40}?)[ \t]*=[ \t]*([^\s~\\]*)', re.M)
RX_BALDUR_INI = re.compile(r'SetPrivateProfileString\s*\(\s*\'([^\']*)\'\s*,\s*\'([^\']*)\'\s*,\s*\'([^\']*)\'')
RX_GETINI_STRING = re.compile(r'\b(EEex\.GetINIString|EEex_GetINIString|EEex\.GetINIValue|EEex_GetINI\w*)\s*\(')
RX_LABEL_STR = re.compile(r'["\']((?:Hook-)?[A-Za-z_]\w*::[~\w]+(?:\([^"\'\n]*\))?(?:-[\w-]+)?|Hook-[^"\'\n]+)["\']')
RX_FUNC_DEF = re.compile(r'(?:function\s+([\w.:]+)\s*\(|([\w.]+)\s*=\s*function\s*\()')
RX_REQ = [
    ('REQUIRE_COMPONENT', re.compile(r'REQUIRE_COMPONENT\s+[~"]([^~"]*eeex[^~"]*)[~"]\s+[~"]?(\w+)[~"]?', re.I)),
    ('MOD_IS_INSTALLED', re.compile(r'MOD_IS_INSTALLED\s+[~"]([^~"]*eeex[^~"]*)[~"]\s+(\(\s*ID_OF_LABEL\s+[~"][^~"]+[~"]\s+[~"][^~"]+[~"]\s*\)|[~"]?\w+[~"]?)', re.I)),
    ('FORBID_COMPONENT', re.compile(r'FORBID_COMPONENT\s+[~"]([^~"]*eeex[^~"]*)[~"]\s+[~"]?(\w+)[~"]?', re.I)),
    ('FILE_EXISTS', re.compile(r'(?:FILE_EXISTS_IN_GAME|FILE_EXISTS)\s+[~"]([^~"]*(?:eeex|infinityloader)[^~"]*)[~"]()', re.I)),
    ('FILE_CONTAINS', re.compile(r'FILE_CONTAINS(?:_EVALUATED)?\s*\(?\s*[~"]([^~"]*(?:eeex|infinityloader)[^~"]*)[~"]\s+[~"]([^~"]*)[~"]', re.I)),
]
RX_LUA_REQ = re.compile(r'\b(EEex_(?:Active|Version|GetVersion|MinimumBuildVersion|IsActive|Build\w*|Loaded|Main))\b')
RX_DOC_VERSION = re.compile(r'EEex[^\n]{0,30}?\b(v?\d+\.\d+(?:\.\d+)*(?:[-\s]?(?:alpha|beta))?)', re.I)


def patched_by_patch_mod(text):
    return any(rx.search(text) for rx, _ in patch_mod.RULES)


# ---------------------------------------------------------------------------------------------------------------
# Collector


class Items:
    """cat -> key -> record (uses, files, shapes, string args, examples, extra)."""

    def __init__(self):
        self.d = collections.defaultdict(dict)

    def add(self, cat, key, src=None, pos=None, shape=None, strargs=None, extra=None):
        r = self.d[cat].get(key)
        if r is None:
            r = self.d[cat][key] = {'uses': 0, 'files': set(), 'shapes': collections.Counter(), 'strargs': {},
                                    'examples': {}, 'extra': collections.defaultdict(set)}
        r['uses'] += 1
        if src is not None:
            r['files'].add(src.rel)
        if shape is not None:
            r['shapes'][shape] += 1
            if src is not None and pos is not None and shape not in r['examples'] and len(r['examples']) < MAX_EXAMPLES:
                r['examples'][shape] = {'file': src.rel, 'line': src.line(pos), 'code': src.line_text(pos)}
        for i, v in (strargs or {}).items():
            vals = r['strargs'].setdefault(str(i), set())
            if len(vals) < MAX_STRARGS:
                vals.add(v[:80])
        for k, v in (extra or {}).items():
            if isinstance(v, (set, list, tuple)):
                r['extra'][k] |= set(v)
            elif v is not None:
                r['extra'][k].add(v)
        return r

    def merge(self, other):
        for cat, d in other.d.items():
            for key, o in d.items():
                r = self.d[cat].get(key)
                if r is None:
                    r = self.d[cat][key] = {'uses': 0, 'files': set(), 'shapes': collections.Counter(), 'strargs': {},
                                            'examples': {}, 'extra': collections.defaultdict(set)}
                r['uses'] += o['uses']
                r['files'] |= o['files']
                r['shapes'].update(o['shapes'])
                for s, ex in o['examples'].items():
                    if s not in r['examples'] and len(r['examples']) < MAX_EXAMPLES:
                        r['examples'][s] = ex
                for i, v in o['strargs'].items():
                    vals = r['strargs'].setdefault(i, set())
                    vals |= set(list(v)[:max(0, MAX_STRARGS - len(vals))])
                for k, v in o['extra'].items():
                    r['extra'][k] |= v

    def keys(self):
        return {cat: sorted(d) for cat, d in self.d.items()}


def call_info(text, after):
    """After a name: ('call', args list) / ('member', '.x') / ('assign', None) / ('ref', None)."""
    m = re.match(r'[ \t]*([(.:\[=])', text[after:after + 200])
    if not m:
        return 'ref', None
    c, at = m.group(1), after + m.end() - 1
    if c == '(':
        body = balanced(text, at)
        return 'call', (split_top(body) if body is not None else None)
    if c in '.:':
        mm = re.match(r'[.:]\s*(\w+)', text[at:at + 80])
        return 'member', ('.' + mm.group(1) if mm else '.?')
    if c == '[':
        return 'member', '[]'
    if text[at:at + 2] == '==':
        return 'ref', None
    return 'assign', None


def shape_of(kind, args):
    if kind == 'call':
        if args is None:
            return '(...)', {}
        strs = {i: v for i, v in ((i, str_value(a)) for i, a in enumerate(args)) if v is not None}
        return '(' + ', '.join(arg_shape(a) for a in args) + ')', strs
    if kind == 'member':
        return args, {}
    return kind, {}


def analyze_source(src, items, side, own, mod_methods, mod_menus=frozenset(), mod_files=frozenset()):
    code = src.code
    weidu = not src.lua
    # a) / b) / e): EEex names
    for m in sm.RX_EEEX.finditer(code):
        name = m.group(1)
        kind, args = call_info(code, m.end())
        shape, strs = shape_of(kind, args)
        in_str = src.lua and src.in_string(m.start())
        script = src.ext in ('.baf', '.d') or ((weidu or in_str) and (name in side['script'] or SCRIPT_LIKE.match(name)))
        if script:
            items.add('ids', name, src, m.start(), shape, strs, {'where': src.ext})
            if not (src.lua and not in_str):
                continue
        items.add('eeex', name, src, m.start(), shape, strs, {'own': name in own, 'side': 'weidu' if weidu else ('lua-string' if in_str else 'lua')})
        if re.search(r'Add\w*Listener$', name) and kind in ('call', 'ref'):
            cb = [a for a in (args or []) if a.startswith('function')]
            items.add('listener', name, src, m.start(), shape, strs,
                      {'callback': [arg_shape(a) for a in cb] or [arg_shape(a) for a in (args or [])[:1]]})
        rq = RX_LUA_REQ.fullmatch(name)
        if rq and not weidu:
            items.add('requirement', 'Lua: ' + name, src, m.start(), shape, None, {'patched': 'n/a (runtime)'})
    # h) hard usage, with the Lua function it sits in and the engine labels it names
    fdefs = [(fm.start(), fm.group(1) or fm.group(2)) for fm in RX_FUNC_DEF.finditer(code)]
    fpos = [p for p, _ in fdefs]
    for m in sm.HARD.finditer(code):
        name = m.group(0)
        if name in own:
            continue
        kind, args = call_info(code, m.end())
        shape, strs = shape_of(kind, args)
        i = bisect.bisect_left(fpos, m.start()) - 1
        fn = fdefs[i][1] if i >= 0 else None
        labels = {v for v in strs.values() if '::' in v or v.startswith('Hook-')}
        items.add('hard', name, src, m.start(), shape, strs, {'labels': labels, 'functions': {fn} if fn else set()})
    for m in RX_LABEL_STR.finditer(code):
        items.add('label', m.group(1), src, m.start(), 'string', None, {})
    # f) data files
    for m in RX_DATAFILE.finditer(code):
        a = code.rfind('\n', 0, m.start()) + 1
        ops = RX_FILEOP.findall(code[a:m.start()])
        op = ops[-1].upper() if ops else ('LUA' if src.lua else 'MENTION')
        items.add('datafile', m.group(1).upper(), src, m.start(), op, None, {'op': op, 'mod_file': m.group(1).upper() in mod_files})
    # setting: EEex.ini / InfinityLoader.ini written by tp2 code
    if weidu:
        for m in RX_EEEX_INI_REF.finditer(code):
            window = code[m.start():m.start() + 1800]
            nxt = sm.RX_BEGIN.search(window)
            window = window[:nxt.start()] if nxt else window
            section = None
            # INI lines have no space before '=' (Enable=1); WeiDU statements do (SET x = 1).
            for t in re.finditer(r'\\?\[([A-Za-z][^\]\r\n~%\\]{0,60})\\?\]|^[ \t]*[A-Za-z][\w .]{0,30}?[\w.]\\?=[^\n]*', window, re.M):
                if t.group(1):
                    section = t.group(1).strip()
                    continue
                km = re.match(r'[ \t]*([A-Za-z][\w .]{0,30}?[\w.])\\?=\\?\)?([^\s~\\)]*)', t.group(0))
                if km and section:
                    items.add('setting', f'{m.group(1)}|{section}|{km.group(1).strip()}', src, m.start(), 'tp2-write', None,
                              {'store': m.group(1), 'section': section, 'key': km.group(1).strip(), 'value': km.group(2) or '?',
                               'op': 'tp2 writes'})
            # A key=value line the tp2 looks for (COUNT_REGEXP_INSTANCES ~^LuaPatchMode=...~, INDEX_BUFFER ...).
            for km in re.finditer(r'(COUNT_REGEXP_INSTANCES|INDEX_BUFFER|REPLACE_TEXTUALLY|REPLACE_EVALUATE|RESOURCE_CONTAINS|'
                                  r'FILE_CONTAINS\w*)[^~"\n]*[~"]\^?\\?\(?([A-Za-z]\w*)=([^~"\s\\)]*)', window):
                op = 'tp2 reads' if km.group(1).upper() in ('COUNT_REGEXP_INSTANCES', 'INDEX_BUFFER', 'RESOURCE_CONTAINS') or km.group(1).upper().startswith('FILE_CONTAINS') else 'tp2 writes'
                items.add('setting', f'{m.group(1)}|{section or "-"}|{km.group(2)}', src, m.start(), op, None,
                          {'store': m.group(1), 'section': section or '-', 'key': km.group(2), 'value': km.group(3) or '?', 'op': op})
        for m in RX_BALDUR_INI.finditer(code):
            items.add('setting', f'Baldur.lua|{m.group(1)}|{m.group(2)}', src, m.start(), 'tp2-write', None,
                      {'store': 'Baldur.lua', 'section': m.group(1), 'key': m.group(2), 'value': m.group(3), 'op': 'tp2 writes'})
    for m in RX_GETINI_STRING.finditer(code):
        kind, args = call_info(code, m.end() - 1)
        strs = {i: str_value(a) for i, a in enumerate(args or []) if str_value(a) is not None}
        items.add('setting', f'{m.group(1)}|' + '|'.join(strs.get(i, '?') for i in range(2)), src, m.start(), 'read', strs,
                  {'store': 'EEex/InfinityLoader INI (' + m.group(1) + ')', 'section': strs.get(0, '?'), 'key': strs.get(1, '?'), 'op': 'reads'})
    # i) requirements (WeiDU)
    if weidu:
        for kind, rx in RX_REQ:
            for m in rx.finditer(code):
                text = re.sub(r'\s+', ' ', m.group(0))
                ok = patched_by_patch_mod(m.group(0))
                key = f'{kind} {m.group(1)} {m.group(2)}'.strip()
                items.add('requirement', key, src, m.start(), kind, None, {'patched': 'yes' if ok else 'no', 'text': text[:120]})
    # d) opcodes
    for m in RX_OPCODE_ANY.finditer(code):
        a = max(code.rfind('LPF', 0, m.start()), code.rfind('LAUNCH_PATCH_FUNCTION', 0, m.start()),
                code.rfind('LAF', 0, m.start()), code.rfind('{', 0, m.start()), m.start() - 400)
        b = code.find('END', m.end())
        if src.lua:
            b = code.find('}', m.end())
        b = b if 0 <= b - m.end() < 600 else m.end() + 300
        params = {}
        for pm in RX_EFF_PARAM.finditer(code[a:b]):
            k = pm.group(1).lower()
            if k not in ('opcode', 'match_opcode', 'effectid') and k not in params:
                params[k] = pm.group(2).strip('~"\'')[:40]
        func = re.search(r'(?:LPF|LAF|LAUNCH_PATCH_FUNCTION|LAUNCH_ACTION_FUNCTION)\s+~?(\w+)~?', code[a:m.start()])
        shape = ' '.join(f'{k}={params[k]}' for k in sorted(params)) or '-'
        items.add('opcode', m.group(1), src, m.start(), shape, None,
                  {'via': (func.group(1) if func else ('lua' if src.lua else 'weidu')),
                   'match': 'match' in code[m.start():m.end()].lower()})
    # e) IDS appends
    for m in RX_IDS_APPEND.finditer(code):
        f, row = m.group(1).upper(), re.sub(r'%TAB%|%WNL%|%LNL%', ' ', m.group(2)).strip()
        p = row.split()
        num = int(p[0], 0) if p and re.fullmatch(r'0x[0-9a-f]+|\d+', p[0], re.I) else None
        # Extender-relevant rows only: STATS.IDS, X-* tables, SPLSTATE.IDS beyond 255, script IDS rows naming EEex.
        if f in ('SPELL.IDS',) or (f == 'SPLSTATE.IDS' and not (num and num > 255)) or \
                (f in ('ACTION.IDS', 'TRIGGER.IDS', 'OBJECT.IDS') and 'eeex' not in row.lower()):
            continue
        extra = {'row': row[:80]}
        if f == 'STATS.IDS' and p and re.fullmatch(r'\d+', p[0]):
            extra['extended'] = int(p[0]) > 202
            key = f'STATS.IDS {p[1] if len(p) > 1 else "?"}'
        else:
            key = f'{f} {p[1] if len(p) > 1 and re.fullmatch(r"[\dx]+", p[0], re.I) else p[0]}'
        items.add('ids', key, src, m.start(), 'append', None, extra)
    # c) methods and fields (Lua side, and Lua chunks in WeiDU strings for fields)
    assigns = {v: class_of_call(c) for v, c in RX_ASSIGN_CALL.findall(code) if class_of_call(c)}
    if src.lua:
        for m in RX_METHOD_CALL.finditer(code):
            recv, meth = m.group(1), m.group(2)
            base = re.split(r'[.\[]', recv)[0]
            if base in SKIP_RECEIVERS or meth in sm.LUA_METHODS_BUILTIN or meth in mod_methods:
                continue
            if src.in_string(m.start()):
                continue
            strong = base in assigns
            cls = class_of_receiver(recv, assigns) or ('|'.join(sorted(side['method_class'][meth])) if meth in side['method_class'] else None)
            kind, args = call_info(code, m.end() - 1)
            shape, strs = shape_of(kind, args)
            items.add('method', meth, src, m.start(), shape, strs,
                      {'class': cls or '?', 'receiver': base, 'class_from': 'EEex getter' if strong else ('name' if cls else '?')})
    for m in RX_FIELD_TOKEN.finditer(code):
        tok = m.group(0)
        segs = [s for s in re.split(r'\.', re.sub(r'\[[^\]]*\]', '', tok))]
        recv = segs[0]
        if not recv and m.start() > 0 and code[m.start() - 1] == ')':
            o = code.rfind('(', 0, m.start())
            cm = re.search(r'(\w+)\s*$', code[max(0, o - 80):o])
            recv = 'call:' + cm.group(1) if cm else ''
        cls = class_of_call(recv[5:]) if recv.startswith('call:') else class_of_receiver(recv, assigns) if recv else None
        # Only a class known from an EEex getter can say a field is not on that class (names are a weak hint).
        strong = recv.startswith('call:') or recv in assigns
        chain = [mm.group(0) if mm else s for s, mm in ((s, re.match(r'm_\w+', s)) for s in segs[1:] if s)]
        cur = cls
        for i, s in enumerate(chain):
            if not s.startswith('m_'):
                break
            known_on = None
            if cur:
                ft = field_type(side, cur, s)
                known_on = cur if ft is not None else None
            items.add('field', s, src, m.start(), None, None,
                      {'class': cur or '?', 'chain': '.'.join(chain[:i + 1])[:80],
                       'on_class': 'yes' if known_on else ('no' if cur and strong else '?')})
            if cur:
                ft = field_type(side, cur, s) or ''
                mm = re.match(r'(?:struct|ptr|obj):(\w+)', ft)
                cur = mm.group(1) if mm else None
    # menus
    for m in RX_MENU_USE.finditer(code):
        items.add('menu', m.group(2), src, m.start(), m.group(1), None, {'via': m.group(1), 'mod_defined': m.group(2) in mod_menus})
    # module flags
    for m in re.finditer(r'EEex_Modules\s*\[\s*["\'](\w+)["\']\s*\](\s*=(?!=)\s*(\w+))?', code):
        items.add('module_flag', m.group(1), src, m.start(), 'write ' + m.group(3) if m.group(2) else 'read', None,
                  {'value': m.group(3) or 'read'})
    windows = [code] if src.path.name.lower() == 'eeex_modules.lua' else \
        [code[w.start():w.start() + 1500] for w in re.finditer(r'EEex_Modules\.lua', code, re.I)] if weidu else []
    for w in windows:
        for m in RX_MODULE_FLAG.finditer(w):
            items.add('module_flag', m.group(1), src, None, 'write ' + m.group(2), None, {'value': m.group(2)})
    # g) settings from Lua: Infinity_Get/SetINIValue, EEex_Options_*
    if src.lua or weidu:
        for m in RX_INI_CALL.finditer(code):
            op = m.group(1)
            if code[m.end() - 1] == '(':
                body = balanced(code, m.end() - 1)
                args = split_top(body) if body is not None else []
            else:  # pcall(Infinity_GetINIValue, a, b, c)
                o = code.rfind('(', 0, m.start())
                body = balanced(code, o)
                args = (split_top(body) if body is not None else [])[1:]
            if not args:
                continue
            sec = str_value(args[0]) if args else None
            key = str_value(args[1]) if len(args) > 1 else None
            third = args[2].strip() if len(args) > 2 else None
            sec_s = sec if sec is not None else '<' + args[0][:40] + '>'
            key_s = key if key is not None else '<' + (args[1][:40] if len(args) > 1 else '?') + '>'
            items.add('setting', f'Baldur.lua|{sec_s}|{key_s}', src, m.start(), op.lower(), None,
                      {'store': 'Baldur.lua', 'section': sec_s, 'key': key_s, 'op': op.lower() + 's',
                       ('default' if op == 'Get' else 'value'): (third or '-')[:40]})
        for m in re.finditer(r'\bEEex_Options_Register\s*\(', code):
            body = balanced(code, m.end() - 1)
            if body is None:
                continue
            args = split_top(body)
            oid = str_value(args[0]) if args else None
            oid = oid if oid is not None else '<' + (args[0][:40] if args else '?') + '>'
            rest = ','.join(args[1:])
            got = {k.lower(): v.strip()[:40] for k, v in re.findall(
                r'\[?["\']?(default|section|key|min|max)["\']?\]?\s*=\s*([^,}\n]+)', rest)}
            sec = str_value(got.get('section', '')) or got.get('section', '?')
            key = str_value(got.get('key', '')) or got.get('key', '?')
            if sec == '?' and key == '?':  # a storage of the mod's own (no section/key): name the row by option id
                sec, key = '(custom storage)', oid
            items.add('setting', f'EEex_Options|{sec}|{key}', src, m.start(), 'register', {0: oid},
                      {'store': 'EEex_Options', 'section': sec, 'key': key, 'option_id': oid, 'default': got.get('default', '?'),
                       'range': f"{got.get('min', '?')}..{got.get('max', '?')}", 'op': 'registers',
                       'storage': (re.search(r'EEex_Options_\w*Storage', rest) or re.search('$', '')).group(0) or 'none'})


def analyze_mod(folder, side):
    own = sm.self_defined(folder)
    sources, mod_methods, mod_menus = {}, set(), set()
    mod_files = frozenset(p.name.upper() for p in folder.rglob('*') if p.is_file())
    for path in sorted(folder.rglob('*')):
        if path.is_file() and path.suffix.lower() in sm.LUA_EXT | sm.WEIDU_EXT:
            src = Source(path, path.relative_to(folder).as_posix())
            sources[path] = src
            if src.lua:
                for a, b, c in RX_MOD_METHODS.findall(src.code):
                    mod_methods.add(a or b or c)
            if src.ext == '.menu':
                mod_menus |= set(RX_MENU_DEF.findall(src.code))
    mod_menus = frozenset(mod_menus)
    items, per_file = Items(), {}
    for path, src in sources.items():
        fi = Items()
        analyze_source(src, fi, side, own, mod_methods, mod_menus, mod_files)
        per_file[path] = fi
        items.merge(fi)
    for path in folder.rglob('*'):
        if path.is_file() and path.suffix.lower() in DOC_EXT and path.stat().st_size < 2_000_000:
            text = path.read_text(encoding='latin-1', errors='replace')
            for m in RX_DOC_VERSION.finditer(text):
                if re.search(r'\beeex\b', m.group(0), re.I):
                    items.add('requirement', 'doc: EEex ' + m.group(1).strip(), None, None, None, None,
                              {'patched': 'n/a (readme)', 'text': m.group(0)[:100]})
    # Components: the keys their tp2 block (with its includes) and their own Lua files use.
    comps = []
    for tp2, cid, lab, block, files in sm.component_blocks(folder):
        ci = Items()
        analyze_source(Source(tp2, tp2.relative_to(folder).as_posix(), block, '.tp2'), ci, side, own, mod_methods, mod_menus, mod_files)
        for f in files:
            ci.merge(per_file[f] if f in per_file else Items())
        name = re.search(r'BEGIN\s+(@-?\d+|~[^~]*~|"[^"]*")', block)
        comps.append({'tp2': tp2.name, 'component': cid, 'label': lab, 'begin': name.group(1)[:80] if name else '',
                      'lua_files': sorted(f.name for f in files), 'uses': ci.keys()})
    meta = tp2_meta(folder)
    return items, own, comps, meta, len(sources)


def tp2_meta(folder):
    versions, authors, games = set(), set(), set()
    for tp2 in folder.rglob('*.tp2'):
        t = sm.read_code(tp2)
        versions |= set(re.findall(r'^\s*VERSION\s+[~"]([^~"]+)[~"]', t, re.M))
        authors |= set(re.findall(r'^\s*AUTHOR\s+[~"]([^~"]+)[~"]', t, re.M))
        for g in re.findall(r'GAME_IS\s+[~"]([^~"]+)[~"]', t):
            games |= set(g.lower().split())
    return {'tp2_version': sorted(versions)[:4], 'tp2_author': sorted(authors)[:3], 'game_is': sorted(games)}


# ---------------------------------------------------------------------------------------------------------------
# Status


def status(cat, key, rec, side):
    ex = rec['extra']
    if cat in ('eeex', 'listener', 'hard'):
        if sm.HARD.fullmatch(key) and key in side['defined']:
            return 'provided', 'IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own'
        if sm.HARD.fullmatch(key):
            return 'unsupported', 'x64 asm / hooks / raw memory'
        if key in side['partial']:
            return 'partial', side['partial'][key]
        if key in side['defined']:
            return 'provided', ''
        if ex.get('own') == {True}:
            return 'own', 'defined by the mod itself'
        if key in side['script'] and (ex.get('side') or {'lua'}) <= {'weidu', 'lua-string'}:
            return 'script', 'IDS entry in IEX.tp2'
        return 'missing', ''
    if cat == 'method':
        if key in side['defined'] or key in side['method_class']:
            return ('partial', side['partial'][key]) if key in side['partial'] else ('provided', '')
        cls = ex.get('class', set()) - {'?'}
        strong = 'EEex getter' in ex.get('class_from', set())
        if key[:1].isupper() and not strong and not key.startswith('virtual_'):
            return 'tolua', 'engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e)'
        if strong or key.startswith('virtual_') or (cls and key[:1].islower()):
            return 'missing', 'on ' + '/'.join(sorted(cls) or ['?']) + ' objects'
        return 'unknown', 'receiver class not inferred (mod code or engine object)'
    if cat == 'field':
        if ex.get('on_class') and 'no' in ex['on_class'] and key in side['fields']:
            return 'partial', 'known on ' + '/'.join(sorted(side['field_classes'].get(key, ())))[:80] + ', not on ' + '/'.join(sorted(ex['class'] - {'?'}))[:60]
        return ('provided', '') if key in side['fields'] else ('missing', '')
    if cat == 'opcode':
        return ('provided', '') if key in side['opcodes'] else ('missing', '')
    if cat == 'ids':
        name = key.split()[-1]
        if key.startswith('STATS.IDS'):
            return 'provided', 'X-STATS.2DA + opcode 401 (IEX)'
        if ' ' in key:
            return 'mod data', 'the mod appends it'
        return ('provided', '') if name in side['script'] else ('missing', 'no IDS entry in IEX.tp2')
    if cat == 'datafile':
        k = key.upper()
        if ex.get('mod_file') == {True}:
            return 'mod data', 'file of the mod itself'
        if ex.get('op') == {'LUA'} and not re.match(r'X-|EEEX\.|INFINITYLOADER\.|M___EEEX', k):
            return 'info', 'named only in Lua code (runtime file or module name)'
        if k in side['datafiles']:
            return 'provided', 'IEX.tp2 installs it'
        if k in side['lua_files']:
            return 'partial', 'IEX ships it in IEX/, not override (probes need patch_mod.py)'
        if k in ('EEEX.DLL', 'EEEX.DB', 'EEEX.EXE', 'INFINITYLOADER.EXE', 'INFINITYLOADER.DB', 'INFINITYLOADER.DLL'):
            return 'missing', 'EEex binary probe (IEX has IEX.dll / IEXLauncher.exe)'
        if k in ('EEEX.INI', 'INFINITYLOADER.INI'):
            return ('provided', '') if (k == 'EEEX.INI' and side['reads_eeex_ini']) or (k == 'INFINITYLOADER.INI' and side['reads_loader_ini']) else ('missing', 'IEX does not read it')
        return 'missing', ''
    if cat == 'menu':
        if True in ex.get('mod_defined', set()):
            return 'mod data', 'defined by the mod'
        if re.match(r'(?i)eeex|b3', key):
            return 'missing', 'EEex menu (IEX ships no .menu)'
        return 'game', 'game UI menu (UI.MENU) or defined at runtime'
    if cat == 'label':
        base = re.sub(r'^Hook-|^Data-', '', key)
        base = re.sub(r'\(\).*$', '', base)
        if base in side['symbols'] or base.split('::')[0] in side['types'] and key.startswith(('CBaldurChitin::m_', 'CInfGame::m_')):
            return 'partial', 'engine function known to IEX (engine description); EEex hook / label semantics not provided'
        return 'unsupported', 'EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent'
    if cat == 'module_flag':
        return 'missing', 'IEX has no EEex_Modules switches'
    if cat == 'hard':
        return 'unsupported', 'native IEX feature needed'
    if cat == 'requirement':
        p = ex.get('patched', set())
        if 'yes' in p:
            return 'patched', 'tools/compat/patch_mod.py rewrites it'
        if p & {'n/a (runtime)', 'n/a (readme)'}:
            if key.startswith('Lua: '):
                n = key[5:]
                return ('provided', '') if n in side['defined'] else ('missing', '')
            return 'info', ''
        return 'unpatched', 'not rewritten by patch_mod.py'
    if cat == 'setting':
        store = next(iter(ex.get('store', {'?'})))
        if store == 'Baldur.lua':
            return 'same', 'engine INI (Baldur.lua), identical under EEex and IEX'
        if store == 'EEex_Options':
            return 'partial', 'IEX: ' + side['options_storage'] + '; no options screen'
        if store in ('EEex.ini', 'InfinityLoader.ini'):
            ok = side['reads_eeex_ini'] if store == 'EEex.ini' else side['reads_loader_ini']
            return ('provided', '') if ok else ('missing', 'IEX does not read ' + store)
        return 'missing', ''
    return 'unknown', ''


# ---------------------------------------------------------------------------------------------------------------
# Output


def jsonable(rec):
    out = {'uses': rec['uses'], 'files': sorted(rec['files'])[:20],
           'shapes': dict(rec['shapes'].most_common(30)),
           'strargs': {k: sorted(v) for k, v in rec['strargs'].items()},
           'examples': list(rec['examples'].values())}
    for k, v in rec['extra'].items():
        out[k] = sorted(str(x) for x in v)[:40]
    return out


CATS = ['eeex', 'override', 'listener', 'method', 'field', 'opcode', 'ids', 'datafile', 'menu', 'module_flag', 'setting', 'hard', 'label',
        'requirement']
CAT_TITLE = {'eeex': 'EEex functions, tables and constants', 'override': 'EEex internal hook functions the mod replaces', 'listener': 'Listeners registered', 'method': 'Engine-object methods',
             'field': 'Engine fields', 'opcode': 'EEex opcodes 400-409', 'ids': 'Script IDS entries and IDS / 2DA appends',
             'datafile': 'EEex data and Lua files', 'menu': 'Menus used', 'module_flag': 'EEex_Modules switches',
             'setting': 'Settings (option keys)', 'hard': 'Hard usage (asm / hooks / raw memory)',
             'label': 'Engine symbols / hook labels named in strings', 'requirement': 'EEex requirement checks'}


RX_INTERNAL = re.compile(r'_Hook_|_Private_|Listeners$|^EEex_On[A-Z]')


def _store(api, mrec, label, cat, key, rec, st, note):
    j = jsonable(rec)
    j['iex_status'], j['iex_note'] = st, note
    mrec['items'].setdefault(cat, {})[key] = j
    a = api[cat].setdefault(key, {'mods': [], 'uses': 0, 'shapes': collections.Counter(), 'examples': [],
                                  'strargs': collections.defaultdict(set), 'statuses': collections.Counter(), 'notes': set(),
                                  'extra': collections.defaultdict(set)})
    a['mods'].append(label)
    a['uses'] += rec['uses']
    a['shapes'].update(rec['shapes'])
    a['statuses'][st] += 1
    if note:
        a['notes'].add(note)
    for k, v in rec['strargs'].items():
        if len(a['strargs'][k]) < MAX_STRARGS:
            a['strargs'][k] |= set(list(v)[:MAX_STRARGS - len(a['strargs'][k])])
    for ex in rec['examples'].values():
        if len(a['examples']) < 2 * MAX_EXAMPLES:
            a['examples'].append(dict(ex, mod=label))
    for k, v in rec['extra'].items():
        a['extra'][k] |= {str(x) for x in v}


def build(corpus_path, mods_dir):
    corpus = json.loads(pathlib.Path(corpus_path).read_text(encoding='utf-8'))
    side = iex_side()
    mods, api = {}, collections.defaultdict(dict)
    for label, meta in corpus['mods'].items():
        folder = pathlib.Path(mods_dir) / label
        folder = folder / 'src' if (folder / 'src').is_dir() else folder
        if not folder.is_dir():
            print('missing folder', folder)
            continue
        items, own, comps, tmeta, nfiles = analyze_mod(folder, side)
        mrec = {'name': meta.get('name', label), 'author': meta.get('author') or ', '.join(tmeta['tp2_author']),
                'version': meta.get('version') or ', '.join(tmeta['tp2_version']), 'url': meta.get('url', ''),
                'kind': meta.get('kind', ''), 'games': meta.get('games') or ' '.join(tmeta['game_is']) or '?',
                'files': nfiles, 'self_defined': sorted(own), 'components': comps, 'items': {}}
        for cat in CATS:
            for key, rec in items.d.get(cat, {}).items():
                st, note = status(cat, key, rec, side)
                if cat in ('eeex', 'listener') and key in own:
                    if cat == 'eeex' and RX_INTERNAL.search(key):
                        orec = dict(rec, extra=dict(rec['extra'], replaced_by_mod={True}))
                        _store(api, mrec, label, 'override', key, orec, *(('provided', 'IEX defines it: check IEX calls it at the same moment')
                                                                           if key in side['defined'] else
                                                                           ('missing', 'EEex internal hook the mod replaces; IEX never calls it')))
                    continue
                _store(api, mrec, label, cat, key, rec, st, note)
        mods[label] = mrec
        print(f'{label}: {nfiles} files, ' + ', '.join(f'{c} {len(mrec["items"].get(c, {}))}' for c in CATS))
    api_out = {}
    for cat, d in api.items():
        api_out[cat] = {}
        for key, a in sorted(d.items(), key=lambda x: (-len(x[1]['mods']), -x[1]['uses'], x[0])):
            st = a['statuses'].most_common(1)[0][0]
            api_out[cat][key] = {'mods': sorted(a['mods']), 'mod_count': len(a['mods']), 'uses': a['uses'], 'iex_status': st,
                                 'iex_notes': sorted(a['notes'])[:5], 'shapes': dict(a['shapes'].most_common(40)),
                                 'strargs': {k: sorted(v) for k, v in a['strargs'].items()}, 'examples': a['examples'],
                                 **{k: sorted(v)[:40] for k, v in a['extra'].items() if k not in ('own',)}}
    return {'schema': 1, 'generated': datetime.date.today().isoformat(), 'iex_version': side['version'],
            'scan_rules_version': 5, 'tool': 'tools/compat/inventory.py', 'corpus_size': len(mods),
            'iex': {'eeex_names': len(side['defined']), 'script_names': sorted(side['script']), 'fields': len(side['fields']),
                    'opcodes': sorted(side['opcodes']), 'datafiles': sorted(side['datafiles']),
                    'reads_eeex_ini': side['reads_eeex_ini'], 'reads_infinityloader_ini': side['reads_loader_ini'],
                    'options_storage': side['options_storage'], 'partial': side['partial']},
            'excluded': corpus.get('excluded', {}), 'api': api_out, 'mods': mods}, side


def md_escape(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def render_md(inv):
    L = ['<!-- generated by tools/compat/inventory.py: everything below this line is rewritten -->', '',
         f"Generated {inv['generated']} by `tools/compat/inventory.py` (IEX {inv['iex_version']}, scan rules v5), corpus "
         f"{inv['corpus_size']} mods.", '']
    api = inv['api']
    # Coverage numbers
    L += ['## Coverage summary', '', '| category | distinct items | provided | partial | missing | unsupported | other | '
          'mod-uses covered (provided / all) |', '|---|---|---|---|---|---|---|---|']
    for cat in CATS:
        d = api.get(cat, {})
        c = collections.Counter(v['iex_status'] for v in d.values())
        mu = sum(v['mod_count'] for v in d.values())
        mp = sum(v['mod_count'] for v in d.values() if v['iex_status'] in ('provided', 'script', 'same', 'patched'))
        other = len(d) - c['provided'] - c['partial'] - c['missing'] - c['unsupported']
        L.append(f"| {CAT_TITLE[cat]} | {len(d)} | {c['provided']} | {c['partial']} | {c['missing']} | {c['unsupported']} | "
                 f"{other} | {mp} / {mu} |")
    L += ['', '"other": script (IEX IDS entry), same (engine INI), patched (patch_mod.py), mod data, info, unknown '
          '(method receiver not inferred: tolua engine method or mod code), unpatched.', '']
    # Corpus
    L += ['## Corpus', '', '| mod | name | author | version | games | source | EEex names | missing | hard | components using EEex |',
          '|---|---|---|---|---|---|---|---|---|---|']
    for label, m in inv['mods'].items():
        it = m['items']
        miss = sum(1 for c in ('eeex', 'listener', 'field', 'opcode', 'ids', 'module_flag') for v in it.get(c, {}).values() if v['iex_status'] == 'missing')
        hard = sum(v['uses'] for v in it.get('hard', {}).values())
        ncomp = sum(1 for c in m['components'] if any(c['uses'].get(k) for k in ('eeex', 'hard', 'opcode', 'ids', 'requirement', 'setting')))
        L.append(f"| {label} | {md_escape(m['name'])} | {md_escape(m['author'])} | {md_escape(m['version'])[:30]} | {md_escape(m['games'])[:40]} | "
                 f"{m['url']} ({md_escape(m['kind'])}) | {len(it.get('eeex', {}))} | {miss} | {hard or '-'} | {ncomp}/{len(m['components'])} |")
    L += ['', '**Excluded after checking:**', ''] + [f'- {k}: {v}' for k, v in inv['excluded'].items()] + ['']
    # Matrices
    for cat in CATS:
        d = api.get(cat, {})
        L += [f'## {CAT_TITLE[cat]} ({len(d)})', '']
        if cat == 'setting':
            L += ['| store | section | key | mods | ops | default / value | IEX status | notes |', '|---|---|---|---|---|---|---|---|']
            for key, v in d.items():
                store, sec, k = (key.split('|') + ['', '', ''])[:3]
                dv = ', '.join(v.get('default', []) + v.get('value', []))[:60]
                L.append(f"| {md_escape(store)} | {md_escape(sec)} | {md_escape(k)} | {', '.join(v['mods'])} | {', '.join(v.get('op', []))} | "
                         f"{md_escape(dv)} | {v['iex_status']} | {md_escape('; '.join(v['iex_notes']))[:120]} |")
            L.append('')
            continue
        L += ['| item | mods | uses | IEX status | used by | argument shapes (top) | notes |', '|---|---|---|---|---|---|---|']
        if cat == 'menu':
            c = collections.Counter(v['iex_status'] for v in d.values())
            L[-2:-2] = [f"{c['mod data']} defined by the mods themselves, {c['game']} game UI menus (or created at runtime); "
                        'only the others are listed (all are in inventory.json).', '']
        for key, v in d.items():
            if cat == 'menu' and v['iex_status'] in ('mod data', 'game'):
                continue
            shapes = ', '.join(f'`{md_escape(s)[:60]}`×{n}' for s, n in list(v['shapes'].items())[:3])
            notes = '; '.join(v['iex_notes'])
            if cat == 'method':
                notes = 'class ' + '/'.join(v.get('class', [])) + ('; ' + notes if notes else '')
            if cat == 'field':
                notes = 'class ' + '/'.join(v.get('class', []))[:60] + ('; ' + notes if notes else '')
            if cat == 'hard':
                notes = ('labels: ' + ', '.join(v.get('labels', [])[:6])) if v.get('labels') else notes
            if cat == 'opcode':
                notes = 'via ' + ', '.join(v.get('via', [])[:6])
            if cat == 'requirement':
                notes = notes or ', '.join(v.get('text', [])[:1])
            used = ', '.join(v['mods'])
            L.append(f"| `{md_escape(key)}` | {v['mod_count']} | {v['uses']} | {v['iex_status']} | {used} | {shapes} | {md_escape(notes)[:160]} |")
        L.append('')
    # Per mod
    L += ['## Per mod', '']
    for label, m in inv['mods'].items():
        it = m['items']
        L += [f"### {label} ({md_escape(m['name'])})", '',
              f"{m['url']} ({md_escape(m['kind'])}); version {md_escape(m['version']) or '?'}; games {md_escape(m['games'])}; "
              f"{m['files']} Lua/WeiDU files; {len(m['components'])} components.", '']
        req = it.get('requirement', {})
        checks = sorted(k for k in req if not k.startswith('doc: '))
        docs = sorted({k[len('doc: EEex '):] for k in req if k.startswith('doc: ')})
        if checks or docs:
            L.append('- **EEex version / detection**: ' + (', '.join(f"`{md_escape(k)}` ({req[k]['iex_status']})" for k in checks) or 'no check')
                     + (f"; readme mentions EEex {', '.join(docs[:12])}" if docs else ''))
        for cat in CATS:
            if cat == 'requirement':
                continue
            d = it.get(cat, {})
            if not d:
                continue
            miss = [k for k, v in d.items() if v['iex_status'] in ('missing', 'unsupported', 'partial', 'unpatched')]
            L.append(f"- **{CAT_TITLE[cat]}**: {len(d)}" + (f"; not covered: {', '.join('`' + md_escape(k) + '`' for k in sorted(miss)[:30])}"
                                                             + (' ...' if len(miss) > 30 else '') if miss else ''))
        gaps = [c for c in m['components'] if any(
            m['items'].get(cat, {}).get(k, {}).get('iex_status') in ('missing', 'unsupported') for cat in ('eeex', 'hard', 'opcode', 'ids', 'listener') for k in c['uses'].get(cat, []))]
        if gaps:
            L.append('- **components with gaps**: ' + ', '.join(f"{c['tp2']}#{c['component']}" for c in gaps[:40]))
        L.append('')
    return '\n'.join(L) + '\n'


def main():
    args = dict(zip(sys.argv[1::2], sys.argv[2::2]))
    inv, _ = build(args['--corpus'], args['--mods'])
    out = pathlib.Path(args['--json'])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(inv, indent=1, sort_keys=False), encoding='utf-8')
    md = pathlib.Path(args['--md'])
    head = ''
    if md.exists():
        text = md.read_text(encoding='utf-8')
        cut = text.find('<!-- generated by tools/compat/inventory.py')
        head = text[:cut] if cut >= 0 else text + '\n'
    md.write_text(head + render_md(inv), encoding='utf-8')
    print(f"{inv['corpus_size']} mods -> {out} ({out.stat().st_size // 1024} KB), {md}")


if __name__ == '__main__':
    main()
