cmake_minimum_required(VERSION 3.20)
project(IEX VERSION 0.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Portable core: Lua glue, EEex-compatible API, logging. No OS headers here.
set(IEX_CORE_SOURCES
    src/core/log.cpp
    src/core/iex_core.cpp
    src/core/callsite_hook.cpp
    src/core/engine_types.cpp
    src/core/lua_objects.cpp
    src/core/lua_methods.cpp
    src/core/events.cpp
    src/core/event_hooks.cpp
    src/core/lua_engine.cpp
    src/core/effects.cpp
    src/core/lua_net.cpp
    src/core/lua_memory.cpp
    src/core/actionbar.cpp
    src/core/lua_resources.cpp
    src/core/framerate.cpp
    src/core/spell_slots.cpp
    src/core/spell_lists.cpp
    src/core/hd_tiles.cpp
    src/core/hd_mips.cpp
    src/core/engine_fix_triggers.cpp
    src/core/engine_fixes.cpp
    src/core/startup_movies.cpp
    src/core/opcodes.cpp
    src/core/lua_ui.cpp
    src/core/lua_scripting.cpp
    src/core/lua_sprite_hooks.cpp
    src/core/modules.cpp
    src/core/vision.cpp
    src/core/object_ids.cpp
    src/core/native_hooks.cpp
    src/core/native_hooks_sado.cpp
    src/core/pathfinding.cpp
    src/core/settings.cpp
    src/core/lua_ini.cpp
    src/core/marshal.cpp
    src/core/reg_hook.cpp
    src/core/native_stick.cpp
    src/core/hook_points.cpp
)

if(WIN32)
    enable_language(ASM_MASM)
    # IEX.dll: injected into Baldur.exe by IEXLauncher.exe (DllMain runs after all static initializers).
    add_library(iex_core STATIC ${IEX_CORE_SOURCES})
    target_include_directories(iex_core PUBLIC src/core)
        add_library(IEX SHARED src/platform/win64/dll/dllmain.cpp src/platform/win64/dll/memory_win64.cpp
        src/platform/win64/dll/net_win64.cpp src/platform/win64/dll/reg_thunk_win64.asm)
    target_link_libraries(IEX PRIVATE iex_core ws2_32)

    # IEXLauncher.exe: starts the game suspended and loads IEX.dll before the game's entry point runs.
    add_executable(IEXLauncher src/platform/win64/launcher/main.cpp)
    # No console window; keep wmain as the entry point.
    target_link_options(IEXLauncher PRIVATE /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup)
elseif(UNIX AND NOT APPLE)
    enable_language(ASM)
    # libiex.so: loaded through LD_PRELOAD. Its entry is a constructor in preload.cpp; .init_array entries run in
    # link order, so preload.cpp is linked LAST: every core global is constructed before IEX starts.
    add_library(iex SHARED ${IEX_CORE_SOURCES} src/platform/linux64/memory_linux64.cpp
        src/platform/linux64/net_linux64.cpp src/platform/linux64/reg_thunk_linux64.S
        src/platform/linux64/preload.cpp)
    target_include_directories(iex PRIVATE src/core)
    target_link_libraries(iex PRIVATE dl)
endif()

