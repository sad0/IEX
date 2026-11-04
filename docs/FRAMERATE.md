# Render frame rate above the logic rate (BG2EE 2.7.3)

Own analysis of the Linux build (symbols, Ghidra `IEX_linux273`) and the Windows exe (pedis.py / xrefs.py,
hand-checked). Linux addresses are symtab VAs, Windows addresses are RVAs (base 0x140000000).
Hand-verified entries: `IEX-data/engine/win/verified_fps.json`.

## Main loop

`CChitin::WinMain` (Lin 0x5933f0) loops on `CChitin::ProcessEvents` (Lin 0x591bc0, Win 0x41b870, SDL events)
then `CChitin::Update` (Lin 0x593090, Win 0x41cac0). One Update is one logic tick **and** one frame:

1. `SearchThreadMain` (path search), timed into chitin+0x1f4; `fadeSounds`.
2. Logic: chitin vtable+0xe8 = `CBaldurChitin::AsynchronousUpdate` (Lin 0x1360c0, Win 0x131c10): message
   handler, multiplayer heartbeats, then `CChitin::AsynchronousUpdate` (Lin 0x58f040, Win 0x419ac0): music,
   tick counter (+0x1c0, copied every second to **+0x1bc = ticks/s**), then the active engine (chitin+0x208)
   `TimerUpdate` (CWarp timers; `CBaldurEngine::TimerUpdate` Lin 0x136830 also bumps a game counter) and
   `TimerAsynchronousUpdate` (world: `CScreenWorld::AsynchronousUpdate(int)` Lin 0x3a5bc0, Win 0x2eb8e0 =
   AI, movement, scrolling, game time). Then UI timer events (`uiEventMenuStack`). Time -> +0x1ec.
3. Render: chitin vtable[0] = `CBaldurChitin::SynchronousUpdate` (Lin 0x136810, Win 0x136510) =
   `CChitin::SynchronousUpdate` (Lin 0x58f300, Win 0x41c890) + `chWriteInifile` (writes Baldur.lua only
   when dirty). Update sets an "in render" flag around this call (Lin +0x1000, Win +0xfb0). Time -> +0x1f0.
   `CChitin::SynchronousUpdate`: frame counter (+0x1cc, every second to **+0x1c8 = frames/s**),
   `DrawClear`, engine `ResetControls` / `TimerSynchronousUpdate` / `RenderUI` (engine vtable Lin
   +0x1a0/+0x1b0/+0x1c0, Win +0x198/+0x1a8/+0x1b8), `CVidMode::Flip(1)` (Lin 0x5b5d00: pointer, `DrawFlip`).
4. `CNetwork::ThreadLoop`; total time -> +0x1e8.
5. **Frame limiter**: `budget = 1000 / CChitin::TIMER_UPDATES_PER_SECOND`; if total < budget and
   chitin+0x1080 (Win +0x1030) == 0: `SDL_Delay(budget - total)`. Call site: Lin 0x5933a4, Win 0x41ccf6;
   the only SDL_Delay call in Update. There is no other pacing (no fixed-step accumulator).

`CChitin::TIMER_UPDATES_PER_SECOND` (Lin 0xd0c454, Win 0x65cc5c, uint, default 30) is set in
`CChitin::InitInstance` from Baldur.lua "Maximum Frame Rate". It is also the logic tick rate: CWarp timers
add 10000/TPS per tick, `CGameSprite::GetLength`, `CGameAIBase::Wait`, scroll speed (`StartScroll`) and the
automated speed options divide by it. Raising it therefore speeds the whole game up.

## Where the world is drawn

