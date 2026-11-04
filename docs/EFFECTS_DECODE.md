# Unknown effect opcodes: DecodeEffect and the inert CGameEffect

BG2EE 2.7.3, Linux ELF (VA) and Windows PE (RVA). Data: `IEX-data/engine/win/verified_t1d_effects.json`.
Tool: `tools/match/decodeeffect.py <BaldursGateII> <Baldur.exe> [--json out]` (re-reads the jump tables,
call sites and base vtable).

## The crash

`CGameEffect::DecodeEffect(Item_effect_st*, CPoint const&, int, CPoint const&, int)`
(L `0x1d5c20`, W `0x1de3d0`, static) switches on the `u16` opcode at `Item_effect_st+0`.
Each case does `new(0x158)` plus a derived ctor. The common tail then writes
`effect+0x150 = arg5` and `effect+0x6c = game time`. An opcode with no case keeps `effect = NULL`,
so the tail writes `NULL+0x150`: W `Baldur.exe+0x1e2741` (`mov [rbx+0x150],eax`, inside DecodeEffect),
L `0x1d5c8a`.

Opcodes with no case (same on both builds): **>= 368, 347..359, 364**.

Save-load path on Windows: `CGameSprite::Unmarshal` 0x37a3e0 -> `CGameEffectList::Unmarshal` 0x1e88e0
(V2 branch) -> `CGameEffect::DecodeEffectFromBase` 0x1e2d30 (E8 `0x1e2d9e`) -> DecodeEffect.
Linux inlines DecodeEffectFromBase into Unmarshal (DecodeEffect E8 `0x1e6201`).
DecodeEffectFromBase passes a zeroed `Item_effect_st` that holds only the opcode, then
`CopyFromBase` copies the full 0x108 record over the new effect. All the effect's data comes back
whatever object DecodeEffect returned.

## ABI

| | item | source | sourceId | target | arg5 | ret |
|---|---|---|---|---|---|---|
| Linux | rdi | rsi (`CPoint*`) | edx | rcx (`CPoint*`) | r8d | rax |
| Windows | rcx | rdx (`CPoint*`) | r8d | r9 (`CPoint*`) | [rsp+0x28] | rax |

At entry DecodeEffect also writes back `item+0x20 = 0` when it was -1.

Call sites: Linux 150 E8, Windows 125 E8, listed in the JSON. Nothing is inlined. Most pass a
constant opcode. The data-driven ones are effect-list Unmarshal / DecodeEffectFromBase, CItem
Equip/Unequip/GetAbilityEffect, CSpell GetAbilityEffect/GetCastingEffect, CMessageAddEffect
UnmarshalMessage, CGameEffectFile::GetEffect and CProjectile.

## Base CGameEffect

- Size `0x158` on both builds.
- Ctor `_ZN11CGameEffectC1EP14Item_effect_stRK6CPointiS2_ii`: L `0x1d1c80` (C1 == C2), W `0x19dcb0`.
  Args: `(this, item, CPoint const* source, int sourceId, CPoint target BY VALUE, int flag, int arg6)`.
  - L: rdi, rsi, rdx, ecx, r8 (`x | y<<32`), r9d, [rsp+8].
  - W: rcx, rdx, r8, r9d, [rsp+0x28] qword, [rsp+0x30], [rsp+0x38]. Returns `this`.
  - DecodeEffect's derived ctors pass `flag 0, arg6 -1`. `Copy()` passes `1, -1`.
  - `flag` picks where the dice go (0: +0x54/+0x58).
  - `m_effectId` is at `+0x10` (dword).
- Vtable (address point): L `0xcbccd0` (12 slots, header `[0]`, typeinfo `0xcef408`). W `0x58f020`
  (11 slots, single deleting dtor, no RTTI).
  - `ApplyEffect` returns 1 and does nothing. `OnLoad`/`OnAddSpecific`/`OnRemove` are empty.
    `UsesDice` returns 0. Resolve/OnAdd/CheckSave/DisplayString are the generic ones.
  - **`Copy` returns NULL** (L slot +0x10, W +0x8). `CGameEffect::CheckAdd` (L 0x1ee8c0, W 0x1cc6c0,
    called by `CGameSprite::AddEffect`) calls `Copy()` on its immunity, bounce and turning paths and
    does not check for NULL. So a raw base object is not safe there.
- Save: `CGameEffectList::Marshal` V2 copies `effect+8` for 0x108 bytes as it is, so the opcode and
  every field are saved unchanged. The only opcode range check in the Linux binary is DecodeEffect's.
- Allocator: L `_Znwm` 0xca2d0 / `_ZdlPv` 0xcabb0. W `new` 0x4f7a88 / delete 0x45e690.
- Game time: L `[0xd235a0]+0x10e0 -> +0x3fa0`, W `[0x667548]+0x1090 -> +0x3fa0`.

## Hook

Redirect every DecodeEffect E8 site (`HookCallSite`) to:

```cpp
static bool KnownOpcode(uint16_t op) {
    return op < 0x170 && !(op >= 347 && op <= 359) && op != 364;
}

void* DecodeEffectHook(uint8_t* item, const CPoint* src, int srcId, const CPoint* tgt, int arg5) {
    uint16_t op = *reinterpret_cast<uint16_t*>(item);
    if (KnownOpcode(op))
        return DecodeEffect(item, src, srcId, tgt, arg5);        // original
    if (*reinterpret_cast<int32_t*>(item + 0x20) == -1)
        *reinterpret_cast<int32_t*>(item + 0x20) = 0;
    uint8_t* p = static_cast<uint8_t*>(EngineNew(0x158));
    uint64_t target; std::memcpy(&target, tgt, 8);               // CPoint by value
    BaseCtor(p, item, src, srcId, target, /*flag*/ 0, /*arg6*/ -1);
    *reinterpret_cast<void**>(p) = g_inertVtable;                // see below
    *reinterpret_cast<int32_t*>(p + 0x150) = arg5;
    *reinterpret_cast<int32_t*>(p + 0x6c) = GameTime();
    return p;
}
```

`g_inertVtable` is a copy of the base vtable. On Linux, also copy the 2 header qwords and point at
slot 0. Then replace the `Copy` slot with:

```cpp
void* InertCopy(uint8_t* self) {
    void* item = GetItemEffect(self);                  // L 0x1c6d20, W 0x1e4d50
    uint8_t* p = static_cast<uint8_t*>(EngineNew(0x158));
    uint64_t target; std::memcpy(&target, self + 0x88, 8);
    BaseCtor(p, item, self + 0x80, *reinterpret_cast<int32_t*>(self + 0x110), target, 1, -1);
    *reinterpret_cast<void**>(p) = g_inertVtable;
    EngineDelete(item);                                // W: (item, 0x30)
    CopyFromBase(p, self + 8);                         // L 0x1c63a0, W 0x1dcaf0
    return p;
}
```

Windows `InertCopy` is a `this`-call: `rcx` = self, so a plain function works. The effect then
stays inert in the lists, runs out on its normal duration, and is saved back unchanged.
Opcode 403 users (SadoEE) can read it via `m_effectId == 403` on the timed list.

Open checks:
- Windows `CGameEffectList::Marshal` (0x1e50e0) was not re-disassembled.
- The scan for opcode-indexed tables covered Linux only.
