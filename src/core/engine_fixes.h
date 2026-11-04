#pragma once

// Engine fixes: engine bugs that EEex fixes, fixed natively by IEX (docs/ENGINE_FIXES.md), on by default.
// Each fix checks the engine bytes it changes first and leaves a site alone when they differ (other build, another
// patch). Baldur.lua: SetPrivateProfileString('IEX','Engine Fixes','0') turns them all off,
// SetPrivateProfileString('IEX','Engine Fix <name>','0') one fix. Environment (takes precedence): IEX_ENGINE_FIXES=0 / 1,
// IEX_ENGINE_FIXES_OFF=<name>,<name> (when set, the per-fix Baldur.lua keys are not read).

struct lua_State;

namespace iex {

// Startup step (kept for the startup order); the fixes themselves are installed by OpenLuaEngineFixes.
void InstallEngineFixes();

// Installs the fixes on the first call (Baldur.lua is loaded by then, no game code has run), then
// IEX_Features.engineFixes = {<name> = true / false}, IEX_EngineFixes() -> the same table.
void OpenLuaEngineFixes(lua_State* L);

} // namespace iex