`CScreenWorld::TimerSynchronousUpdate` (Lin 0x39c330, Win 0x2fcbc0): applies the touch-scroll velocity
(+0x78, divided by TPS, then x0.75 per call), `CInfGame::SynchronousUpdate` (Lin 0x313110, Win 0x292010:
deferred object work queues), `CTimerWorld::StartTime` when the area asks for it, then
`CVidMode::EnableScissoring`, `CGameArea::RenderZoomed` (Lin 0x1911b0, Win 0x189e20: `DrawBeginScaled`,
`CGameArea::Render` -> CInfinity tiles, sprites, fog; then the area's "render on top" objects), and
`UpdateLua`. `CBaldurEngine::RenderUI` = `uiDrawMenuStack` (menus run their Lua `enabled`/text functions
here, once per frame: this is what the SadoEE FPS counter counts).

Sprite animation frames advance in the AI update (`CGameAnimationType*::IncrementFrame` from AIUpdate),
not in Render, so drawing more often does not animate faster.

## Game speed and EEex's 'Uncap FPS' (measured 2026-10-30, tools/speedtest)

the maintainer's report (IEX 0.3.0 RC, Tweaks Anthology "Dynamic FPS Change" + BuffBot): "everything is twice as fast at
60 fps". Cause: TA's Lua action writes `EEex_CChitin.TIMER_UPDATES_PER_SECOND = 60` out of combat (30 in combat
and cutscenes). That variable is the logic tick rate, so the game runs twice as fast. **EEex does the same.**

Probe `tools/speedtest/probe/spd_body.lua`, runner `tools/speedtest/run.ps1` (EET 2.7.3 copy, save "Chapter 2
Start", window off screen; 144 Hz primary monitor + a 60 Hz one). Per phase: drawn frames/s (a menu's per-frame
Lua), game time (m_gameTime) per real second (normal = 15), leader walking speed. "TA" = TA's rule (60 out of
combat; in combat it writes 30 = normal everywhere), "bbN" = the write comes from a chunk named BfBotFst.lua
(BuffBot's fast mode). Cells: frames/s, game ticks/s (speed).

| engine, settings                              | 30 ticks/s  | TA out of combat (60)  | 120 (BuffBot 4x)    |
|-----------------------------------------------|-------------|------------------------|---------------------|
| EEex, Uncap FPS 1 (default), VSync 1          | 60, 15      | 60, 30 (2x)            | 60, 60 (4x)         |
| EEex, Uncap FPS 1, VSync 0                    | 715, 15     | 795, 30 (2x)           |                     |
| EEex, Uncap FPS 1, VSync 0, limit 45          | 45, 15      | 45, 30 (2x)            |                     |
| EEex, Uncap FPS 0                             | 30, 15      | 60, 30 (2x)            | 60, 30 (2x)         |
| IEX 0.3.0 (Uncap keys ignored)                | 30, 15      | 60, 30 (2x)            | 58, 29 (2x)         |
| IEX now, defaults (Uncap 1, Keep Game Speed 1)| 144, 15     | 144, **15 (1x)**       | bb120: 144, 60 (4x) |
| IEX now, Keep Game Speed 0                    | 144, 15     | 144, 30 (2x)           | 144, 60 (4x)        |
| IEX now, limit 45                             | 45, 15      | 45, 15 (1x)            | bb120: 45, 60 (4x)  |
| IEX now, VSync 0                              | 957, 15     | 945, 15 (1x)           | bb120: 882, 60 (4x) |
| IEX now, Uncap FPS 0                          | 30, 15      | 60, 15 (1x)            | bb120: 30, 60 (4x)  |

Walking: 129 px/s at 1x, 255-268 px/s at 2x, 511-530 px/s at 4x on both engines (8.6-8.8 px per game tick
everywhere: walking follows the game time).

What EEex's options do (observed): 'Uncap FPS' decouples frames from ticks (frames at the monitor rate, the
logic at TIMER_UPDATES_PER_SECOND even above the refresh rate: 120 ticks/s = 4x with 60 fps); off = the
engine's one frame per tick (120 is then capped by the flip at 60 = 2x). 'VSync Enabled' 0 = as many frames as
possible; 'Uncap FPS Limit Enabled' / 'Uncap FPS Limit' cap them. Its "Uncap FPS" options tab shows: AI Speed
(the tick rate), Enable FPS Uncap, Enable FPS Limit, FPS Limit, FPS Limit Busy Wait Threshold, Fullscreen
Variable Refresh Rate Hint, Lua Garbage Collection Steps ('Lua GC Steps'), Remove Middle Mouse Scroll
Multiplier, VSync Enabled. Off screen, EEex drew 60 fps with VSync on although the primary monitor is 144 Hz;
IEX follows the refresh rate of the window's display (144 there). Not checked with an on-screen window.

