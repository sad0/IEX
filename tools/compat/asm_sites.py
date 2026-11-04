#!/usr/bin/env python3
"""Builds IEX-data/inventory/asm_sites.json from the per-mod asm patch catalogues.

Inputs (all IEX-data, written from the mods' own code only, see docs/CLEAN_ROOM.md):
  inventory/asm_catalogue/cat_*.json   one record per engine patch request of a mod
  engine/win/win_functions.jsonl       Windows 2.7.3 function ranges (Ghidra export)
  engine/win64-bg2ee-2.7.3.symbols.json, engine/win/verified_*.json   Windows -> Linux symbol matches

Output: inventory/asm_sites.json = {sites: [...], points: {...}, coverage: {...}} and a coverage summary on stdout.
Each site gets: its engine function (Windows rva + symbol, Linux address when matched) and its hook point (the
engine moment IEX implements once, natively; POINTS below). The router (lua/IEX_HookRequests.lua) reads the
generated lua/IEX_AsmSites.lua table (written by --lua) to bind a mod's request to a point.
"""
import argparse
import bisect
import glob
import json
import os
import re
import sys

DATA = os.environ.get('IEX_DATA', 'E:/Dev/IEX-data')
BASE = 0x140000000

# ---- hook points --------------------------------------------------------------------------------------------
# id (= the IEX runtime name, src/core/hook_points.h) -> (category, engine moment, status).
# status: native = implemented in the hook-point registry; feature = covered by an IEX feature installed at startup
# (a whole behaviour, not a per-call listener); todo = not implemented yet; n/a = nothing IEX can or should do.
POINTS = {
    'hitRoll':           ('attack', 'CGameSprite::Hit: d20 attack roll (0..19)', 'native'),
    'toHitTotal':        ('attack', 'CGameSprite::Hit: right-hand to-hit total, final', 'native'),
    'critThreshold':     ('attack', 'CGameSprite::Hit: critical threshold (CDerivedStats::GetCriticalValue)', 'native'),
    'critBlocked':       ('attack', 'CGameSprite::Hit: helmet-stopped critical keeps flag 2', 'native'),
    'attackResult':      ('attack', 'CGameSprite::Hit: hit / miss', 'native'),
    'damageRoll':        ('attack', 'CGameSprite::Damage: weapon damage roll + bonus', 'native'),
    'critMultiplier':    ('attack', 'CGameSprite::Damage: critical multiplier', 'native'),
    'strengthToHit':     ('attack', 'strength to-hit bonus (Stick HitStrMod: defined, never registered)', 'n/a'),
    'attackIndex':       ('swing', 'CGameSprite::Swing: attack index of the attack frame', 'native'),
    'attackCancel':      ('swing', 'CGameSprite::Swing: cancel the attack frame', 'native'),
    'keepAmmo':          ('swing', 'CGameSprite::Swing: CItem::SetUsageCount after a shot', 'native'),
    'afterSwingOp248':   ('swing', 'EEex Lua hook EEex_Opcode_Hook_OnAfterSwingCheckedOp248 (Lua override, no patch)', 'todo'),
    'backstabCheck':     ('attack', 'CGameSprite::Damage backstab: invisibility / position / immunity checks + decision', 'todo'),
    'backstabSuccess':   ('attack', 'CGameSprite::Damage backstab applied', 'todo'),
    'casterSchoolSpell': ('save', 'CSpell::GetAbilityEffect: caster school (save penalty)', 'native'),
    'casterSchoolItem':  ('save', 'CItem::GetAbilityEffect: caster school (save penalty)', 'native'),
    'targetSchool':      ('save', 'CGameEffect::CheckSave: target school (save bonus)', 'native'),
    'hideInSight':       ('stealth', 'CGameSprite::Hide: hiding while seen', 'native'),
    'lastingModes':      ('modal', 'modal states not cancelled by actions / buttons / moving; no per-round feedback', 'native'),
    'stealthReveals':    ('modal', 'stealth reveal rules', 'native'),
    'findTrapsButton':   ('modal', 'Find Traps action bar button', 'native'),
    'actionButtonL':     ('ui', 'CInfButtonArray::OnLButtonPressed(index)', 'native'),
    'actionButtonR':     ('ui', 'CInfButtonArray::OnRButtonPressed(index)', 'native'),
    'classDone':         ('chargen', 'CScreenCreateChar: class step completed', 'native'),
    'profMaxUI':         ('chargen', 'UpdateProficienciesPanel: maximum shown (the table''s max field)', 'native'),
    'profMax':           ('chargen', 'OnProficiencyPlusMinusButtonClick: maximum a + may reach (GetClassProficiency)', 'native'),
    'respecGear':        ('chargen', 'CompleteCharacterSkills: starting gold / weapon', 'native'),
    'groundMoveClick':   ('world', 'CGameArea::OnActionButtonClickGround: move click', 'native'),
    'groundContainer':   ('world', 'CGameSprite::UpdateVisibleGroundItems: container in range', 'native'),
    'containerMarker':   ('world', 'CGameContainer::Render: permanent outline color by marker', 'native'),
    'campMarker':        ('worldmap', 'world map: party marker', 'native'),
    'campSameArea':      ('worldmap', 'world map: current area clicked', 'native'),
    'deathDrop':         ('world', 'death effect: inventory dropped', 'native'),
    'smallFootprint':    ('search', 'CSearchBitmap Add/RemoveObject: bumpable creature footprint', 'native'),
    'alliedPassThrough': ('path', 'Pathfinding Redux movement policy: allies pass through allies (search map, walk '
                          'step, bump, route cost, background search snapshot)', 'feature'),
    'pathAttackSpacing': ('path', 'Pathfinding Redux attack spacing: approach slots in Attack / AttackReevaluate', 'todo'),
    'pathPreference':    ('path', 'Pathfinding Redux route preference planner (optional install)', 'todo'),
    'pathSettle':        ('path', 'Pathfinding Redux gentle settle (CMessageStopActions from Lua)', 'todo'),
    'bigParty':          ('party', 'party array / MAX_CHARACTERS past 6 members (SadoEE #40)', 'todo'),
    'partyVision':       ('party', 'fog of war for more than the engine viewer cap', 'feature'),
    'emptyContainerOutline': ('world', 'EEex B3EmptyContainer module hook (highlight outline)', 'feature'),
    'callStub':          ('engine', 'Lua-callable engine functions a mod builds Windows stubs for', 'native'),
    'buildProbe':        ('engine', 'build detection by reading code bytes (no patch)', 'n/a'),
    'bardSpellTable':    ('rules', 'bard spell progression table chosen per kit (CRuleTables)', 'todo'),
    'kitProfColumn':     ('rules', 'CRuleTables::GetProficiencyClassIndex: multiclass kit weapon column', 'todo'),
    'timeStopClock':     ('effects', 'effect timers under Time Stop / Haste (chriz CBRTC gates)', 'todo'),
    'raceString':        ('rules', 'CRuleTables::GetRaceString: extra races', 'todo'),
    'layeredAnimResRef': ('anim', 'CGameAnimationTypeMonsterLayered::GetAnimationResRef: weapon shown', 'todo'),
    'unidentifiedIcon':  ('item', 'CItem icon / ground icon / PushToLua resref of an unidentified item', 'todo'),
    'xpBank':            ('xp', 'XP bank: identity, award, writer, cap, reset, party (mod DLLs)', 'todo'),
    'dualClassProgression': ('xp', 'dual-class progression detours into the mod DLLs', 'todo'),
    'legacyX86':         ('legacy', 'legacy 32-bit EEex patch (2.5 x86 asm): cannot run on x64 2.7.3', 'n/a'),
    'modDll':            ('legacy', "the mod's own DLL detours (MinHook), not an EEex request", 'n/a'),
}

