# SadoEE engine field targets

Every engine userdata field that SadoEE (our own mod, `E:/Enhanced Edition/SadoEE/SadoEE`, 49 Lua files)
reads or writes through EEex-style typed userdata. This is the minimum struct surface IEX must expose
for SadoEE to run. Names are the public Lua API names used by mods.

- Source: `grep` of all `*.lua` for `.m_*`, `field(x, 'm_*')`, `pRes.resref`, `pNext`, `nNewX`... plus
  manual reading of each receiver to infer its engine type.
- **Uses** = number of textual accesses in SadoEE (approximate; same name on several types is summed).
- **Conf** = confidence of the Linux 2.7.3 offset we derived (see `TYPES_METHOD.md`). Offsets themselves
  are game-derived data and live outside this repo (`IEX-data/engine/types/linux64-bg2ee-2.7.3.types.json`).

Totals: 28 types, ~119 fields used by SadoEE (plus a few neighbours resolved for context).

## How SadoEE reaches the objects

| Entry point | Type |
|---|---|
| `EEex_GameObject_Get(id)`, `EEex_GameObject_CastUserType`, `EEex_LuaObject`, `EEex_LuaTrigger_Object` | `CGameObject` / `CGameSprite` / `CGameContainer` / `CGameTrigger` (by `m_objectType`: 0x31 sprite, 0x41 trigger, container) |
| `EEex_EngineGlobal_CBaldurChitin`, `EngineGlobals.g_pBaldurChitin` | `CBaldurChitin` |
| `EEex_Area_GetVisible()`, `sp.m_pArea`, `game.m_gameAreas:get(i)` | `CGameArea` |
| `EEex_Actionbar_GetArray()` | `CInfButtonArray` |
| `EEex_PtrToUD(p, 'CStore')`, `'CStoreFileItem'`, `'CItem'` | as named |
| `EEex_Utility_IterateCPtrList(list, fn)` | `CPtrList` nodes (`pNext`, `data`) |

## Fields

### CGameObject (base of every game object)
| Field | Lua type | Uses | Conf | Notes |
|---|---|---|---|---|
| m_id | int | 99 | high | object id (`sp.m_id`, `ob.m_id`) |
| m_objectType | u8 | 27 | high | 0x31 sprite, 0x41 trigger |
| m_pos | CPoint | 64 | high | `.x`, `.y` |
| m_pArea | CGameArea* | 17 | high | |
| m_typeAI | CAIObjectType | 35 | high | `.m_Class/.m_Race/.m_EnemyAlly/.m_Alignment` |

### CGameAIBase (scriptable objects)
| Field | Lua type | Uses | Conf | Notes |
|---|---|---|---|---|
| m_scriptName | char[32] `:get()` | 13 | high (sprite, container) | trigger: see note in types json |
| m_curAction | CAIAction | 9 | high | |
| m_queuedActions | CTypedPtrList&lt;CAIAction*&gt; | 9 | high | iterated, `.m_nCount` |

### CGameSprite
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_resref | CResRef `:get()` | 2 | high |
| m_baseStats | CCreatureFileHeader | 50 | high |
| m_derivedStats | CDerivedStats | 6 | high |
| m_equipment | CGameSpriteEquipment | 73 | high |
| m_startTypeAI | CAIObjectType | 5 | medium |
| m_liveTypeAI | CAIObjectType | 1 | medium |
| m_animation | CGameAnimation (`.m_animation.m_animationID`) | 9 | medium |
| m_timedEffectList | CGameEffectList | 1 | high |
| m_equipedEffectList | CGameEffectList | 1 | medium |
| m_dialog | CResRef `:get()/:set()` | 2 | medium |

### CCreatureFileHeader (`sp.m_baseStats`, CRE V1.0 header)
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_name | strref | 2 | high |
| m_apparentName | strref | 1 | medium |
| m_flags | u32 | (shared) | high |
| m_xpValue | u32 | 1 | high |
| m_xp | u32 | 15 | high |
| m_gold | u32 | 2 | high |
| m_generalState | u32 | (shared) | high |
| m_hitPoints | s16 | 9 | high |
| m_maxHitPointsBase | s16 | 2 | high |
| m_portraitSmall / m_portraitLarge | CResRef `:get()` | 2 / 2 | medium |
| m_armorClass | s16 | 1 | **low** (natural vs effective AC unclear) |
| m_level1 / m_level2 / m_level3 | u8 | 3 / 3 / 2 | high |
| m_STRBase, m_INTBase, m_WISBase, m_DEXBase, m_CONBase, m_CHRBase | u8 | 1-3 each | high |
| m_mageSpecUpperWord | u16 (kit) | 4 | medium |

### CDerivedStats (`sp.m_derivedStats`)
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_generalState | u32 | 6 | high |
| m_nMaxHitPoints | s16 | (EEex API) | high |

The full stat-id table (201 stats) is also resolved, for `EEex_Sprite_GetStat`-style helpers.

### CGameSpriteEquipment (`sp.m_equipment`)
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_items | CItem*[39] `:get(i)/:set(i,v)` | 65 | high |
| m_selectedWeapon | u8 | 9 | high |

### CItem
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| pRes | CResItem* (`.resref:get()`) | 46 | high |
| m_flags | u32 | 15 (shared) | high |
| m_useCount1 | u16 | 6 | high |

