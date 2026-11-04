// Settings files EEex-dependent mods write or test (InfinityLoader.ini, EEex.ini), and what they switch on:
// the Lua io / os libraries (LuaPatchMode), the print() log file (LogFile), EEex's module switches.
// Own implementation of the documented Lua 5.2 io / os library behavior (the engine's Lua has neither).
#include "settings.h"

#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#ifndef _WIN32
#include <glob.h>
#endif

namespace iex {

namespace {

std::string g_gameDir;

// --- INI files ---

std::string Trim(const std::string& s)
{
    const char* ws = " \t\r\n";
    const auto a = s.find_first_not_of(ws);
    if (a == std::string::npos)
        return {};
    const auto b = s.find_last_not_of(ws);
    return s.substr(a, b - a + 1);
}

std::string Lower(std::string s)
{
    for (char& c : s)
        if (c >= 'A' && c <= 'Z')
            c = static_cast<char>(c - 'A' + 'a');
    return s;
}

using IniData = std::map<std::string, std::map<std::string, std::string>>;  // lowercase section / key

bool ReadLines(const std::string& path, std::vector<std::string>& lines)
{
    std::ifstream in(path, std::ios::binary);
    if (!in)
        return false;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        lines.push_back(line);
    }
    return true;
}

bool ParseIni(const std::string& path, IniData& out)
{
    std::vector<std::string> lines;
    if (!ReadLines(path, lines))
        return false;
    std::string section;
    for (const std::string& raw : lines) {
        const std::string line = Trim(raw);
        if (line.empty() || line[0] == ';' || line[0] == '#')
            continue;
        if (line[0] == '[') {
            const auto close = line.find(']');
            section = Lower(Trim(line.substr(1, close == std::string::npos ? std::string::npos : close - 1)));
            continue;
        }
        const auto eq = line.find('=');
        if (eq == std::string::npos)
            continue;
        out[section][Lower(Trim(line.substr(0, eq)))] = Trim(line.substr(eq + 1));
    }
    return true;
}

// Sets [section] key=value in the file, keeping every other line (creates the file / section / key if needed).
bool WriteIniValue(const std::string& path, const std::string& section, const std::string& key, const std::string& value)
{
    std::vector<std::string> lines;
    ReadLines(path, lines);
    const std::string wantSection = Lower(section), wantKey = Lower(key);
    std::string current;
    bool inSection = false, sectionSeen = false;
    std::size_t insertAt = lines.size();
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const std::string line = Trim(lines[i]);
        if (!line.empty() && line[0] == '[') {
            const auto close = line.find(']');
            current = Lower(Trim(line.substr(1, close == std::string::npos ? std::string::npos : close - 1)));
            if (inSection && current != wantSection)
                break;
            inSection = current == wantSection;
            if (inSection) {
                sectionSeen = true;
                insertAt = i + 1;
            }
            continue;
        }
        if (!inSection || line.empty() || line[0] == ';' || line[0] == '#')
            continue;
        insertAt = i + 1;
        const auto eq = line.find('=');
        if (eq != std::string::npos && Lower(Trim(line.substr(0, eq))) == wantKey) {
            lines[i] = Trim(line.substr(0, eq)) + "=" + value;
            insertAt = std::string::npos;
            break;
        }
    }
    if (insertAt != std::string::npos) {
        if (!sectionSeen) {
            if (!lines.empty() && !Trim(lines.back()).empty())
                lines.push_back("");
            lines.push_back("[" + section + "]");
            insertAt = lines.size();
        }
        lines.insert(lines.begin() + static_cast<std::ptrdiff_t>(insertAt), key + "=" + value);
    }
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    for (const std::string& l : lines)
        out << l << "\r\n";
    return out.good();
}

// A file of the game folder given by a mod: relative, no "..".
bool SafeRelative(const std::string& name)
{
    if (name.empty() || name.find("..") != std::string::npos || name[0] == '/' || name[0] == '\\' ||
        name.find(':') != std::string::npos)
        return false;
    return true;
}

IniData g_loader;   // InfinityLoader.ini
IniData g_modules;  // EEex.ini
bool g_loaderFound = false, g_modulesFound = false;

std::string LoaderValue(const char* key)
{
    auto s = g_loader.find("general");
    if (s == g_loader.end())
        return {};
    auto k = s->second.find(Lower(key));
    return k == s->second.end() ? std::string() : k->second;
}

// --- print() mirror (InfinityLoader.ini LogFile) ---

std::FILE* g_printLog = nullptr;
std::size_t g_printLogBytes = 0;
std::mutex g_printMutex;
constexpr std::size_t kMaxPrintLog = 64u * 1024 * 1024;  // never fill the disk