# Router bindings: Windows 2.7.3 patch address -> how the mod's request becomes a listener of a point.
#   args: what the mod's Lua callback receives, from the point's listener arguments:
#         'idN' = object id of argument N (-1 for nil), 'argN' = argument N as is, 'ptrN' = address of argument N,
#         'objN' = argument N (engine object userdata)
#   ret:  'number' (a non-number counts 0; a Lua error or a missing function keeps the engine value),
#         'boolean', 'none'; switch = the point is a switch the request turns on (pure asm patch, no Lua)
#   fn:   the callback name when the mod's GenLuaCall text does not give one
#   label: (name, offset) the address is EEex_Label(name) + offset (runtime label), not a fixed number
#   bridge: the point needs data the request does not carry; the named bridge (lua/IEX_NativeHooks.lua) binds it
BINDINGS = {
    0x14039DE77: {'point': 'hideInSight', 'args': ['arg1'], 'ret': 'boolean', 'fn': 'ST_Hook_HideInPlainSight'},
    0x1403B9B87: {'point': 'attackIndex', 'args': ['id1', 'id2', 'arg3'], 'ret': 'none', 'fn': 'ST_Hook_AttackIndex'},
    0x1403B8A79: {'point': 'attackCancel', 'args': ['id1', 'id2'], 'ret': 'boolean', 'fn': 'ST_Hook_ShouldCancelAttack'},
    0x14039E115: {'point': 'hitRoll', 'args': ['id1', 'id2', 'arg3'], 'ret': 'number', 'fn': 'ST_Hook_HitRoll'},
    0x14039E634: {'point': 'toHitTotal', 'args': ['id1', 'id2', 'arg3'], 'ret': 'number', 'fn': 'ST_Hook_HitMod'},
    0x140390530: {'point': 'damageRoll', 'args': ['id1', 'id2', 'arg3'], 'ret': 'number', 'fn': 'ST_Hook_AttackDamMod'},
    0x14039EBC3: {'point': 'critThreshold', 'args': ['id1', 'id2', 'arg3'], 'ret': 'number', 'fn': 'ST_Hook_CriticalHitMod'},
    0x14039EC58: {'point': 'critBlocked', 'switch': True},
    0x1403912B2: {'point': 'critMultiplier', 'args': ['id1', 'id2', 'arg3'], 'ret': 'number',
                  'fn': 'ST_Hook_CriticalHitMultiplier'},
    0x14039EEEF: {'point': 'attackResult', 'args': ['arg3'], 'ret': 'none', 'fn': 'ST_Hook_AttackResult'},
    0x140263641: {'point': 'actionButtonL', 'args': ['arg1'], 'ret': 'none', 'fn': 'ST_Hook_ButtonPressed'},
    0x140264DEF: {'point': 'actionButtonR', 'args': ['arg1'], 'ret': 'none', 'fn': 'ST_Hook_RButtonPressed'},
    0x14024EF66: {'point': 'casterSchoolSpell', 'args': ['id1', 'ptr2'], 'ret': 'number', 'fn': 'ST_Hook_SaveDCMod'},
    0x1401FB552: {'point': 'casterSchoolItem', 'args': ['id1', 'ptr2'], 'ret': 'number', 'fn': 'ST_Hook_SaveDCMod'},
    0x1401CD85B: {'point': 'targetSchool', 'args': ['id1', 'ptr2'], 'ret': 'number', 'fn': 'ST_Hook_SaveMod'},
    0x1402B92FA: {'point': 'classDone', 'args': ['id1'], 'ret': 'none', 'fn': 'ST_Hook_CharGenClassDone'},
    0x1402C7C41: {'point': 'profMaxUI', 'args': ['arg1', 'arg2'], 'ret': 'number', 'fn': 'ST_Hook_ProficiencyMax'},
    0x1402BE2B1: {'point': 'profMax', 'args': ['arg1', 'arg2'], 'ret': 'number', 'fn': 'ST_Hook_ProficiencyMax'},
    # SadoEE: its EEex_Hook* requests (the rest of its patches are JIT stubs + raw writes: SadoEE bridge)
    0x1403B902A: {'point': 'keepAmmo', 'args': ['obj1', 'obj2'], 'ret': 'boolean', 'fn': 'SQAmmo_Hook_Keep'},
    'SQCONT':    {'point': 'containerMarker', 'label': ('Hook-CGameContainer::Render()-B3EmptyContainer', 0x39),
                  'bridge': 'SadoEE valuable containers'},
}

