// INI files for the EEex table functions EEex.GetINIString / EEex.SetINIString (path, section, key[, value]),
// with the Windows profile-file rules mods rely on: section and key names compare case-insensitively, a missing
// file / section / key gives the default, writing creates them. Portable (no Windows API): same on Linux.
// A relative path is relative to the game directory (the working directory); '\' separators work on Linux too.
#include "lua_ini.h"

#include "iex_core.h"
#include "lua_api.h"

#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace iex {

namespace {

std::string Trim(const std::string& s)
{
    std::size_t b = 0, e = s.size();
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r'))
        ++b;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r'))
        --e;
    return s.substr(b, e - b);
}

bool SameName(const std::string& a, const std::string& b)
{
    if (a.size() != b.size())
        return false;
    for (std::size_t i = 0; i < a.size(); ++i)
        if (std::tolower(static_cast<unsigned char>(a[i])) != std::tolower(static_cast<unsigned char>(b[i])))
            return false;
    return true;
}

std::string FixPath(std::string p)
{
#if !defined(_WIN32)
    for (char& c : p)
        if (c == '\\')
            c = '/';
#endif
    return p;
}

std::vector<std::string> ReadLines(const std::string& path)
{
    std::vector<std::string> lines;
    std::ifstream in(FixPath(path), std::ios::binary);
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        lines.push_back(line);
    }
    return lines;
}

// Index of the key line in [section], or -1. `sectionLine` / `sectionEnd` receive the section bounds (-1: none).
int Find(const std::vector<std::string>& lines, const std::string& section, const std::string& key, int& sectionLine,
         int& sectionEnd)
{
    sectionLine = -1;
    sectionEnd = -1;
    bool in = false;
    for (int i = 0; i < static_cast<int>(lines.size()); ++i) {
        const std::string t = Trim(lines[i]);
        if (!t.empty() && t.front() == '[') {
            if (in) {
                sectionEnd = i;
                return -1;
            }
            const std::size_t close = t.find(']');
            in = close != std::string::npos && SameName(Trim(t.substr(1, close - 1)), section);
            if (in)
                sectionLine = i;
            continue;
        }
        if (!in || t.empty() || t.front() == ';')
            continue;
        const std::size_t eq = t.find('=');
        if (eq != std::string::npos && SameName(Trim(t.substr(0, eq)), key))
            return i;
    }
    if (in)
        sectionEnd = static_cast<int>(lines.size());
    return -1;
}

// EEex.GetINIString(path, section, key, default) -> string
int LuaGet(lua_State* L)
{
    const char* path = lua.tolstring(L, 1, nullptr);
    const char* section = lua.tolstring(L, 2, nullptr);
    const char* key = lua.tolstring(L, 3, nullptr);
    const char* def = lua.tolstring(L, 4, nullptr);
    if (!path || !section || !key)
        LuaError(L, "EEex.GetINIString: path, section, key expected");
    const auto lines = ReadLines(path);
    int s, e;
    const int at = Find(lines, section, key, s, e);
    if (at < 0) {
        lua.pushstring(L, def ? def : "");
        return 1;
    }
    std::string value = Trim(lines[at].substr(lines[at].find('=') + 1));
    if (value.size() >= 2 && (value.front() == '"' || value.front() == '\'') && value.back() == value.front())
        value = value.substr(1, value.size() - 2);
    lua.pushstring(L, value.c_str());
    return 1;
}

// EEex.SetINIString(path, section, key, value): value nil removes the key.
int LuaSet(lua_State* L)
{
    const char* path = lua.tolstring(L, 1, nullptr);
    const char* section = lua.tolstring(L, 2, nullptr);
    const char* key = lua.tolstring(L, 3, nullptr);
    const char* value = lua.tolstring(L, 4, nullptr);
    if (!path || !section || !key)
        LuaError(L, "EEex.SetINIString: path, section, key expected");
    auto lines = ReadLines(path);
    int s, e;
    const int at = Find(lines, section, key, s, e);
    const std::string entry = std::string(key) + "=" + (value ? value : "");
    if (at >= 0) {
        if (value)
            lines[at] = entry;
        else
            lines.erase(lines.begin() + at);
    } else if (value) {
        if (s < 0) {
            if (!lines.empty() && !Trim(lines.back()).empty())
                lines.emplace_back();
            lines.push_back(std::string("[") + section + "]");
            lines.push_back(entry);
        } else {
            int insert = e;
            while (insert > s + 1 && Trim(lines[insert - 1]).empty())
                --insert;
            lines.insert(lines.begin() + insert, entry);
        }
    }
    std::ofstream out(FixPath(path), std::ios::binary | std::ios::trunc);
    for (const auto& l : lines)
        out << l << "\r\n";
    lua.pushboolean(L, out.good());
    return 1;
}

} // namespace

void OpenLuaIni(lua_State* L)
{
    lua.getglobal(L, "EEex");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "EEex");
    }
    lua.pushcclosure(L, LuaGet, 0);
    lua.setfield(L, -2, "GetINIString");
    lua.pushcclosure(L, LuaSet, 0);
    lua.setfield(L, -2, "SetINIString");
    lua.settop(L, -2);
}

} // namespace iex