int LuaPrintMirror(lua_State* L)
{
    const int n = lua.gettop(L);
    std::string line;
    for (int i = 1; i <= n; ++i) {
        if (i > 1)
            line += '\t';
        lua.getglobal(L, "tostring");
        lua.pushvalue(L, i);
        if (lua.pcallk(L, 1, 1, 0, 0, nullptr) == 0) {
            std::size_t len = 0;
            const char* s = lua.tolstring(L, -1, &len);
            if (s)
                line.append(s, len);
        }
        lua.settop(L, n);
    }
    {
        std::lock_guard<std::mutex> lock(g_printMutex);
        if (g_printLog && g_printLogBytes < kMaxPrintLog) {
            const int w = std::fprintf(g_printLog, "INFO: LPRINT: %s\n", line.c_str());
            std::fflush(g_printLog);
            g_printLogBytes += w > 0 ? static_cast<std::size_t>(w) : 0;
        }
    }
    // the engine's own print (upvalue 1) as before
    lua.pushvalue(L, LuaUpvalueIndex(1));
    lua.insert(L, 1);
    if (lua.pcallk(L, n, 0, 0, 0, nullptr) != 0)
        lua.error(L);
    return 0;
}

// --- io library ---

constexpr const char* kFileMeta = "IEX_FILE*";

struct LuaFile {
    std::FILE* f;
    bool closable;  // false for the standard streams
    bool pipe;      // io.popen: closed with pclose
};

#ifdef _WIN32
int ClosePipe(std::FILE* f) { return _pclose(f); }
std::FILE* OpenPipe(const char* cmd, const char* mode) { return _popen(cmd, mode); }
#else
int ClosePipe(std::FILE* f) { return pclose(f); }
// Mods written for Windows list files with cmd's `dir /b "<dir>\<pattern>"` (BuffBot's preset list): on Linux the
// same listing (bare names, sorted) comes from glob(), in a temporary file read like the command's output.
std::FILE* DirListing(const std::string& cmd)
{
    std::string c = cmd;
    const auto strip = [&c](const char* tail) {
        const std::size_t n = std::strlen(tail);
        if (c.size() >= n && c.compare(c.size() - n, n, tail) == 0)
            c.erase(c.size() - n);
    };
    while (!c.empty() && c.back() == ' ')
        c.pop_back();
    strip("2>nul");
    strip("2>NUL");
    while (!c.empty() && c.back() == ' ')
        c.pop_back();
    if (c.size() < 9 || (c.compare(0, 7, "dir /b ") != 0 && c.compare(0, 7, "DIR /B ") != 0))
        return nullptr;
    std::string pattern = c.substr(7);
    if (pattern.size() >= 2 && pattern.front() == '"' && pattern.back() == '"')
        pattern = pattern.substr(1, pattern.size() - 2);
    for (char& ch : pattern)
        if (ch == '\\')
            ch = '/';
    std::FILE* f = std::tmpfile();
    if (!f)
        return nullptr;
    glob_t g{};
    if (glob(pattern.c_str(), 0, nullptr, &g) == 0) {
        for (std::size_t i = 0; i < g.gl_pathc; ++i) {
            const char* path = g.gl_pathv[i];
            const char* slash = std::strrchr(path, '/');
            std::fprintf(f, "%s\n", slash ? slash + 1 : path);
        }
    }
    globfree(&g);
    std::rewind(f);
    return f;
}
std::FILE* OpenPipe(const char* cmd, const char* mode) { return popen(cmd, mode); }
#endif
int CloseFile(LuaFile* lf) { return lf->pipe ? ClosePipe(lf->f) : std::fclose(lf->f); }

int PushError(lua_State* L, const std::string& what)
{
    const int e = errno;
    lua.pushnil(L);
    lua.pushstring(L, (what.empty() ? std::string(std::strerror(e)) : what + ": " + std::strerror(e)).c_str());
    lua.pushinteger(L, e);
    return 3;
}

LuaFile* NewFile(lua_State* L, std::FILE* f, bool closable)
{
    auto* lf = static_cast<LuaFile*>(lua.newuserdata(L, sizeof(LuaFile)));
    lf->f = f;
    lf->closable = closable;
    lf->pipe = false;
    lua.getfield(L, LUA_REGISTRYINDEX, kFileMeta);
    lua.setmetatable(L, -2);
    return lf;
}

LuaFile* ToFile(lua_State* L, int idx)
{
    if (lua.type(L, idx) != LUA_TUSERDATA || !lua.getmetatable(L, idx))
        return nullptr;
    lua.getfield(L, LUA_REGISTRYINDEX, kFileMeta);
    const bool same = lua.rawequal(L, -1, -2) != 0;
    lua.settop(L, lua.gettop(L) - 2);
    return same ? static_cast<LuaFile*>(lua.touserdata(L, idx)) : nullptr;
}

std::FILE* OpenFileArg(lua_State* L, int idx)
{
    LuaFile* lf = ToFile(L, idx);
    if (!lf)
        LuaError(L, "bad argument #%d (file expected)", idx);
    if (!lf->f)
        LuaError(L, "attempt to use a closed file");
    return lf->f;
}

bool ReadLine(std::FILE* f, std::string& out, bool keepNewline)
{
    out.clear();
    int c;
    bool any = false;
    while ((c = std::fgetc(f)) != EOF) {
        any = true;
        if (c == '\n') {
            if (keepNewline)
                out += '\n';
            return true;
        }
        out += static_cast<char>(c);
    }
    return any;
}