def load_jsonl(path):
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


class EngineMap:
    def __init__(self):
        self.starts, self.funcs = [], []
        for r in load_jsonl(os.path.join(DATA, 'engine/win/win_functions.jsonl')):
            if r.get('k') != 'fn':
                continue
            for a, b in r['ranges']:
                self.funcs.append((int(a, 16), int(b, 16), int(r['rva'], 16), r['name']))
        self.funcs.sort()
        self.starts = [f[0] for f in self.funcs]
        self.names = {}  # win rva of a function -> (symbol, demangled, linux)
        for s in json.load(open(os.path.join(DATA, 'engine/win64-bg2ee-2.7.3.symbols.json'), encoding='utf-8')):
            self.names[int(s['addr'], 16)] = (s['name'], s.get('demangled', ''), s.get('linux_addr'))
        for f in glob.glob(os.path.join(DATA, 'engine/win/verified_*.json')):
            d = json.load(open(f, encoding='utf-8'))
            if not isinstance(d, list):
                continue
            for v in d:
                if v.get('kind') == 'function' and v.get('win'):
                    try:
                        w = int(v['win'], 16)
                    except ValueError:
                        continue
                    self.names[w] = (v['name'], self.names.get(w, ('', '', None))[1], v.get('linux'))

    def lookup(self, rva):
        i = bisect.bisect_right(self.starts, rva) - 1
        while i >= 0:
            a, b, fn, gname = self.funcs[i]
            if a <= rva < b:
                sym = self.names.get(fn)
                return {'fn_rva': hex(fn), 'fn_offset': hex(rva - fn), 'symbol': sym[0] if sym else gname,
                        'demangled': sym[1] if sym else '', 'linux_fn': sym[2] if sym else None}
            if rva - a > 0x20000:
                break
            i -= 1
        return None


