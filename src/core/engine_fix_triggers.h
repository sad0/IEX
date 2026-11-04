#pragma once

// Engine fix 13 (docs/ENGINE_FIXES.md): event triggers with an object function re-resolve their object on every
// evaluation. Installed by InstallEngineFixes as "eventTriggerObjects".

namespace iex {

bool InstallEventTriggerObjects();

} // namespace iex