// Reads with the Lua 5.2 formats ("*l" "*L" "*a" "*n", byte count) from argument `first` on.
int ReadFormats(lua_State* L, std::FILE* f, int first)
{
    const int last = lua.gettop(L);
    std::clearerr(f);
    if (first > last) {
        std::string line;
        if (ReadLine(f, line, false))
            lua.pushlstring(L, line.data(), line.size());
        else
            lua.pushnil(L);
        return 1;
    }
    int pushed = 0;
    for (int i = first; i <= last; ++i) {
        bool ok = true;
        if (lua.type(L, i) == LUA_TNUMBER) {
            const auto count = static_cast<std::size_t>(lua.tointegerx(L, i, nullptr));
            std::string buf(count, '\0');
            const std::size_t got = count ? std::fread(&buf[0], 1, count, f) : 0;
            if (count == 0) {
                const int c = std::fgetc(f);
                ok = c != EOF;
                if (ok)
                    std::ungetc(c, f);
                lua.pushstring(L, "");
            } else {
                ok = got > 0;
                lua.pushlstring(L, buf.data(), got);
            }
        } else {
            const char* fmt = lua.tolstring(L, i, nullptr);
            std::string spec = fmt ? fmt : "";
            if (!spec.empty() && spec[0] == '*')
                spec.erase(0, 1);
            const char kind = spec.empty() ? 'l' : spec[0];
            if (kind == 'l' || kind == 'L') {
                std::string line;
                ok = ReadLine(f, line, kind == 'L');
                lua.pushlstring(L, line.data(), line.size());
            } else if (kind == 'a') {
                std::string all;
                char buf[4096];
                std::size_t n;
                while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0)
                    all.append(buf, n);
                lua.pushlstring(L, all.data(), all.size());
            } else if (kind == 'n') {
                double d = 0;
                ok = std::fscanf(f, "%lf", &d) == 1;
                lua.pushnumber(L, d);
            } else {
                LuaError(L, "bad argument #%d to 'read' (invalid format)", i);
            }
        }
        ++pushed;
        if (!ok) {
            lua.settop(L, lua.gettop(L) - 1);
            lua.pushnil(L);
            break;
        }
    }
    return pushed;
}

int WriteValues(lua_State* L, std::FILE* f, int first, int fileIdx)
{
    const int last = lua.gettop(L);
    bool ok = true;
    for (int i = first; i <= last; ++i) {
        const int t = lua.type(L, i);
        if (t != LUA_TSTRING && t != LUA_TNUMBER)
            LuaError(L, "bad argument #%d to 'write' (string expected)", i - first + 1);
        std::size_t len = 0;
        const char* s = lua.tolstring(L, i, &len);
        ok = std::fwrite(s, 1, len, f) == len && ok;
    }
    if (!ok)
        return PushError(L, "");
    if (fileIdx)
        lua.pushvalue(L, fileIdx);
    else
        lua.pushboolean(L, 1);
    return 1;
}

int FileClose(lua_State* L)
{
    LuaFile* lf = ToFile(L, 1);
    if (!lf)
        LuaError(L, "bad argument #1 to 'close' (file expected)");
    if (!lf->f)
        LuaError(L, "attempt to use a closed file");
    if (!lf->closable) {
        lua.pushnil(L);
        lua.pushstring(L, "cannot close standard file");
        return 2;
    }
    const bool pipe = lf->pipe;
    const int r = CloseFile(lf);
    lf->f = nullptr;
    if (pipe) {
        // Lua 5.2 / LuaJIT: true (or nil), "exit", status
        if (r == -1)
            return PushError(L, "");
        lua.pushboolean(L, r == 0);
        lua.pushstring(L, "exit");
        lua.pushinteger(L, r);
        return 3;
    }
    if (r != 0)
        return PushError(L, "");
    lua.pushboolean(L, 1);
    return 1;
}

int FileGc(lua_State* L)
{
    LuaFile* lf = ToFile(L, 1);
    if (lf && lf->f && lf->closable) {
        CloseFile(lf);
        lf->f = nullptr;
    }
    return 0;
}

int FileToString(lua_State* L)
{
    LuaFile* lf = ToFile(L, 1);
    char buf[64];
    if (!lf || !lf->f)
        std::snprintf(buf, sizeof(buf), "file (closed)");
    else
        std::snprintf(buf, sizeof(buf), "file (%p)", static_cast<void*>(lf->f));
    lua.pushstring(L, buf);
    return 1;
}

int FileRead(lua_State* L) { return ReadFormats(L, OpenFileArg(L, 1), 2); }
int FileWrite(lua_State* L) { return WriteValues(L, OpenFileArg(L, 1), 2, 1); }

int FileFlush(lua_State* L)
{
    if (std::fflush(OpenFileArg(L, 1)) != 0)
        return PushError(L, "");
    lua.pushvalue(L, 1);
    return 1;
}