### CRes
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| resref | name `:get()` | 46 | medium (stored as a pointer in 2.7.3) |

### CAIObjectType
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_EnemyAlly | u8 | 6 | high |
| m_Race | u8 | 14 | high |
| m_Class | u8 | 28 | high |
| m_Alignment | u8 | 5 | medium |
| m_Instance | int (written: `a.m_acteeID.m_Instance = id`) | 4 | high |

### CAIAction
| Field | Lua type | Uses | Conf |
|---|---|---|---|
| m_actionID | s16 | 21 | high |
| m_acteeID | CAIObjectType | 4 | high |
| m_dest | CPoint | 7 | high |

### CPoint / CRect
| Field | Uses | Conf |
|---|---|---|
| CPoint.x, CPoint.y | 64+ | high |
| CRect.left/top/right/bottom (`m_rBounding`, `rViewPort`) | 23 | high |

### CPtrList / node
| Field | Uses | Conf |
|---|---|---|
| m_pNodeHead | 1 | high |
| m_nCount | 3 | high |
| node.pNext, node.data | 1 + iterator | high |
| `:AddTail(ud)` (method) | 1 | n/a (method) |

### CGameArea
| Field | Uses | Conf |
|---|---|---|
| m_resref `:get()` | 14 (shared) | high |
| m_lVertSort | 11 | medium |
| m_lVertSortBack | 12 | medium |
| m_cInfinity | 2 | high |

### CInfinity (`area.m_cInfinity`)
| Field | Uses | Conf |
|---|---|---|
| nNewX, nNewY | 2 / 2 | medium |
| rViewPort | 2 | high: +0x78, the world view with zoom (as EEex, observed 2026-10-29); +0x68 = rViewPortUnzoomed |

### CInfGame (`chitin.m_pObjectGame`)
| Field | Uses | Conf |
|---|---|---|
| m_gameAreas `:get(i)` | 2 | high |
| m_visibleArea | 2 | high |
| m_nState | 2 | medium |
| m_nReputation | 1 | high |
| m_iContainer | 2 | high |
| m_iContainerSprite | 1 | medium |
| m_worldTime.m_gameTime | 1 | high |
| m_sSaveGame.m_pchData `:get()` | 1 | medium |
| m_sCurrentCampaign.m_pchData `:get()` | 1 | high |

### CBaldurChitin
| Field | Uses | Conf |
|---|---|---|
| m_pObjectGame | 19 | high |
| m_pEngineInventory | 6 | high |
| m_pEngineWorld | 1 | high |
| m_pEngineStore | 1 | high |
| m_pObjectCursor (`:SetCursor` method) | 1 | high |

### CScreenInventory / CScreenStore / CStore / CStoreFileItem
| Field | Uses | Conf |
|---|---|---|
| CScreenInventory.m_pTempItem (read, written nil) | 9 | medium |
| CScreenStore.m_pStore | 1 | high |
| CStore.m_resRef `:get()` | 1 | high |
| CStore.m_lInventory | 3 | high |
| CStoreFileItem.m_itemId `:get()` | 1 | high |
| CStoreFileItem.m_usageCount `:get(i)` | 1 | medium |
| CStoreFileItem.m_nInStock | 1 | high |

### CGameContainer
| Field | Uses | Conf |
|---|---|---|
| m_lstItems | 5 | high |
| m_dwFlags | 10 (shared) | high |
| m_drawPoly (written) | 6 (shared) | high |
| m_trapActivated, m_trapDetected | 7 / 7 (shared) | high |
| m_containerType | 1 | high |
| m_lockDifficulty | 1 | high |
| m_trapRemovalDifficulty | 2 (shared) | high |

### CGameTrigger
| Field | Uses | Conf |
|---|---|---|
| m_rBounding | 5 | high |
| m_dwFlags | (shared) | high |
| m_trapActivated, m_trapDetected | (shared) | high |
| m_trapDetectionDifficulty | 1 | high |
| m_trapDisarmingDifficulty (EEex's name; IEX also keeps m_trapRemovalDifficulty) | 2 / 2 | high |
| m_scriptRes `:get()` | 2 | high |
| m_drawPoly | (shared) | high |

### CGameDoor
Observed under EEex (2026-10-29, trap probe): the door's disarm difficulty is `m_trapDisarmingDifficulty` (0x646,
as on triggers; containers say `m_trapRemovalDifficulty`) and doors have `m_drawPoly` (0x660, i16), which SadoEE
writes to outline a detected trapped door.

### CGameEffect (items of the effect lists)
| Field | Uses | Conf |
|---|---|---|
| m_effectId | 2 | high |
| m_sourceId | 1 | medium |
| m_sourceRes (also used as an effect-table key) | 1 | high |

### CInfButtonArray / CGameAnimationType
| Field | Uses | Conf |
|---|---|---|
| CInfButtonArray.m_buttonTypes `:get(i)` (i = 0..11) | 1 | medium |
| CGameAnimation.m_animation | 9 | medium |
| CGameAnimationType.m_animationID | 4 | high |

## Not covered here

- Raw `EEex_ReadU32(ptr + 0x..)` / asm-hook offsets in SadoEE (Windows x64 offsets, binary-level).
- Methods called on userdata (`AddTail`, `SetCursor`, `:get/:set` accessors): API surface, not layout.
