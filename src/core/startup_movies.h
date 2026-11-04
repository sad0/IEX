#pragma once

// Skip Intro Movies: the movies CScreenStart::TimerAsynchronousUpdate plays when the game starts (the logo, then
// the intro / blackpit / SoD intro that the SoD start menu queues) are not played. Movies played later (new game
// intro, cutscenes, resting, the Movies screen) are untouched. Off by default; on with Baldur.lua
// [IEX] 'Skip Intro Movies' = 1 or the environment variable IEX_SKIP_INTRO=1 (test runners).

namespace iex {

// Hooks the CBaldurProjector::PlayMovie / PlayMovieNext calls inside CScreenStart::TimerAsynchronousUpdate.
void InstallStartupMovieHooks();

} // namespace iex