int FileSeek(lua_State* L)
{
    std::FILE* f = OpenFileArg(L, 1);
    const char* whence = lua.type(L, 2) == LUA_TSTRING ? lua.tolstring(L, 2, nullptr) : "cur";
    const long offset = lua.type(L, 3) == LUA_TNUMBER ? static_cast<long>(lua.tointegerx(L, 3, nullptr)) : 0;
    int w = SEEK_CUR;
    if (std::strcmp(whence, "set") == 0)
        w = SEEK_SET;
    else if (std::strcmp(whence, "end") == 0)
        w = SEEK_END;
    else if (std::strcmp(whence, "cur") != 0)
        LuaError(L, "bad argument #2 to 'seek' (invalid option '%s')", whence);
    if (std::fseek(f, offset, w) != 0)
        return PushError(L, "");
    lua.pushinteger(L, static_cast<lua_Integer>(std::ftell(f)));
    return 1;
}

int FileSetvbuf(lua_State* L)
{
    OpenFileArg(L, 1);
    lua.pushboolean(L, 1);
    return 1;
}

// Iterator of file:lines() / io.lines(): upvalue 1 = file, upvalue 2 = close at end (boolean), 3 = format.
int LinesStep(lua_State* L)
{
    LuaFile* lf = ToFile(L, LuaUpvalueIndex(1));
    if (!lf || !lf->f)
        LuaError(L, "file is already closed");
    lua.settop(L, 0);
    lua.pushvalue(L, LuaUpvalueIndex(3));
    const int n = ReadFormats(L, lf->f, 1);
    if (lua.type(L, -n) == LUA_TNIL && lua.toboolean(L, LuaUpvalueIndex(2))) {
        CloseFile(lf);
        lf->f = nullptr;
    }
    return n;
}

void PushLines(lua_State* L, int fileIdx, bool closeAtEnd, int formatIdx)
{
    lua.pushvalue(L, fileIdx);
    lua.pushboolean(L, closeAtEnd);
    if (formatIdx && lua.type(L, formatIdx) != LUA_TNIL)
        lua.pushvalue(L, formatIdx);
    else
        lua.pushstring(L, "*l");
    lua.pushcclosure(L, LinesStep, 3);
}

int FileLines(lua_State* L)
{
    OpenFileArg(L, 1);
    PushLines(L, 1, false, 2);
    return 1;
}

int IoOpen(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name)
        LuaError(L, "bad argument #1 to 'open' (string expected)");
    const char* mode = lua.type(L, 2) == LUA_TSTRING ? lua.tolstring(L, 2, nullptr) : "r";
    std::string m = mode;
    if (m.find('b') == std::string::npos)
        m += 'b';  // no newline translation: same bytes on Windows and Linux
    if (m.empty() || std::strchr("rwa", m[0]) == nullptr)
        LuaError(L, "bad argument #2 to 'open' (invalid mode '%s')", mode);
    std::FILE* f = std::fopen(name, m.c_str());
    if (!f)
        return PushError(L, name);
    NewFile(L, f, true);
    return 1;
}

// io.popen(command [, mode]): the command's output ("r", text mode as LuaJIT on Windows) or input ("w").
// BuffBot lists its preset files with it.
int IoPopen(lua_State* L)
{
    const char* cmd = lua.tolstring(L, 1, nullptr);
    if (!cmd)
        LuaError(L, "bad argument #1 to 'popen' (string expected)");
    const char* mode = lua.type(L, 2) == LUA_TSTRING ? lua.tolstring(L, 2, nullptr) : "r";
    if (std::strcmp(mode, "r") != 0 && std::strcmp(mode, "w") != 0)
        LuaError(L, "bad argument #2 to 'popen' (invalid mode '%s')", mode);
    std::fflush(nullptr);
#ifndef _WIN32
    if (mode[0] == 'r') {
        if (std::FILE* listing = DirListing(cmd)) {
            NewFile(L, listing, true);  // a plain temporary file: closed with fclose
            return 1;
        }
    }
#endif
    std::FILE* f = OpenPipe(cmd, mode);
    if (!f)
        return PushError(L, cmd);
    NewFile(L, f, true)->pipe = true;
    return 1;
}

int IoClose(lua_State* L)
{
    if (lua.gettop(L) == 0 || lua.type(L, 1) == LUA_TNIL) {
        lua.pushnil(L);
        lua.pushstring(L, "cannot close standard file");
        return 2;
    }
    return FileClose(L);
}

int IoType(lua_State* L)
{
    LuaFile* lf = ToFile(L, 1);
    if (!lf)
        lua.pushnil(L);
    else
        lua.pushstring(L, lf->f ? "file" : "closed file");
    return 1;
}

int IoLines(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name) {
        lua.getfield(L, LuaUpvalueIndex(1), "stdin");
        PushLines(L, lua.gettop(L), false, 0);
        return 1;
    }
    std::FILE* f = std::fopen(name, "rb");
    if (!f)
        LuaError(L, "%s: %s", name, std::strerror(errno));
    NewFile(L, f, true);
    PushLines(L, lua.gettop(L), true, 2);
    return 1;
}