IEX decision (better, compatible):
- The same Baldur.lua [EEex] keys and defaults, and an "Uncap FPS" tab with EEex's labels in the options screen
  (plus three IEX rows). Not implemented: 'Lua GC Steps' and 'Remove Middle Mouse Scroll Multiplier' (other
  features); 'Uncap FPS Fullscreen VRR' is stored and shown only.
- **Keep Game Speed** (Baldur.lua [IEX] 'Keep Game Speed', default 1): a mod's write to
  `EEex_CChitin.TIMER_UPDATES_PER_SECOND` does not change the logic rate. It becomes a render rate request (used
  when the player has no render rate, i.e. 'Uncap FPS' 0 and no IEX 'Frame Rate') and the writer reads back what
  it wrote (TA's `~= 60` check stays quiet). Writes from the files listed in `IEX_GameSpeedWriters` (default
  `{ 'BfBotFst' }`: BuffBot's explicit 2x / 4x fast mode, matched on the Lua chunk name) change the logic rate as
  under EEex and read the real rate. 'Keep Game Speed' 0 = exactly EEex. The player's own "AI Speed"
  (Baldur.lua [IEX] 'AI Speed', default 30, applied live from the options screen) always sets the game speed.

### The saved tick rate (the maintainer's report "still twice as fast at 60 fps", 2026-10-30)

`CBaldurChitin::SaveOptions` (Lin 0x132720) writes the **current** `TIMER_UPDATES_PER_SECOND` to 'Program Options'
'Maximum Frame Rate' (Lin 0x1327c0: `mov edx, [TIMER_UPDATES_PER_SECOND]`, `"%d"`, then the key), and
`CChitin::InitInstance` reads it back at the next launch (accepted range 10..90, else 30). So a mod's rate write
(TA Dynamic FPS: 60 out of combat; under EEex, under IEX before Keep Game Speed, or with Keep Game Speed 0) is saved
and becomes the logic rate of every later launch. the maintainer's 0.3.0 game had 'Maximum Frame Rate' 60: logic 60 ticks/s,
game time 30/s (2x) in and out of combat, because Keep Game Speed then also blocked TA's in-combat 30. IEX.log's
"Render frame rate: 60 (logic 30 ticks/s)" is printed before InitInstance reads the key and did not show it.
Under EEex the saved value is harmless with TA (TA rewrites 60 / 30 all the time).

Fix: with Keep Game Speed on, the logic rate is the player's speed, [IEX] 'AI Speed' (default 30, written only by
the AI Speed option), set on the first logic tick (after InitInstance); 'Maximum Frame Rate' is not used (IEX.log:
"Keep Game Speed: Baldur.lua 'Maximum Frame Rate' 60 ... not used, game speed 30"). Keep Game Speed 0 = EEex
(the saved value is the logic rate).

Measured after the fix (copy of the maintainer's full-win-0.3.0 game: BG2EE + TA Dynamic FPS, BuffBot, SadoEE, Stick,
Pathfinding Redux; his Baldur.lua with 'Maximum Frame Rate' 60; his Quick-Save, AR0602; leader walking 417 px
out / 421 px back, 2 legs each; tools/speedtest `-Copy -EngineName`, phases `x,x,x,x`, WalkMs 4000):