HEX = re.compile(r'0x14[0-9A-Fa-f]{7}')


def parse_address(v):
    if isinstance(v, int):
        return v if v >= BASE else v + BASE
    if not isinstance(v, str):
        return None
    m = HEX.search(v)
    return int(m.group(0), 16) if m else None


# ---- point assignment ---------------------------------------------------------------------------------------
STICK_IDS = [  # hook_id prefix -> point (versions before the 2.7 table use 2.6 addresses)
    ('HideInPlainSight', 'hideInSight'), ('AttackIndex', 'attackIndex'), ('AttackCancel', 'attackCancel'),
    ('ShouldCancelAttack', 'attackCancel'), ('HitRoll', 'hitRoll'), ('HitStrMod', 'strengthToHit'),
    ('HitMod', 'toHitTotal'), ('AttackDamMod', 'damageRoll'), ('DamMod', 'damageRoll'),
    ('CriticalHitMultiplier', 'critMultiplier'), ('CriticalHitMod', 'critThreshold'), ('CriticalHit', 'critBlocked'),
    ('AttackResult', 'attackResult'), ('RButtonPressed', 'actionButtonR'), ('ButtonPressed', 'actionButtonL'),
    ('BackstabSuccess', 'backstabSuccess'), ('Backstab', 'backstabCheck'), ('SaveDCMod', 'casterSchoolSpell'),
    ('SaveMod', 'targetSchool'), ('CharGenClassDone', 'classDone'), ('ProficiencyUIMax', 'profMaxUI'), ('ProficiencyActualMax', 'profMax'),
    ('ProficiencyMax', 'profMax'),
    ('Override_EEex_Opcode_Hook_OnAfterSwingCheckedOp248', 'afterSwingOp248'),
]

STICK_ADDR = {a: b['point'] for a, b in BINDINGS.items() if isinstance(a, int) and b['point'] not in ('keepAmmo',)}
STICK_ADDR.update({
    0x14034CFBD: 'strengthToHit', 0x140390C45: 'backstabCheck', 0x140390CF0: 'backstabCheck',
    0x140390D12: 'backstabCheck', 0x140390D88: 'backstabCheck', 0x140390DD4: 'backstabCheck',
    0x140390DE3: 'backstabSuccess', 0x1402C7C41: 'profMaxUI', 0x1402BE2B1: 'profMax',
})

SADO_FILE_POINT = {
    'M_SQAMMO': 'keepAmmo', 'M_SQATKM': 'groundMoveClick', 'M_SQKEEP': 'deathDrop', 'M_SQCHST': 'groundContainer',
    'M_SQCONT': 'containerMarker', 'M_SQFOOT': 'smallFootprint', 'M_SQRESP': 'respecGear', 'M_SQ0BLD': 'buildProbe',
    'M_PSXP7': 'bigParty', 'M_PSXP7S': 'bigParty', 'M_PSXP7V': 'partyVision',
}

PFR_POLICY = {'MRIP_SearchSnapshot', 'MRIP_YieldCost', 'MRIP_RouteCost', 'MRIP_PassCost', 'MRIP_Tick'}