int IoWrite(lua_State* L) { return WriteValues(L, stdout, 1, 0); }
int IoRead(lua_State* L) { return ReadFormats(L, stdin, 1); }

// io.output() / io.input(): the standard streams (redirection to a file is kept as given).
int IoOutput(lua_State* L)
{
    if (lua.type(L, 1) == LUA_TUSERDATA) {
        lua.pushvalue(L, 1);
        return 1;
    }
    lua.getfield(L, LuaUpvalueIndex(1), "stdout");
    return 1;
}
int IoInput(lua_State* L)
{
    if (lua.type(L, 1) == LUA_TUSERDATA) {
        lua.pushvalue(L, 1);
        return 1;
    }
    lua.getfield(L, LuaUpvalueIndex(1), "stdin");
    return 1;
}

void SetFn(lua_State* L, const char* name, lua_CFunction fn, int upvalues = 0)
{
    lua.pushcclosure(L, fn, upvalues);
    lua.setfield(L, -2, name);
}

void OpenIo(lua_State* L)
{
    lua.L_newmetatable(L, kFileMeta);
    lua.createtable(L, 0, 8);
    SetFn(L, "close", FileClose);
    SetFn(L, "flush", FileFlush);
    SetFn(L, "lines", FileLines);
    SetFn(L, "read", FileRead);
    SetFn(L, "seek", FileSeek);
    SetFn(L, "setvbuf", FileSetvbuf);
    SetFn(L, "write", FileWrite);
    lua.setfield(L, -2, "__index");
    SetFn(L, "__gc", FileGc);
    SetFn(L, "__tostring", FileToString);
    lua.settop(L, lua.gettop(L) - 1);

    lua.createtable(L, 0, 12);
    const int io = lua.gettop(L);
    NewFile(L, stdin, false);
    lua.setfield(L, io, "stdin");
    NewFile(L, stdout, false);
    lua.setfield(L, io, "stdout");
    NewFile(L, stderr, false);
    lua.setfield(L, io, "stderr");
    SetFn(L, "open", IoOpen);
    SetFn(L, "popen", IoPopen);
    SetFn(L, "close", IoClose);
    SetFn(L, "type", IoType);
    SetFn(L, "write", IoWrite);
    SetFn(L, "read", IoRead);
    lua.pushvalue(L, io);
    SetFn(L, "lines", IoLines, 1);
    lua.pushvalue(L, io);
    SetFn(L, "output", IoOutput, 1);
    lua.pushvalue(L, io);
    SetFn(L, "input", IoInput, 1);
    lua.setglobal(L, "io");
}

// --- os library ---

int OsTime(lua_State* L)
{
    if (lua.type(L, 1) != LUA_TTABLE) {
        lua.pushnumber(L, static_cast<lua_Number>(std::time(nullptr)));
        return 1;
    }
    std::tm t{};
    const auto field = [&](const char* name, int def) {
        lua.getfield(L, 1, name);
        int isnum = 0;
        const lua_Integer v = lua.tointegerx(L, -1, &isnum);
        lua.settop(L, lua.gettop(L) - 1);
        if (!isnum && def < 0)
            LuaError(L, "field '%s' missing in date table", name);
        return isnum ? static_cast<int>(v) : def;
    };
    t.tm_sec = field("sec", 0);
    t.tm_min = field("min", 0);
    t.tm_hour = field("hour", 12);
    t.tm_mday = field("day", -1);
    t.tm_mon = field("month", -1) - 1;
    t.tm_year = field("year", -1) - 1900;
    lua.getfield(L, 1, "isdst");
    t.tm_isdst = lua.type(L, -1) == LUA_TNIL ? -1 : lua.toboolean(L, -1);
    lua.settop(L, lua.gettop(L) - 1);
    const std::time_t r = std::mktime(&t);
    if (r == static_cast<std::time_t>(-1))
        lua.pushnil(L);
    else
        lua.pushnumber(L, static_cast<lua_Number>(r));
    return 1;
}

int OsDate(lua_State* L)
{
    const char* fmt = lua.type(L, 1) == LUA_TSTRING ? lua.tolstring(L, 1, nullptr) : "%c";
    const std::time_t when = lua.type(L, 2) == LUA_TNUMBER ? static_cast<std::time_t>(lua.tonumberx(L, 2, nullptr))
                                                            : std::time(nullptr);
    bool utc = false;
    if (*fmt == '!') {
        utc = true;
        ++fmt;
    }
    const std::tm* tp = utc ? std::gmtime(&when) : std::localtime(&when);
    if (!tp) {
        lua.pushnil(L);
        return 1;
    }
    const std::tm t = *tp;
    if (std::strcmp(fmt, "*t") == 0 || std::strcmp(fmt, "t") == 0) {
        lua.createtable(L, 0, 9);
        const auto set = [&](const char* k, int v) {
            lua.pushinteger(L, v);
            lua.setfield(L, -2, k);
        };
        set("sec", t.tm_sec);
        set("min", t.tm_min);
        set("hour", t.tm_hour);
        set("day", t.tm_mday);
        set("month", t.tm_mon + 1);
        set("year", t.tm_year + 1900);
        set("wday", t.tm_wday + 1);
        set("yday", t.tm_yday + 1);
        lua.pushboolean(L, t.tm_isdst > 0);
        lua.setfield(L, -2, "isdst");
        return 1;
    }
    char buf[512];
    const std::size_t n = *fmt ? std::strftime(buf, sizeof(buf), fmt, &t) : 0;
    lua.pushlstring(L, buf, n);
    return 1;
}