| settings                                         | frames/s | game ticks/s | walk out / back px/s |
|--------------------------------------------------|----------|--------------|----------------------|
| reference: 'Uncap FPS' 0, mods' rate requests off (engine pacing, one frame per tick) | 30 | 14.94-14.98 | 119.0-120.1 / 105.2-105.3 |
| the maintainer's settings (Uncap 1, VSync 1, 60 Hz monitor) | 60       | 14.95-15.00  | 120.3-120.7 / 105.3  |
| Frame Rate 120, VSync 0                          | 117      | 15.00        | 120.0-120.3 / 105.3-105.5 |
| Frame Rate 144, VSync 0                          | 133-136  | 14.99-15.00  | 120.2 / 105.3        |
| Frame Rate 240, VSync 0                          | 180-205  | 14.98-15.00  | 120.0-120.2 / 105.4  |
| the maintainer's settings, Frame Interpolation 0           | 59-60    | 14.99-15.00  | 120.3-120.5 / 105.3  |
| Keep Game Speed 0 (= EEex with the saved 60)     | 57-60    | 29.4-29.9    | 240.3-240.4 / 210.7-212.6 (2x) |
| before the fix (0.3.0, the maintainer's settings)          | 59       | 29.6-30.1    | 2x                   |

Walking within 1.5 % of the reference at every frame rate, 8.02 / 7.02 px per game tick everywhere. Nothing ran
the logic twice (interpolation, render slot hook, tick schedule, Pathfinding Redux): only the saved tick rate.

## IEX approach (src/core/framerate.cpp)

Two hooks: the SDL_Delay call of Update (call-site hook, site from `const CChitin.Update.delaySite`) and
Update's own frame, CBaldurChitin vtable slot 0 (`IEX_VtSlot_ChitinSynchronousUpdate`: Win RVA 0x58dd00, Lin
0xcedfb8 = `_ZTV13CBaldurChitin` + 0x10; both hold SynchronousUpdate; entry in `verified_fps.json`).
With a render target N and T ticks/s:
- Ticks run on a fixed schedule (1000 / T ms apart): a late tick (long frame, blocking flip) is caught up by
  shorter waits; more than 3 ticks behind = start again. The average tick rate is T even when frames are rarer
  than ticks (120 ticks/s with 45 or 60 fps).
- A frame clock (1000 / N ms) decides every frame: Update's own frame is drawn only when due (else skipped and
  counted), and frames due while the tick waits are drawn there (`CBaldurChitin::SynchronousUpdate` with the
  in-render flag set). A frame more than half an interval late is dropped. N need not be a multiple of T.
- 'Uncap FPS' 1 + VSync 1: N = refresh rate of the window's display (SDL_GL_GetCurrentWindow ->
  SDL_GetWindowDisplayIndex -> SDL_GetCurrentDisplayMode), re-read every 2 s, at most the limit when enabled.
  VSync 0: N = the limit, else 1000. VSync = the GL swap interval (SDL_GL_Set/GetSwapInterval), checked every
  tick, the engine's value restored when 'Uncap FPS' is off. Busy Wait Threshold = ms of each wait spun.

Lua: `IEX_SetFrameRate(n [, cap])` (0 = engine default, -1 = window display refresh rate, followed),
`IEX_GetFrameRate()` -> requested, ticks/s, rate in use, mod request, Update frames skipped, swap interval;
`IEX_GetRenderRate()` (engine frames/s and ticks/s), `IEX_SetFrameRateFloor(n)`, `IEX_SetVSync(-1|0|1)`,
`IEX_SetBusyWait(ms)`, `IEX_ApplyFrameSettings()` (re-reads Baldur.lua), `IEX_SetKeepGameSpeed(on)`,
`IEX_GetKeepGameSpeed()`. Baldur.lua `SetPrivateProfileString('IEX','Frame Rate','144')` overrides the EEex
settings when not 0 (lua/IEX_FrameRate.lua).

Limits:
- Per-render side effects that run more (or less) often when N != T: touch-scroll inertia decay, the
  `StartTime` interface countdown, the area flash countdown (CGameArea +0xfac), menu Lua that counts frames.

## Motion interpolation (framerate.cpp, on by default in the extra-frame mode)