def assign_point(s):
    mod, kind = s['mod'], s['kind'] or ''
    does = str(s.get('does') or '').lower()
    text = ' '.join(str(s.get(k) or '') for k in ('component', 'feature', 'does', 'engine_hint', 'notes')).lower()
    addr = s.get('address_abs')
    if mod.startswith('stick-lua-functions'):
        if addr in STICK_ADDR and mod.endswith('v0.11.0'):
            return STICK_ADDR[addr]
        hid = s.get('hook_id') or ''
        for k, p in STICK_IDS:
            if hid.startswith(k):
                if p == 'profMax' and 'ui' in hid.lower():
                    return 'profMaxUI'
                if p == 'casterSchoolSpell' and addr == 0x1401FB552:
                    return 'casterSchoolItem'
                return p
        return None
    if mod.startswith('SadoEE/'):
        f = mod.split('/', 1)[1].split(' ')[0]
        if kind == 'call_stub':
            return 'callStub'
        if kind == 'byte_pattern_check':
            return 'buildProbe'
        if f == 'M_SQCONT' and 'module' in kind.lower():
            return 'emptyContainerOutline'
        if f == 'M_SQMODE':
            if 'find traps' in does:
                return 'findTrapsButton'
            if 'stealth' in does or 'reveal' in does or 'hidden' in does:
                return 'stealthReveals'
            return 'lastingModes'
        if f == 'M_SQCAMP':
            return 'campSameArea' if ('current area' in does or 'origin' in does and 'click' in does) else 'campMarker'
        return SADO_FILE_POINT.get(f)
    if mod == 'pathfinding-redux':
        cb = (s.get('lua_callback') or '').split(',')[0].split(' ')[0]
        comp = str(s.get('component') or '').lower()
        if 'preference' in comp:
            return 'pathPreference'
        if 'settle' in comp:
            return 'pathSettle'
        if 'attack spacing' in comp:
            return 'pathAttackSpacing'
        return 'alliedPassThrough'
    if mod == 'chriz-bg-modpack':
        f = (s.get('file') or '').lower()
        if 'cbmid' in f:
            return 'unidentifiedIcon'
        if 'dual' in f:
            return 'dualClassProgression'
        return 'xpBank'
    if mod == 'chriz-bg-rebalance':
        f = s.get('file') or ''
        if 'CBRSP' in f:
            return 'bardSpellTable'
        if 'CBRKP' in f:
            return 'kitProfColumn'
        return 'timeStopClock'
    if mod == 'chriz-playable-races':
        return 'raceString' if 'CBPRRC' in (s.get('file') or '') else 'layeredAnimResRef'
    if mod in ('bgee-graphics-enhanced', 'ie-enhancer'):
        return 'modDll'
    if mod in ('olvynspells', 'high-power-bg'):
        return 'legacyX86'
    return None


def load_catalogues():
    out = []
    for f in sorted(glob.glob(os.path.join(DATA, 'inventory/asm_catalogue/cat_*.json'))):
        d = json.load(open(f, encoding='utf-8'))
        if isinstance(d, dict):
            d = d.get('patches', [])
        for r in d:
            r['catalogue'] = os.path.basename(f)
            out.append(r)
    return out