int OsClock(lua_State* L)
{
    lua.pushnumber(L, static_cast<lua_Number>(std::clock()) / CLOCKS_PER_SEC);
    return 1;
}

int OsDifftime(lua_State* L)
{
    lua.pushnumber(L, lua.tonumberx(L, 1, nullptr) - lua.tonumberx(L, 2, nullptr));
    return 1;
}

int OsGetenv(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const char* v = name ? std::getenv(name) : nullptr;
    if (v)
        lua.pushstring(L, v);
    else
        lua.pushnil(L);
    return 1;
}

int OsRemove(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name)
        LuaError(L, "bad argument #1 to 'remove' (string expected)");
    if (std::remove(name) != 0)
        return PushError(L, name);
    lua.pushboolean(L, 1);
    return 1;
}

int OsRename(lua_State* L)
{
    const char* from = lua.tolstring(L, 1, nullptr);
    const char* to = lua.tolstring(L, 2, nullptr);
    if (!from || !to)
        LuaError(L, "bad argument to 'rename' (string expected)");
    if (std::rename(from, to) != 0)
        return PushError(L, from);
    lua.pushboolean(L, 1);
    return 1;
}

int OsTmpname(lua_State* L)
{
    static unsigned counter = 0;
    char buf[128];
    std::snprintf(buf, sizeof(buf), "iex_tmp_%lld_%u", static_cast<long long>(std::time(nullptr)), ++counter);
    lua.pushstring(L, buf);
    return 1;
}

int OsExecute(lua_State* L)
{
    const char* cmd = lua.tolstring(L, 1, nullptr);
    if (!cmd) {
        lua.pushboolean(L, 1);  // a shell is available
        return 1;
    }
    const int r = std::system(cmd);
    if (r == 0)
        lua.pushboolean(L, 1);
    else
        lua.pushnil(L);
    lua.pushstring(L, "exit");
    lua.pushinteger(L, r);
    return 3;
}

int OsExit(lua_State* L)
{
    int code = EXIT_SUCCESS;
    if (lua.type(L, 1) == LUA_TBOOLEAN)
        code = lua.toboolean(L, 1) ? EXIT_SUCCESS : EXIT_FAILURE;
    else if (lua.type(L, 1) == LUA_TNUMBER)
        code = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    Log("os.exit(%d) called by Lua", code);
    std::exit(code);
}

void OpenOs(lua_State* L)
{
    lua.createtable(L, 0, 9);
    SetFn(L, "time", OsTime);
    SetFn(L, "date", OsDate);
    SetFn(L, "clock", OsClock);
    SetFn(L, "difftime", OsDifftime);
    SetFn(L, "getenv", OsGetenv);
    SetFn(L, "remove", OsRemove);
    SetFn(L, "rename", OsRename);
    SetFn(L, "tmpname", OsTmpname);
    SetFn(L, "execute", OsExecute);
    SetFn(L, "exit", OsExit);
    lua.setglobal(L, "os");
}

// --- bit library (LuaJIT BitOp: 32-bit operations, signed 32-bit results) ---

std::uint32_t ToBit(lua_State* L, int idx)
{
    const lua_Number n = lua.tonumberx(L, idx, nullptr);
    // the low 32 bits of the integer part, as LuaJIT's bit.tobit
    const double m = std::fmod(n, 4294967296.0);
    const long long v = static_cast<long long>(m < 0 ? m + 4294967296.0 : m);
    return static_cast<std::uint32_t>(v);
}

void PushBit(lua_State* L, std::uint32_t v)
{
    lua.pushnumber(L, static_cast<lua_Number>(static_cast<std::int32_t>(v)));
}