What moves where (own analysis, Linux objdump/Ghidra + Windows objdump, entries in `verified_fps.json`):

- **Objects**: drawn by `CGameArea::Render` (Lin 0x1908d0, Win 0x189360) from the four vertical lists of the
  area, in order head +0xce0 (`m_lVertSortAdd`), `CInfinity::Render`, +0xc70 (`m_lVertSortBack`), +0xc38
  (`m_lVertSort`), +0xca8 (`m_lVertSortFlight`) (CPtrList head at list+8, node next +0, object id +0x10),
  each through `CGameObjectArray::GetShare` (Win 0x276700) and the object's vtable Render (Win +0x98,
  Lin +0xa0); `RenderZoomed` then redraws its "on top" list (+0xf08). `CGameSprite::Render` (Lin 0x4bb000,
  Win 0x36ba50) takes the draw point from `CGameObject::m_pos` (+0xc/+0x10) and `m_posZ` (+0x14) and stores
  nothing into the sprite. Projectiles, VVCs and other area objects are CGameObjects in the same lists.
- **Movement cadence** (trace, both builds): a walking sprite's `m_pos` changes every **second** logic tick
  (15 steps/s at 30 ticks/s, ~5-9 px per step), so even the normal 30 fps shows 15 Hz motion.
- **Camera**: already advanced per drawn frame by the engine. `CGameArea::Render` itself calls
  `CInfinity::Scroll` (Lin 0x3212c0, Win 0x2a2b30; scroll destination area +0x8c8, speed +0x8c4) or
  `CInfinity::AdjustViewPosition` (Lin 0x322330, Win 0x29bcf0; edge/keyboard direction +0x234/+0x230), both
  time based (SDL_GetTicks delta stored in CInfinity +0x2f0, capped at 500 ms). Logic only sets destinations
  (`CScreenWorld::AsynchronousUpdate` -> `SetScrollDest` / `SetViewPosition`). Measured in the extra-frame
  mode: keyboard scroll moves the view 7-8 px on **every** frame (main and extra). Nothing to interpolate.
  (The tick-based zoom transition of `CScreenWorld::AsynchronousUpdate`, +0xbac..+0xbd4, stays per tick.)

IEX design:

1. `CChitin::Update` call-site hook (event_hooks.cpp) -> `FrameRateOnLogicTick()`: tick counter.
2. `CGameArea::RenderZoomed` call-site hook (already the `AreaRender` event): after the Lua listeners,
   `FrameInterpolationBegin(area)` walks the four lists; the first time an object is seen in a tick its
   logic position is captured; then `m_pos`/`m_posZ` are overwritten with the drawn point and the real
   values are written back by `FrameInterpolationEnd()` right after RenderZoomed returns. Only frames of the
   render path (CChitin in-render flag set: Update's frame and the extra frames) are touched, never
   `CScreenWorld::SaveScreen` (save thumbnails). AI, path search, the next AsynchronousUpdate, saving and the
   Lua menu code never see an interpolated value.
3. Per object, when its position changes at tick S, the drawn point goes from where it was drawn at S to the
   new position over `span` ticks = interval since its previous change (1..2), so a sprite stepping every
   other tick glides at constant speed. Frame phase: 0 for Update's own frame, i/n for extra frame i.
   The drawn world lags the logic by one step (33-66 ms); sprite animation frames stay on logic ticks.
4. Snap (no interpolation): first sight, other area or object pointer, unseen for > 8 ticks, or a move of
   more than 128 px between two ticks (teleport, area change, CompressTime).
5. Checks: RenderZoomed writes back only over its own value; before each tick the restored positions are
   compared to the objects again. Both counters (`mismatch`) stayed 0 in every test.

Lua: `IEX_Features.frameInterpolation`, `IEX_SetFrameInterpolation(on)`, `IEX_GetFrameInterpolation()` -> setting, active, frames drawn
interpolated, objects moved in the last frame, snaps, mismatches; `IEX_TraceFrameInterpolation(id, frames)`
logs logic/drawn position and the view per frame. Baldur.lua `SetPrivateProfileString('IEX','Frame
Interpolation','0')` turns it off (default on; active only while the frame rate is above the tick rate).
Since 2026-10-30 the frame phase is (frame time - tick start) / tick length (frame clock); speed test runs at
144 fps: mismatch 0.

### Evidence (2026-10-29)

Windows (win-spell copy, Sauvegarde-Rapide-2, IEX_SetFrameRate(60), 60 Hz monitor, window minimized):
trace of the walking leader, one line per drawn frame (`p` = frame phase):

```
tick=2217 p=0.0 logic=(3738,2807) drawn=(3741,2801)    tick=2219 p=0.0 logic=(3736,2815) drawn=(3738,2807)
tick=2217 p=0.5 logic=(3738,2807) drawn=(3740,2803)    tick=2219 p=0.5 logic=(3736,2815) drawn=(3737,2809)
tick=2218 p=0.0 logic=(3738,2807) drawn=(3739,2804)    tick=2220 p=0.0 logic=(3736,2815) drawn=(3737,2811)
tick=2218 p=0.5 logic=(3738,2807) drawn=(3739,2806)    tick=2220 p=0.5 logic=(3736,2815) drawn=(3736,2813)
```

The drawn point changes on every frame (4 frames per logic step), monotonic, and reaches each logic point
exactly when the next step starts. Keyboard scroll in the same mode: view x 2949, 2941, 2933, 2926, ... one
value per frame (main and extra).

Desync check: same save loaded fresh, party walks to fixed points and back (actions issued at fixed game
times), every change of a party member's logic position recorded with its game time: interpolation on vs
off gave byte-identical files (129 changes). (One other "on" run had the same positions with a 3-tick shift
of one path start: the path search result arrives after a wall-clock dependent delay, same as between two
"off" runs.) 10-minute soak with interpolation on (party walking every 7 s, an enemy spawned every 40 s,
party attacks; the scripted Irenicus dungeon dialog stopped the party for the last ~2 minutes): 60 fps /
30-31 ticks/s, 33720 frames drawn interpolated, no crash, `mismatch` = 0, 0 snaps, no save written. Linux:
4-minute soak, same counters (0 / 0).

Linux (bg2ee-full-0.2.0 copy in WSLg, Chapter 1 Start): same trace shape (drawn point between logic steps
on every drawn frame; WSLg reaches 40-50 fps so some extra frames are skipped, the motion still advances on
every drawn frame). cdtweaks in that copy sets 60 ticks/s out of combat (no extra frames then); the test held
the rate at 30.

## Evidence (Windows, win-mods-fps copy, BG2 save, 2026-10-28)

`live_fpstest.lua` (test copy): 4 s per setting; frames = AreaRender events, game ticks = CTimerWorld
m_gameTime, walk = leader MoveToPoint distance in the first 1.5 s.

```
set=0    area frames/s=30.1 engine fps=30 tps=30 | game ticks/s=15.19 | walk  84.5 px/s
set=60   area frames/s=60.5 engine fps=61 tps=31 | game ticks/s=14.95 | walk 106.6 px/s
set=120  area frames/s=60.0 engine fps=60 tps=31 | game ticks/s=15.19 | walk  91.5 px/s
set=144  area frames/s=60.0 engine fps=60 tps=31 | game ticks/s=15.25 | walk 103.2 px/s
set=-1   area frames/s=60.0 engine fps=60 tps=30 | game ticks/s=14.99 | walk  92.2 px/s
set=0    area frames/s=29.9 engine fps=30 tps=30 | game ticks/s=14.96 | walk 104.0 px/s
```

Logic ticks and game time per real second are unchanged; walking speed stays in the same 84-106 px/s range
with and without (path start varies). The SadoEE FPS counter shows 60 FPS (green) with IEX_SetFrameRate(120).
Linux: see the motion interpolation evidence above.