def family(mod):
    return mod.split('@')[0].split('/')[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(DATA, 'inventory/asm_sites.json'))
    ap.add_argument('--lua', help='also write the router table (lua/IEX_AsmSites.lua)')
    ap.add_argument('--md', help='also refresh the generated part of docs/NATIVE_HOOK_POINTS.md')
    args = ap.parse_args()
    em = EngineMap()
    sites = []
    for r in load_catalogues():
        a = parse_address(r.get('address'))
        r['address_abs'] = a
        s = {k: r.get(k) for k in ('mod', 'component', 'feature', 'hook_id', 'file', 'line', 'shipped', 'registered',
                                   'kind', 'address', 'params', 'expected_bytes', 'lua_callback', 'args', 'returns',
                                   'does', 'engine_hint', 'notes', 'other_builds')}
        s['address_abs'] = hex(a) if a else None
        s['engine'] = em.lookup(a - BASE) if a else None
        s['point'] = assign_point(r)
        sites.append(s)

    # coverage: shipped requests only, mod family level
    cov = {}
    for s in sites:
        if s['shipped'] is False or s.get('registered') is False:
            continue
        p = s['point'] or 'unassigned'
        c = cov.setdefault(p, {'requests': 0, 'mods': set(), 'addresses': set()})
        c['requests'] += 1
        c['mods'].add(family(s['mod']))
        if s['address_abs']:
            c['addresses'].add(s['address_abs'])
    mods_all = sorted({family(s['mod']) for s in sites if s['shipped'] is not False})
    points_out = {}
    for p, c in sorted(cov.items(), key=lambda kv: (-len(kv[1]['mods']), -kv[1]['requests'])):
        cat, moment, status = POINTS.get(p, ('?', '?', 'unassigned'))
        points_out[p] = {'category': cat, 'moment': moment, 'status': status, 'requests': c['requests'], 'mods': sorted(c['mods']),
                         'addresses': len(c['addresses'])}
    # mods fully covered = every shipped request of the mod on a point with status native/feature/n/a
    full = {}
    for m in mods_all:
        ps = {s['point'] for s in sites if family(s['mod']) == m and s['shipped'] is not False
              and s.get('registered') is not False}
        st = [POINTS.get(p, ('', '', 'unassigned'))[2] for p in ps]
        full[m] = {'points': sorted(x or 'unassigned' for x in ps),
                   'covered': all(x in ('native', 'feature', 'n/a') for x in st),
                   'missing': sorted(p or 'unassigned' for p in ps
                                     if POINTS.get(p, ('', '', 'unassigned'))[2] not in ('native', 'feature', 'n/a'))}
    summary = {
        'requests': len(sites), 'shipped': sum(1 for s in sites if s['shipped'] is not False),
        'distinct_addresses': len({s['address_abs'] for s in sites if s['address_abs']}),
        'mapped_to_function': sum(1 for s in sites if s['engine']),
        'with_linux_function': sum(1 for s in sites if s['engine'] and s['engine'].get('linux_fn')),
        'points': len(points_out),
        'points_native': sum(1 for p in points_out.values() if p['status'] in ('native', 'feature')),
        'mods': len(mods_all), 'mods_covered': sum(1 for v in full.values() if v['covered']),
    }
    json.dump({'schema': 1, 'note': 'Generated by tools/compat/asm_sites.py from inventory/asm_catalogue (mods own code).',
               'summary': summary, 'points': points_out, 'mods': full, 'sites': sites},
              open(args.out, 'w', encoding='utf-8'), indent=1)
    print(json.dumps(summary, indent=1))
    for p, v in points_out.items():
        print(f"{p:26s} {v['status']:10s} req={v['requests']:4d} addr={v['addresses']:4d} mods={','.join(v['mods'])}")
    for m, v in full.items():
        print(f"{m:24s} covered={v['covered']} missing={v['missing']}")
    if args.lua:
        write_lua(sites, args.lua)
    if args.md:
        write_md(sites, points_out, full, summary, args.md)


def lua_value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (list, tuple)):
        return '{ ' + ', '.join(lua_value(x) for x in v) + ' }'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'") + "'"


def write_lua(sites, path):
    """Router table (lua/IEX_AsmSites.lua): every known Windows 2.7.3 patch address of the corpus -> its point,
    the point's status, the mods that request it, and the binding when IEX routes it."""
    rows = {}
    for s in sites:
        a = s['address_abs']
        p = s['point']
        k = s['kind'] or ''
        if not a or not p or not (k.startswith('EEex_Hook') or k.startswith('EEex_JITAt')):
            continue
        r = rows.setdefault(int(a, 16), {'point': p, 'mods': set()})
        r['mods'].add(family(s['mod']))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- Generated by tools/compat/asm_sites.py (IEX-data/inventory/asm_sites.json): do not edit.\n')
        f.write('-- Windows 2.7.3 x64 patch address of an EEex_Hook* / EEex_JITAt request -> IEX hook point\n')
        f.write('-- (docs/NATIVE_HOOK_POINTS.md). status: native / feature / todo / n/a. bind: how lua/IEX_HookRequests.lua\n')
        f.write('-- turns the request into a listener (args / ret / fn / switch / bridge).\n')
        f.write('IEX_AsmSites = {\n')
        for a in sorted(rows):
            r = rows[a]
            st = POINTS.get(r['point'], ('', '', 'todo'))[2]
            b = BINDINGS.get(a)
            line = "\t[0x%X] = { point = '%s', status = '%s', mods = '%s'" % (a, r['point'], st, ','.join(sorted(r['mods'])))
            if b:
                line += ', bind = {' + ', '.join('%s = %s' % (k, lua_value(v)) for k, v in b.items() if k != 'point') + ' }'
            f.write(line + ' },\n')
        f.write('}\n')
        f.write('-- Requests at an address computed from a runtime label: EEex_Label(name) + offset.\n')
        f.write('IEX_AsmLabelSites = {\n')
        for k, b in BINDINGS.items():
            if isinstance(k, str) and 'label' in b:
                st = POINTS.get(b['point'], ('', '', 'todo'))[2]
                f.write("\t{ label = %s, offset = %d, point = '%s', status = '%s', bind = {%s} },\n" % (
                    lua_value(b['label'][0]), b['label'][1], b['point'], st,
                    ', '.join('%s = %s' % (kk, lua_value(v)) for kk, v in b.items() if kk not in ('point', 'label'))))
        f.write('}\n')