int BitToBit(lua_State* L) { PushBit(L, ToBit(L, 1)); return 1; }
int BitNot(lua_State* L) { PushBit(L, ~ToBit(L, 1)); return 1; }
int BitBswap(lua_State* L)
{
    const std::uint32_t v = ToBit(L, 1);
    PushBit(L, (v >> 24) | ((v >> 8) & 0xff00u) | ((v << 8) & 0xff0000u) | (v << 24));
    return 1;
}
template <int Op>
int BitFold(lua_State* L)
{
    std::uint32_t r = ToBit(L, 1);
    const int n = lua.gettop(L);
    for (int i = 2; i <= n; ++i) {
        const std::uint32_t v = ToBit(L, i);
        r = Op == 0 ? (r & v) : Op == 1 ? (r | v) : (r ^ v);
    }
    PushBit(L, r);
    return 1;
}
template <int Op>
int BitShift(lua_State* L)
{
    const std::uint32_t v = ToBit(L, 1);
    const unsigned n = ToBit(L, 2) & 31u;
    std::uint32_t r = 0;
    switch (Op) {
    case 0: r = v << n; break;                                                         // lshift
    case 1: r = v >> n; break;                                                         // rshift
    case 2: r = static_cast<std::uint32_t>(static_cast<std::int32_t>(v) >> n); break;  // arshift
    case 3: r = n ? (v << n) | (v >> (32 - n)) : v; break;                             // rol
    default: r = n ? (v >> n) | (v << (32 - n)) : v; break;                            // ror
    }
    PushBit(L, r);
    return 1;
}
int BitToHex(lua_State* L)
{
    std::uint32_t v = ToBit(L, 1);
    int n = lua.type(L, 2) == LUA_TNUMBER ? static_cast<int>(lua.tointegerx(L, 2, nullptr)) : 8;
    const bool upper = n < 0;
    if (upper)
        n = -n;
    if (n > 8)
        n = 8;
    if (n < 1)
        n = 1;
    if (n < 8)
        v &= (1u << (4 * n)) - 1;
    char buf[16];
    std::snprintf(buf, sizeof(buf), upper ? "%0*X" : "%0*x", n, v);
    lua.pushstring(L, buf);
    return 1;
}

void OpenBit(lua_State* L)
{
    lua.createtable(L, 0, 12);
    SetFn(L, "tobit", BitToBit);
    SetFn(L, "bnot", BitNot);
    SetFn(L, "band", BitFold<0>);
    SetFn(L, "bor", BitFold<1>);
    SetFn(L, "bxor", BitFold<2>);
    SetFn(L, "lshift", BitShift<0>);
    SetFn(L, "rshift", BitShift<1>);
    SetFn(L, "arshift", BitShift<2>);
    SetFn(L, "rol", BitShift<3>);
    SetFn(L, "ror", BitShift<4>);
    SetFn(L, "bswap", BitBswap);
    SetFn(L, "tohex", BitToHex);
    lua.setglobal(L, "bit");
}

// --- IEX_ReadINIFile / IEX_WriteINIFile ---

// IEX_ReadINIFile(file, section, key) -> string or nil: a value of an INI file of the game folder.
int LuaReadIniFile(lua_State* L)
{
    const char* file = lua.tolstring(L, 1, nullptr);
    const char* section = lua.tolstring(L, 2, nullptr);
    const char* key = lua.tolstring(L, 3, nullptr);
    if (!file || !section || !key || !SafeRelative(file))
        LuaError(L, "IEX_ReadINIFile: file (relative to the game folder), section and key expected");
    IniData data;
    ParseIni(g_gameDir + "/" + file, data);
    auto s = data.find(Lower(section));
    if (s != data.end()) {
        auto k = s->second.find(Lower(key));
        if (k != s->second.end()) {
            lua.pushstring(L, k->second.c_str());
            return 1;
        }
    }
    lua.pushnil(L);
    return 1;
}

// IEX_WriteINIFile(file, section, key, value) -> bool.
int LuaWriteIniFile(lua_State* L)
{
    const char* file = lua.tolstring(L, 1, nullptr);
    const char* section = lua.tolstring(L, 2, nullptr);
    const char* key = lua.tolstring(L, 3, nullptr);
    const char* value = lua.tolstring(L, 4, nullptr);
    if (!file || !section || !key || !value || !SafeRelative(file))
        LuaError(L, "IEX_WriteINIFile: file (relative to the game folder), section, key and value expected");
    lua.pushboolean(L, WriteIniValue(g_gameDir + "/" + file, section, key, value));
    return 1;
}

void PushIni(lua_State* L, const IniData& data)
{
    lua.createtable(L, 0, static_cast<int>(data.size()));
    for (const auto& s : data) {
        lua.createtable(L, 0, static_cast<int>(s.second.size()));
        for (const auto& k : s.second) {
            lua.pushstring(L, k.second.c_str());
            lua.setfield(L, -2, k.first.c_str());
        }
        lua.setfield(L, -2, s.first.c_str());
    }
}

} // namespace

void LoadSettings(const std::string& gameDir)
{
    g_gameDir = gameDir;
    g_loaderFound = ParseIni(gameDir + "/InfinityLoader.ini", g_loader);
    g_modulesFound = ParseIni(gameDir + "/EEex.ini", g_modules);
    if (g_loaderFound)
        Log("InfinityLoader.ini: LuaPatchMode=%s LogFile=%s", LoaderValue("LuaPatchMode").c_str(),
            LoaderValue("LogFile").c_str());
    if (g_modulesFound) {
        for (const auto& s : g_modules) {
            auto e = s.second.find("enable");
            if (e != s.second.end())
                Log("EEex.ini [%s] Enable=%s", s.first.c_str(), e->second.c_str());
        }
    }
}

