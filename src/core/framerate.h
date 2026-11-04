#pragma once

// Render frame rate decoupled from the game logic rate (see docs/FRAMERATE.md).
// The engine runs one logic tick and one rendered frame per CChitin::Update, at "Maximum Frame Rate"
// (CChitin::TIMER_UPDATES_PER_SECOND). IEX keeps that tick rate and draws frames on its own clock: extra frames in
// the idle time the engine would otherwise spend in SDL_Delay, Update's own frame skipped when not due. Driven by
// EEex's 'Uncap FPS' settings (on by default, as in EEex) or IEX's 'Frame Rate' (lua/IEX_FrameRate.lua).

#include <cstdint>

struct lua_State;

namespace iex {

// Hooks the SDL_Delay call of CChitin::Update (call site given by the `const CChitin.Update.delaySite`).
void InstallFrameRateHooks();

// Motion interpolation of the extra frames. FrameRateOnLogicTick runs before each CChitin::Update (one logic
// tick). FrameInterpolationBegin(area) moves the area's objects to their drawn (interpolated) position just
// before CGameArea::RenderZoomed; when it returns true, FrameInterpolationEnd() must be called right after
// RenderZoomed to write the real positions back.
void FrameRateOnLogicTick();
bool FrameInterpolationBegin(std::uintptr_t area);
void FrameInterpolationEnd();

// Registers IEX_SetFrameRate / IEX_GetFrameRate / IEX_GetRenderRate and the IEX_*FrameInterpolation functions.
void OpenLuaFrameRate(lua_State* L);

} // namespace iex