def write_md(sites, points, mods, summary, path):
    """Replaces the text between the GENERATED markers of the doc with the coverage tables."""
    begin, end = '<!-- GENERATED by tools/compat/asm_sites.py: begin -->', '<!-- GENERATED: end -->'
    out = [begin, '']
    out.append('Corpus: %d patch requests (%d shipped) from %d mods, %d distinct Windows addresses; %d mapped to '
               'their engine function, %d of those to the matching Linux function.' % (
                   summary['requests'], summary['shipped'], summary['mods'], summary['distinct_addresses'],
                   summary['mapped_to_function'], summary['with_linux_function']))
    st = {}
    for p, v in points.items():
        st.setdefault(v['status'], []).append(p)
    req_by = {k: sum(points[p]['requests'] for p in v) for k, v in st.items()}
    out.append('')
    out.append('| status | points | requests |')
    out.append('|---|---|---|')
    for k in ('native', 'feature', 'todo', 'n/a', 'unassigned'):
        if k in st:
            out.append('| %s | %d | %d |' % (k, len(st[k]), req_by[k]))
    out.append('')
    out.append('### Hook points (most requested first)')
    out.append('')
    out.append('| point | category | status | requests | addresses | mods | engine function (Windows rva / Linux) | moment |')
    out.append('|---|---|---|---|---|---|---|---|')
    for p, v in points.items():
        ex = [s for s in sites if s['point'] == p and s['engine']]
        fns = []
        for s in ex:
            e = s['engine']
            name = e['demangled'] or e['symbol']
            t = '%s (%s / %s)' % (name.split('(')[0], e['fn_rva'], e['linux_fn'] or '-')
            if t not in fns:
                fns.append(t)
        f = '; '.join(fns[:3]) + (' +%d' % (len(fns) - 3) if len(fns) > 3 else '')
        out.append('| `%s` | %s | %s | %d | %d | %s | %s | %s |' % (p, v['category'], v['status'], v['requests'],
                                                              v['addresses'], ', '.join(v['mods']), f or '-', v['moment']))
    out.append('')
    out.append('### Mods')
    out.append('')
    out.append('| mod | points | covered | missing points |')
    out.append('|---|---|---|---|')
    for m, v in mods.items():
        out.append('| %s | %d | %s | %s |' % (m, len(v['points']), 'yes' if v['covered'] else 'no',
                                            ', '.join('`%s`' % x for x in v['missing']) or '-'))
    out.append('')
    out.append('### Routed sites (lua/IEX_AsmSites.lua bindings)')
    out.append('')
    out.append('| address | point | mod callback | args | ret |')
    out.append('|---|---|---|---|---|')
    for a, b in BINDINGS.items():
        addr = ('EEex_Label(%s)+0x%X' % b['label']) if 'label' in b else '0x%X' % a
        out.append('| %s | `%s` | %s | %s | %s |' % (addr, b['point'], b.get('fn', '-'), ' '.join(b.get('args', [])) or '-',
                                                 'switch' if b.get('switch') else ('bridge' if b.get('bridge') else b.get('ret', '-'))))
    out.append('')
    out.append(end)
    text = open(path, encoding='utf-8').read() if os.path.exists(path) else begin + '\n' + end + '\n'
    i, j = text.index(begin), text.index(end) + len(end)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text[:i] + '\n'.join(out) + text[j:])


if __name__ == '__main__':
    main()