// LuaJIT (Lua 5.1) globals mods use in EEex's LuaJIT mode: loadstring (BuffBot's preset import), unpack, and
// the coroutine library (the engine's Lua has it linked but never opens it: its functions are taken from the
// engine's own luaL_Reg array `co_funcs`, or luaopen_coroutine where the build exports it).
static void OpenLuaJitGlobals(lua_State* L)
{
    struct Alias { const char* name; const char* table; const char* field; };
    for (const Alias& a : { Alias{ "loadstring", nullptr, "load" }, Alias{ "unpack", "table", "unpack" } }) {
        lua.getglobal(L, a.name);
        const bool has = lua.type(L, -1) != LUA_TNIL;
        lua.settop(L, lua.gettop(L) - 1);
        if (has)
            continue;
        if (a.table) {
            lua.getglobal(L, a.table);
            if (lua.type(L, -1) == LUA_TTABLE)
                lua.getfield(L, -1, a.field);
            else
                lua.pushnil(L);
            lua.setglobal(L, a.name);
            lua.settop(L, lua.gettop(L) - 1);
        } else {
            lua.getglobal(L, a.field);
            lua.setglobal(L, a.name);
        }
    }
    lua.getglobal(L, "coroutine");
    const bool hasCo = lua.type(L, -1) != LUA_TNIL;
    lua.settop(L, lua.gettop(L) - 1);
    if (hasCo)
        return;
    const std::uintptr_t base = EngineImageBase();
    if (const std::uint32_t open = engineTypes.Symbol("luaopen_coroutine")) {
        reinterpret_cast<int (*)(lua_State*)>(base + open)(L);  // leaves the library table
        lua.setglobal(L, "coroutine");
        Log("coroutine library opened (luaopen_coroutine)");
        return;
    }
    const std::uint32_t reg = engineTypes.Symbol("co_funcs");
    if (!reg)
        return;
    struct Reg { const char* name; lua_CFunction fn; };
    const auto* r = reinterpret_cast<const Reg*>(base + reg);
    lua.createtable(L, 0, 6);
    int n = 0;
    for (; r->name && r->fn && n < 16; ++r, ++n) {
        lua.pushcclosure(L, r->fn, 0);
        lua.setfield(L, -2, r->name);
    }
    lua.setglobal(L, "coroutine");
    Log("coroutine library opened (%d engine functions)", n);
}

void OpenLuaSettings(lua_State* L)
{
    lua.createtable(L, 0, 4);
    PushIni(L, g_loader);
    lua.setfield(L, -2, "loader");
    PushIni(L, g_modules);
    lua.setfield(L, -2, "eeexIni");
    lua.pushboolean(L, g_loaderFound);
    lua.setfield(L, -2, "loaderFound");
    lua.pushboolean(L, g_modulesFound);
    lua.setfield(L, -2, "eeexIniFound");
    lua.setglobal(L, "IEX_Settings");

    lua.pushcclosure(L, LuaReadIniFile, 0);
    lua.setglobal(L, "IEX_ReadINIFile");
    lua.pushcclosure(L, LuaWriteIniFile, 0);
    lua.setglobal(L, "IEX_WriteINIFile");

    // EEex's LuaJIT mode (the loader replaces the engine's Lua) gives mods the io and os libraries; IEX keeps the
    // engine's Lua 5.2 and adds them, when the same InfinityLoader.ini line asks for it.
    const std::string mode = Lower(LoaderValue("LuaPatchMode"));
    if (mode == "external" || mode == "replace_internal_with_external") {
        lua.getglobal(L, "io");
        const bool hasIo = lua.type(L, -1) != LUA_TNIL;
        lua.settop(L, lua.gettop(L) - 1);
        if (!hasIo)
            OpenIo(L);
        lua.getglobal(L, "os");
        const bool hasOs = lua.type(L, -1) != LUA_TNIL;
        lua.settop(L, lua.gettop(L) - 1);
        if (!hasOs)
            OpenOs(L);
        lua.getglobal(L, "bit");
        const bool hasBit = lua.type(L, -1) != LUA_TNIL;
        lua.settop(L, lua.gettop(L) - 1);
        if (!hasBit)
            OpenBit(L);
        OpenLuaJitGlobals(L);
        Log("LuaPatchMode=%s: Lua io / os / bit libraries opened", LoaderValue("LuaPatchMode").c_str());
    }

    const std::string logFile = LoaderValue("LogFile");
    if (!logFile.empty() && SafeRelative(logFile) && !g_printLog) {
        g_printLog = std::fopen((g_gameDir + "/" + logFile).c_str(), "w");
        if (g_printLog) {
            lua.getglobal(L, "print");
            lua.pushcclosure(L, LuaPrintMirror, 1);
            lua.setglobal(L, "print");
            Log("LogFile=%s: print() output mirrored there", logFile.c_str());
        }
    }
}

} // namespace iex
