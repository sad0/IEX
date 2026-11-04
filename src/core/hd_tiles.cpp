#include "hd_tiles.h"

#include "callsite_hook.h"
#include "hd_mips.h"
#include "engine_types.h"
#include "hook_points.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "platform_memory.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace iex {

namespace {

constexpr const char* kRenderTexture = "_ZN8CVidTile13RenderTextureEiRK5CRectiij";
constexpr const char* kDrawTexCoord = "_Z12DrawTexCoordii";
constexpr const char* kDrawColorTone = "_Z13DrawColorTone8DrawTone";
constexpr const char* kDrawGetRenderer = "_Z15DrawGetRendererv";
constexpr const char* kSetTile = "_ZN11CResTileSet7SetTileEP8CResTilei";
constexpr const char* kChitin = "g_pChitin";
constexpr const char* kGenTexture = "_Z14DrawGenTexture10DrawFilterb8DrawWrapb";
constexpr const char* kTexImage = "_Z24DrawCompressedTexImage2DiiiiPKv";
constexpr const char* kCreateProgram = "_Z20DrawCreateProgram_GLiPKcS0_";

// Engine layouts (both builds, own analysis: CVidTile::RenderTexture Lin 0x5b9170 / Win 0x4257c0,
// CResTileSet::Parse Lin 0x571e50 / Win 0x3f8b50, CResTileSet::SetTile Lin 0x5838b0 / Win 0x3f9550).
constexpr std::size_t kVidTileRes = 0x100;    // CVidTile: CResTile* of the tile being drawn
constexpr std::size_t kResTileSet = 0x0;      // CResTile: CResTileSet*
constexpr std::size_t kResTileIndex = 0x8;    // CResTile: tile index (int)
constexpr std::size_t kResTilePvr = 0x10;     // CResTile: CResPVR* of its page (CResTileSet::SetTile)
constexpr std::size_t kChitinSmooth = 0x1dc;  // CChitin: 1 = "Use Nearest Neighbour Scaling" off (seam shader)
constexpr std::uint32_t kGlNearest = 0x2600, kGlLinear = 0x2601;
constexpr std::size_t kSetName = 0x8;         // CRes: resref text (char*)
constexpr std::size_t kSetEntries = 0x40;     // CResTileSet: first tile entry (file data + 0x18)
constexpr std::size_t kSetTileLength = 0x48;  // CResTileSet: header +0x0c, 12 for PVRZ entries
constexpr std::uint32_t kPvrzEntry = 12;
constexpr int kToneSeam = 8;   // DrawColorTone value of the tile seam shader (fpSEAM)
constexpr int kTonePlain = 0;  // fpDraw
constexpr int kRendererD3D9 = 1;
constexpr int kSeamProgram = 8;  // DrawInit_GL: DrawCreateProgram_GL(8, "vpDraw", "fpSEAM")

// GL constants (public OpenGL headers)
constexpr unsigned kGlTexture2D = 0x0DE1, kGlMinFilter = 0x2801, kGlMaxLevel = 0x813D, kGlInternalFormat = 0x1003;
constexpr unsigned kGlNearestMipNearest = 0x2700, kGlLinearMipLinear = 0x2703;
constexpr unsigned kGlDxt1Rgb = 0x83F0, kGlDxt1Rgba = 0x83F1, kGlDxt5 = 0x83F3;
// PVR pixel formats the engine passes to DrawCompressedTexImage2D (DXT1 = 7, DXT5 = 11)
constexpr int kPvrDxt1 = 7, kPvrDxt5 = 11;
// Filter field value IEX writes into an HD page's CResPVR (read only by the hooked DrawGenTexture calls):
// 'IE' tag, mode (1 = trilinear, 0 = nearest mip), log2(scale).
constexpr std::uint32_t kMarkTag = 0x49450000;

using RenderFn = void (*)(void* vidTile, int texture, const void* rect, int x, int y, unsigned flags);
using TexCoordFn = void (*)(int u, int v);
using ToneFn = void (*)(int tone);
using RendererFn = int (*)();
using SetTileFn = void (*)(void* set, void* resTile, int index);
using GenTextureFn = int (*)(int filter, int mip, int wrap, int b);
using TexImageFn = std::uintptr_t (*)(int w, int h, int format, int size, const void* data);
using CreateProgramFn = bool (*)(int slot, const char* vs, const char* fs);
using ShaderSourceFn = void (*)(unsigned shader, int count, const char* const* text, const int* length);
using TexParamFn = void (*)(unsigned target, unsigned name, int value);
using GetLevelParamFn = void (*)(unsigned target, int level, unsigned name, int* value);
using CompressedFn = void (*)(unsigned target, int level, unsigned fmt, int w, int h, int border, int size,
                              const void* data);

RenderFn g_render = nullptr;
TexCoordFn g_texCoord = nullptr;
ToneFn g_tone = nullptr;
RendererFn g_renderer = nullptr;
SetTileFn g_setTile = nullptr;
std::uintptr_t g_chitinPtr = 0;        // address of g_pChitin
std::uint32_t g_pvrFilterOffset = 0;   // CResPVR: GL filter given to DrawGenTexture (Lin 0x5c, Win 0x60)
std::uint64_t g_linearPages = 0;

// Mipmaps of HD pages (hooks on the DrawGenTexture / DrawCompressedTexImage2D calls of CResPVR).
GenTextureFn g_genTexture = nullptr;
TexImageFn g_texImage = nullptr;
TexParamFn g_glTexParameteri = nullptr;
GetLevelParamFn g_glGetTexLevelParameteriv = nullptr;
CompressedFn g_glCompressedTexImage2D = nullptr;
bool g_mips = false;     // hooks + GL entry points ready
int g_pendingMark = -1;
int g_pendingSlot = -1;   // its texture slot  // mode << 8 | log2 scale of the texture DrawGenTexture just created
std::uint64_t g_mipPages = 0, g_mipLevels = 0, g_mipSkipped = 0;
double g_mipBuildMs = 0, g_mipUploadMs = 0, g_lastEngineUploadMs = 0;
std::chrono::steady_clock::time_point g_genAt;  // DrawGenTexture of the marked page (CResPVR::Demand inflates after it)

// HD-aware seam program (program 8 sources rewritten while the engine compiles them).
CreateProgramFn g_createProgram = nullptr;
ShaderSourceFn g_shaderSource = nullptr;  // the real glShaderSource
std::uintptr_t g_shaderSourcePtr = 0;     // Windows: address of the engine's glShaderSource pointer
bool g_inSeam = false, g_seamHd = false, g_seamTried = false;
int g_seamRewritten = 0;

// The HD tile being drawn (render thread only; set around one engine RenderTexture call).
struct Current {
    bool on = false;
    int u0 = 0, v0 = 0, scale = 1;
};
Current g_cur;

std::uint64_t g_hdDraws = 0, g_plainDraws = 0;
bool g_d3dLogged = false;
std::vector<const void*> g_seenSets;  // tile sets already logged

template <class T> T Read(const void* p, std::size_t off)
{
    T v;
    std::memcpy(&v, static_cast<const std::uint8_t*>(p) + off, sizeof(T));
    return v;
}

int ScaleOfSize(std::uint32_t size)
{
    switch (size) {
    case 128: return 2;
    case 256: return 4;
    case 512: return 8;
    default: return 1;
    }
}

// Scale of a tile set: 2/4/8 for a PVRZ-based TIS with tile size 128/256/512, else 1.
int SetScale(const void* set)
{
    if (!set || Read<std::uint32_t>(set, kSetTileLength) != kPvrzEntry)
        return 1;
    const auto* entries = Read<const std::uint8_t*>(set, kSetEntries);
    if (!entries)
        return 1;
    // CResTileSet::Parse checked "TIS V1  " at the start of the data and points the entries 0x18 bytes after it.
    const std::uint8_t* header = entries - 0x18;
    if (std::memcmp(header, "TIS V1  ", 8) != 0)
        return 1;
    const std::uint32_t size = Read<std::uint32_t>(header, 0x14);
    const int scale = ScaleOfSize(size);
    bool seen = false;
    for (const void* s : g_seenSets)
        if (s == set) {
            seen = true;
            break;
        }
    if (!seen && g_seenSets.size() < 4096) {
        g_seenSets.push_back(set);
        const char* name = Read<const char*>(set, kSetName);
        if (scale != 1 || size != 64)
            Log("HD tiles: %.8s tile size %u -> %s", name ? name : "?", size,
                scale != 1 ? (scale == 2 ? "2x" : scale == 4 ? "4x" : "8x") : "1x (not 128/256/512)");
    }
    return scale;
}

// Scale of the tile the CVidTile is about to draw (1 = engine as is) and its texel origin in the PVRZ page.
int TileScale(const void* vidTile, int& u0, int& v0)
{
    const void* tile = Read<const void*>(vidTile, kVidTileRes);
    if (!tile)
        return 1;
    const void* set = Read<const void*>(tile, kResTileSet);
    const int scale = SetScale(set);
    if (scale == 1)
        return 1;
    const auto* entries = Read<const std::uint8_t*>(set, kSetEntries);
    if (g_renderer && g_renderer() == kRendererD3D9) {
        if (!g_d3dLogged) {
            g_d3dLogged = true;
            Log("HD tiles: Direct3D 9 backend (Baldur.lua Graphics/Backend 1): HD tiles need OpenGL, drawn at 1x");
        }
        return 1;
    }
    const int index = Read<int>(tile, kResTileIndex);
    if (index < 0)
        return 1;
    const std::uint8_t* e = entries + static_cast<std::size_t>(index) * kPvrzEntry;
    u0 = Read<int>(e, 4);
    v0 = Read<int>(e, 8);
    return scale;
}

void PollMipJobs();

// Replaces the CVidTile::RenderTexture calls of CInfTileSet::Render. Same ABI on both platforms.
void HookRenderTexture(void* vidTile, int texture, const void* rect, int x, int y, unsigned flags)
{
    PollMipJobs();
    int u0 = 0, v0 = 0;
    // texture 0 = untextured black quad, no texture coordinates
    const int scale = texture != 0 ? TileScale(vidTile, u0, v0) : 1;
    if (scale == 1) {
        ++g_plainDraws;
        g_render(vidTile, texture, rect, x, y, flags);
        return;
    }
    ++g_hdDraws;
    g_cur.u0 = u0;
    g_cur.v0 = v0;
    g_cur.scale = scale;
    g_cur.on = true;
    g_render(vidTile, texture, rect, x, y, flags);
    g_cur.on = false;
}

// The DrawTexCoord calls of CVidTile::RenderTexture: corners x / x+64, y / y+64 -> x / x+64*scale.
void HookTexCoord(int u, int v)
{
    if (g_cur.on) {
        u = g_cur.u0 + (u - g_cur.u0) * g_cur.scale;
        v = g_cur.v0 + (v - g_cur.v0) * g_cur.scale;
    }
    g_texCoord(u, v);
}

// The DrawColorTone calls of CVidTile::RenderTexture: the engine's fpSEAM works on 64-texel tiles and 1-texel
// neighbours. Without the HD-aware seam program (its sources could not be rewritten), an HD tile is drawn with the
// plain shader instead.
void HookTone(int tone)
{
    if (g_cur.on && tone == kToneSeam && !g_seamHd)
        tone = kTonePlain;
    g_tone(tone);
}

bool SmoothScaling()
{
    const void* chitin = g_chitinPtr ? Read<const void*>(reinterpret_cast<const void*>(g_chitinPtr), 0) : nullptr;
    return chitin && Read<std::int32_t>(chitin, kChitinSmooth) != 0;
}

// --- HD-aware seam program ---

// Rewrites the engine's own sources (game resources vpDraw / fpSEAM, or a shader mod's): the original main() is kept
// under another name and still draws everything whose texel / world ratio is 1 (all 1x drawing: same code, same
// result); a new main() handles HD tiles. Returns false (source unchanged) when the expected names are missing.
const char kSeamFsHd[] = R"GLSL(
varying highp vec2 vIexPos;
void main()
{
	highp vec2 iexT = vTc / uTcScale;
	highp float iexDp = abs(dFdx(vIexPos.x)) + abs(dFdy(vIexPos.x));
	highp float iexDt = abs(dFdx(iexT.x)) + abs(dFdy(iexT.x));
	highp float iexR = iexDp > 0.0 ? iexDt / iexDp : 1.0;
	if (iexR < 1.5)
	{
		iexSeam1x();
		return;
	}
	// HD tile: 64 world px = 64 * scale texels from the tile origin (vRef). Hardware trilinear filtering of the
	// mipmapped page; the sample point stays half a texel (of the sampled level) inside the tile, so no texel of
	// the atlas neighbour is blended in.
	highp float iexSpan = 64.0 * exp2(floor(log2(iexR) + 0.5));
	highp vec2 iexRef = vRef / uTcScale;
	highp float iexRho = max(length(dFdx(iexT)), length(dFdy(iexT)));
	highp float iexH = 0.5 * max(iexRho, 1.0);
	highp vec2 iexC = clamp(iexT, iexRef + vec2(iexH), iexRef + vec2(iexSpan - iexH));
	vec4 iexColor = texture2D(uTex, iexC * uTcScale) * vColor;
	float iexGrey = dot(iexColor.rgb, vec3(0.299, 0.587, 0.114));
	vec3 iexTone = iexGrey * uColorTone.rgb;
	gl_FragColor = vec4(mix(iexColor.rgb, iexTone, uColorTone.a), iexColor.a);
}
)GLSL";

const char kSeamVsHd[] = R"GLSL(
varying highp vec2 vIexPos;
void main()
{
	iexMain0();
	vIexPos = aPos;
}
)GLSL";

bool Rename(std::string& src, const char* from, const char* to)
{
    const std::size_t at = src.find(from);
    if (at == std::string::npos || src.find(from, at + 1) != std::string::npos)
        return false;
    src.replace(at, std::strlen(from), to);
    return true;
}

bool RewriteSeam(std::string& src)
{
    if (src.find("gl_FragColor") != std::string::npos) {
        for (const char* need : {"vTc", "vRef", "uTcScale", "uTex", "uColorTone", "vColor"})
            if (src.find(need) == std::string::npos)
                return false;
        if (!Rename(src, "void main()", "void iexSeam1x()"))
            return false;
        src += kSeamFsHd;
        return true;
    }
    if (src.find("aPos") == std::string::npos || src.find("gl_Position") == std::string::npos)
        return false;
    if (!Rename(src, "void main()", "void iexMain0()"))
        return false;
    src += kSeamVsHd;
    return true;
}

std::string g_seamText[2];
int g_seamCalls = 0;

// glShaderSource while the engine builds program 8 (Linux: its 2 call sites; Windows: the engine's pointer, swapped
// for the duration of that one DrawCreateProgram_GL call).
void WrapShaderSource(unsigned shader, int count, const char* const* text, const int* length)
{
    if (!g_inSeam || g_seamCalls >= 2) {
        g_shaderSource(shader, count, text, length);
        return;
    }
    std::string& keep = g_seamText[g_seamCalls++];
    keep.clear();
    for (int i = 0; i < count; ++i)
        keep.append(text[i], length && length[i] >= 0 ? static_cast<std::size_t>(length[i]) : std::strlen(text[i]));
    if (RewriteSeam(keep)) {
        ++g_seamRewritten;
        const char* p = keep.c_str();
        g_shaderSource(shader, 1, &p, nullptr);
        return;
    }
    g_shaderSource(shader, count, text, length);
}

// The DrawCreateProgram_GL call of DrawInit_GL for program 8, and IEX's own rebuild of it.
bool HookCreateProgram(int slot, const char* vs, const char* fs)
{
    if (slot == kSeamProgram && g_shaderSourcePtr) {
        // Windows: the engine's pointer must hold the GL library's glShaderSource of the current context.
        std::uintptr_t cur = 0;
        std::memcpy(&cur, reinterpret_cast<void*>(g_shaderSourcePtr), sizeof(cur));
        const auto gl = reinterpret_cast<std::uintptr_t>(platform::GlProc("glShaderSource"));
        if (cur && cur == gl && cur != reinterpret_cast<std::uintptr_t>(&WrapShaderSource)) {
            g_shaderSource = reinterpret_cast<ShaderSourceFn>(cur);
        } else {
            Log("HD tiles: engine glShaderSource pointer not recognised (0x%llx, GL 0x%llx), seam program left as is",
                static_cast<unsigned long long>(cur), static_cast<unsigned long long>(gl));
            g_shaderSource = nullptr;
            g_shaderSourcePtr = 0;
        }
    }
    if (slot != kSeamProgram || !g_shaderSource)
        return g_createProgram(slot, vs, fs);
    g_inSeam = true;
    g_seamCalls = 0;
    g_seamRewritten = 0;
    std::uintptr_t saved = 0;
    if (g_shaderSourcePtr) {
        std::memcpy(&saved, reinterpret_cast<void*>(g_shaderSourcePtr), sizeof(saved));
        const auto mine = reinterpret_cast<std::uintptr_t>(&WrapShaderSource);
        std::memcpy(reinterpret_cast<void*>(g_shaderSourcePtr), &mine, sizeof(mine));
    }
    bool ok = g_createProgram(slot, vs, fs);
    if (g_shaderSourcePtr)
        std::memcpy(reinterpret_cast<void*>(g_shaderSourcePtr), &saved, sizeof(saved));
    g_inSeam = false;
    if (!ok && g_seamRewritten) {
        Log("HD tiles: the HD-aware seam program did not build; engine program 8 rebuilt as is (HD tiles use fpDraw)");
        ok = g_createProgram(slot, vs, fs);
        g_seamHd = false;
    } else {
        g_seamHd = ok && g_seamRewritten == 2;
        Log("HD tiles: seam program %s", g_seamHd ? "HD-aware (engine fpSEAM for 1x, clamped trilinear for HD tiles)"
                                                : "left as is (sources not recognised; HD tiles use fpDraw)");
    }
    return ok;
}

// --- Mipmaps of HD pages ---

// The DrawGenTexture calls of CResPVR::Demand / CreateTexture: the filter comes from the CResPVR, where HookSetTile
// put IEX's mark for HD pages. The engine gets the real filter; the following upload builds the mip chain.
int HookGenTexture(int filter, int mip, int wrap, int b)
{
    const auto f = static_cast<std::uint32_t>(filter);
    if ((f & 0xFFFF0000u) != kMarkTag)
        return g_genTexture(filter, mip, wrap, b);
    g_pendingMark = static_cast<int>(f & 0xFFFF);
    g_genAt = std::chrono::steady_clock::now();
    const bool trilinear = ((f >> 8) & 0xFF) != 0;
    g_pendingSlot = g_genTexture(static_cast<int>(trilinear ? kGlLinear : kGlNearest), mip, wrap, b);
    return g_pendingSlot;
}

// --- Mip attachment off the render thread ---
//
// A page whose PVRZ carries its own mip levels gets them uploaded at once (nothing built). Otherwise level 0 is copied,
// a worker thread builds the chain, and the render thread attaches it a few frames later (one page per poll); level 0
// is drawn meanwhile (GL_LINEAR, GL_TEXTURE_MAX_LEVEL 0). GL is only called on the render thread.
// Texture reuse: the engine may delete the texture (page cache eviction, area unload) and GL may hand its name to
// another texture before the chain is ready. Each pending texture carries a stamp in GL_TEXTURE_MIN_LOD (a value no
// engine texture uses; GL's default is -1000); the chain is attached only if glIsTexture is true and the stamp, size
// and format still match. A fresh texture on a reused name has the default MIN_LOD and is left alone.

using GetIntFn = void (*)(unsigned name, int* value);
using BindFn = void (*)(unsigned target, unsigned texture);
using IsTexFn = unsigned char (*)(unsigned texture);
using TexParamfFn = void (*)(unsigned target, unsigned name, float value);
using GetTexParamfFn = void (*)(unsigned target, unsigned name, float* value);
GetIntFn g_glGetIntegerv = nullptr;
BindFn g_glBindTexture = nullptr;
IsTexFn g_glIsTexture = nullptr;
TexParamfFn g_glTexParameterf = nullptr;
GetTexParamfFn g_glGetTexParameterfv = nullptr;
using CompressedSubFn = void (*)(unsigned target, int level, int x, int y, int w, int h, unsigned fmt, int size,
                                 const void* data);
CompressedSubFn g_glCompressedTexSubImage2D = nullptr;
constexpr std::size_t kAttachChunk = 256 * 1024;  // bytes uploaded per attach step
constexpr unsigned kGlTextureBinding2D = 0x8069, kGlMinLod = 0x813A, kGlWidth = 0x1000, kGlHeight = 0x1001;
constexpr float kGlDefaultMinLod = -1000.0f;
constexpr unsigned kGlMagFilter = 0x2800, kGlWrapS = 0x2802, kGlWrapT = 0x2803, kGlActiveTexture = 0x84E0,
                   kGlTexture0 = 0x84C0;
using GenTexFn = void (*)(int n, unsigned* names);
using DelTexFn = void (*)(int n, const unsigned* names);
using GetTexParamiFn = void (*)(unsigned target, unsigned name, int* value);
using ActiveTexFn = void (*)(unsigned unit);
GenTexFn g_glGenTextures = nullptr;
DelTexFn g_glDeleteTextures = nullptr;
GetTexParamiFn g_glGetTexParameteriv = nullptr;
ActiveTexFn g_glActiveTexture = nullptr;
// The draw layer's texture slot table (build constant IEX.hdTiles.texSlots): 512 slots of 0x28 bytes, GL name at +0.
std::uintptr_t g_texSlots = 0;
constexpr int kTexSlots = 512;
constexpr std::uintptr_t kTexSlotStride = 0x28;

struct MipJob {
    std::uint32_t id = 0;
    unsigned texture = 0;  // GL name
    int w = 0, h = 0, internal = 0, levels = 0;
    bool trilinear = true;
    mips::Format fmt = mips::Format::BC1;
    std::vector<std::uint8_t> level0;
    std::vector<std::vector<std::uint8_t>> out;
    std::vector<int> ow, oh;
    double buildMs = 0;
    int slot = -1;                     // engine texture slot (DrawGenTexture result)
    unsigned newTexture = 0;           // the mipmapped copy IEX builds, swapped into the slot when complete
    int magFilter = 0, wrapS = 0, wrapT = 0;  // the engine texture's parameters, copied to the new one
    std::chrono::steady_clock::time_point queued;
};

std::mutex g_jobMutex;
std::condition_variable g_jobCv;
std::deque<std::unique_ptr<MipJob>> g_todo, g_done;
std::atomic<int> g_doneCount{0};
std::uint32_t g_nextJob = 1;
bool g_workerStarted = false;
std::uint64_t g_mipAttached = 0, g_mipDropped = 0, g_mipFromFile = 0;
double g_renderMaxMs = 0;  // longest render-thread time spent on one HD page (upload hook or attach)

float StampOf(std::uint32_t id)
{
    return -2000.0f - static_cast<float>(id % 100000);
}

void Worker()
{
    for (;;) {
        std::unique_ptr<MipJob> job;
        {
            std::unique_lock<std::mutex> lock(g_jobMutex);
            g_jobCv.wait(lock, [] { return !g_todo.empty(); });
            job = std::move(g_todo.front());
            g_todo.pop_front();
        }
        const auto t0 = std::chrono::steady_clock::now();
        mips::Build(job->fmt, job->w, job->h, job->level0.data(), job->levels, job->out, job->ow, job->oh);
        job->buildMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        {
            std::lock_guard<std::mutex> lock(g_jobMutex);
            g_done.push_back(std::move(job));
        }
        g_doneCount.fetch_add(1, std::memory_order_release);
    }
}

double MsSince(std::chrono::steady_clock::time_point t)
{
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count();
}

// IEX's own render-thread time for one HD page step (level-0 copy, one attach step); the engine's own upload and
// PVRZ inflate are not included. A new maximum is logged (at most 10 times).
void NoteRenderTime(double ms, const char* what)
{
    if (ms <= g_renderMaxMs)
        return;
    g_renderMaxMs = ms;
    static int logged = 0;
    if (++logged <= 10)
        Log("HD tiles: longest IEX render-thread step so far: %.1f ms (%s)", ms, what);
}


// Render thread, between tile draws. The chain is never written into the texture the engine draws with (drivers
// stall or copy when a texture in use gets new levels): IEX builds a NEW texture with every level, in bands of at
// most kAttachChunk bytes, at most one band every 4 ms, then swaps its GL name into the engine's texture slot and
// deletes the old texture. Checks before the first band and before the swap: the old texture still exists, carries
// this job's stamp and is still the slot's texture; otherwise the new texture is deleted and the job dropped.
std::unique_ptr<MipJob> g_attaching;
std::size_t g_attachLevel = 0;  // 0 = level 0, i = mip level i
int g_attachRow = 0;            // next block row of that level
int g_attachSteps = 0;
double g_attachMs = 0;
std::chrono::steady_clock::time_point g_lastAttach;

unsigned* SlotName(int slot)
{
    if (!g_texSlots || slot < 0 || slot >= kTexSlots)
        return nullptr;
    return reinterpret_cast<unsigned*>(g_texSlots + static_cast<std::uintptr_t>(slot) * kTexSlotStride);
}

bool OldStillValid(const MipJob& job)
{
    const unsigned* slot = SlotName(job.slot);
    if (!slot || *slot != job.texture || !g_glIsTexture(job.texture))
        return false;
    g_glBindTexture(kGlTexture2D, job.texture);
    float stamp = 0;
    g_glGetTexParameterfv(kGlTexture2D, kGlMinLod, &stamp);
    return stamp == StampOf(job.id);
}

void FinishJob(bool attached)
{
    MipJob& job = *g_attaching;
    if (attached) {
        ++g_mipAttached;
        ++g_mipPages;
        g_mipLevels += job.out.size();
        g_mipBuildMs += job.buildMs;
    } else {
        ++g_mipDropped;
        if (job.newTexture)
            g_glDeleteTextures(1, &job.newTexture);
    }
    if (g_mipAttached + g_mipDropped <= 6)
        Log("HD tiles: mips of a %dx%d page %s: %zu levels built in %.0f ms on the worker, new texture filled on the "
            "render thread in %d steps, %.1f ms in all, %.0f ms after the upload", job.w, job.h,
            attached ? "swapped in" : "dropped (texture gone or reused)", job.out.size(), job.buildMs, g_attachSteps,
            g_attachMs, MsSince(job.queued));
    g_attaching.reset();
}

void PollMipJobs()
{
    if (!g_attaching) {
        if (g_doneCount.load(std::memory_order_acquire) == 0)
            return;
        std::lock_guard<std::mutex> lock(g_jobMutex);
        if (g_done.empty())
            return;
        g_attaching = std::move(g_done.front());
        g_done.pop_front();
        g_doneCount.fetch_sub(1, std::memory_order_acq_rel);
        g_attachLevel = 0;
        g_attachRow = 0;
        g_attachSteps = 0;
        g_attachMs = 0;
    }
    const auto t0 = std::chrono::steady_clock::now();
    if (std::chrono::duration<double, std::milli>(t0 - g_lastAttach).count() < 4.0)
        return;
    g_lastAttach = t0;
    ++g_attachSteps;
    MipJob& job = *g_attaching;
    const unsigned fmt = static_cast<unsigned>(job.internal);
    const std::size_t levels = job.out.size();
    int previous = 0;
    g_glGetIntegerv(kGlTextureBinding2D, &previous);
    int outcome = 0;  // 0 = continue, 1 = attached, -1 = dropped
    const char* what = "mip texture fill step";
    if (!job.newTexture) {
        // First step: the slot must still hold the job's texture (no GL query); create the new texture with every
        // level allocated.
        what = "mip texture create step";
        const unsigned* slot = SlotName(job.slot);
        if (!slot || *slot != job.texture) {
            outcome = -1;
        } else {
            g_glGenTextures(1, &job.newTexture);
            g_glBindTexture(kGlTexture2D, job.newTexture);
            g_glTexParameteri(kGlTexture2D, kGlMagFilter, job.magFilter);
            g_glTexParameteri(kGlTexture2D, kGlWrapS, job.wrapS);
            g_glTexParameteri(kGlTexture2D, kGlWrapT, job.wrapT);
            g_glTexParameteri(kGlTexture2D, kGlMaxLevel, static_cast<int>(levels));
            g_glTexParameteri(kGlTexture2D, kGlMinFilter,
                              static_cast<int>(job.trilinear ? kGlLinearMipLinear : kGlNearestMipNearest));
            g_glCompressedTexImage2D(kGlTexture2D, 0, fmt, job.w, job.h, 0, static_cast<int>(job.level0.size()), nullptr);
            for (std::size_t i = 0; i < levels; ++i)
                g_glCompressedTexImage2D(kGlTexture2D, static_cast<int>(i + 1), fmt, job.ow[i], job.oh[i], 0,
                                         static_cast<int>(job.out[i].size()), nullptr);
        }
    } else if (g_attachLevel <= levels) {
        // One band of one level of the new texture (not drawn yet: no driver wait).
        const std::size_t i = g_attachLevel;
        const int lw = i == 0 ? job.w : job.ow[i - 1], lh = i == 0 ? job.h : job.oh[i - 1];
        const std::vector<std::uint8_t>& src = i == 0 ? job.level0 : job.out[i - 1];
        const std::size_t rowBytes = static_cast<std::size_t>((lw + 3) / 4) * (job.fmt == mips::Format::BC1 ? 8 : 16);
        const int blockRows = (lh + 3) / 4;
        const int band = std::max(1, static_cast<int>(kAttachChunk / rowBytes));
        const int rows = std::min(band, blockRows - g_attachRow);
        g_glBindTexture(kGlTexture2D, job.newTexture);
        g_glCompressedTexSubImage2D(kGlTexture2D, static_cast<int>(i), 0, g_attachRow * 4, lw,
                                    std::min(rows * 4, lh - g_attachRow * 4), fmt, static_cast<int>(rows * rowBytes),
                                    src.data() + g_attachRow * rowBytes);
        g_attachRow += rows;
        if (g_attachRow >= blockRows) {
            ++g_attachLevel;
            g_attachRow = 0;
        }
    } else {
        what = "mip texture swap step";
        // Last step: swap the new texture into the engine's slot, rebind it where the old one was bound, delete the old.
        if (!OldStillValid(job)) {
            outcome = -1;
        } else {
            *SlotName(job.slot) = job.newTexture;
            int active = 0;
            g_glGetIntegerv(kGlActiveTexture, &active);
            for (unsigned unit = 0; unit < 2; ++unit) {
                g_glActiveTexture(kGlTexture0 + unit);
                int bound = 0;
                g_glGetIntegerv(kGlTextureBinding2D, &bound);
                if (static_cast<unsigned>(bound) == job.texture)
                    g_glBindTexture(kGlTexture2D, job.newTexture);
            }
            g_glActiveTexture(static_cast<unsigned>(active));
            if (static_cast<unsigned>(previous) == job.texture)
                previous = static_cast<int>(job.newTexture);
            g_glDeleteTextures(1, &job.texture);
            outcome = 1;
        }
    }
    g_glBindTexture(kGlTexture2D, static_cast<unsigned>(previous));
    const double ms = MsSince(t0);
    g_attachMs += ms;
    g_mipUploadMs += ms;
    NoteRenderTime(ms, what);
    if (outcome != 0)
        FinishJob(outcome > 0);
}

bool ResolveGl()
{
    if (g_glCompressedTexImage2D)
        return true;
    g_glTexParameteri = reinterpret_cast<TexParamFn>(platform::GlProc("glTexParameteri"));
    g_glGetTexLevelParameteriv = reinterpret_cast<GetLevelParamFn>(platform::GlProc("glGetTexLevelParameteriv"));
    g_glGetIntegerv = reinterpret_cast<GetIntFn>(platform::GlProc("glGetIntegerv"));
    g_glBindTexture = reinterpret_cast<BindFn>(platform::GlProc("glBindTexture"));
    g_glIsTexture = reinterpret_cast<IsTexFn>(platform::GlProc("glIsTexture"));
    g_glTexParameterf = reinterpret_cast<TexParamfFn>(platform::GlProc("glTexParameterf"));
    g_glGetTexParameterfv = reinterpret_cast<GetTexParamfFn>(platform::GlProc("glGetTexParameterfv"));
    g_glCompressedTexSubImage2D = reinterpret_cast<CompressedSubFn>(platform::GlProc("glCompressedTexSubImage2D"));
    g_glGenTextures = reinterpret_cast<GenTexFn>(platform::GlProc("glGenTextures"));
    g_glDeleteTextures = reinterpret_cast<DelTexFn>(platform::GlProc("glDeleteTextures"));
    g_glGetTexParameteriv = reinterpret_cast<GetTexParamiFn>(platform::GlProc("glGetTexParameteriv"));
    g_glActiveTexture = reinterpret_cast<ActiveTexFn>(platform::GlProc("glActiveTexture"));
    auto* c = reinterpret_cast<CompressedFn>(platform::GlProc("glCompressedTexImage2D"));
    if (!g_glTexParameteri || !g_glGetTexLevelParameteriv || !g_glGetIntegerv || !g_glBindTexture || !g_glIsTexture ||
        !g_glTexParameterf || !g_glGetTexParameterfv || !g_glCompressedTexSubImage2D || !g_glGenTextures ||
        !g_glDeleteTextures || !g_glGetTexParameteriv || !g_glActiveTexture || !c)
        return false;
    g_glCompressedTexImage2D = c;
    return true;
}

// The DrawCompressedTexImage2D calls of CResPVR::Demand / CreateTexture (level 0, the bound texture).
std::uintptr_t HookTexImage(int w, int h, int format, int size, const void* data)
{
    const int mark = g_pendingMark;
    g_pendingMark = -1;
    const bool bc1 = format == kPvrDxt1, bc3 = format == kPvrDxt5;
    if (mark < 0 || !g_mips || !data || size < 0 || !(bc1 || bc3))
        return g_texImage(w, h, format, size, data);
    const auto t0 = std::chrono::steady_clock::now();
    const double inflateMs = std::chrono::duration<double, std::milli>(t0 - g_genAt).count();
    const mips::Format fmt = bc1 ? mips::Format::BC1 : mips::Format::BC3;
    const std::size_t size0 = mips::LevelSize(fmt, w, h);
    // Mip levels stored in the file (PVR3 body = level 0, 1, 2... of one surface): how many fit exactly?
    std::vector<std::size_t> fileLevels;  // offsets of levels 1..n
    if (static_cast<std::size_t>(size) > size0) {
        std::size_t off = size0;
        int lw = w, lh = h;
        while (off < static_cast<std::size_t>(size) && lw > 1 && lh > 1) {
            lw = std::max(1, lw / 2);
            lh = std::max(1, lh / 2);
            fileLevels.push_back(off);
            off += mips::LevelSize(fmt, lw, lh);
        }
        if (off != static_cast<std::size_t>(size))
            fileLevels.clear();
    }
    const int log2Scale = mark & 0xFF;
    const bool trilinear = ((mark >> 8) & 0xFF) != 0;
    // Level 0 only to the engine (with stored mips the body is bigger than level 0, which GL would refuse).
    const std::uintptr_t r = g_texImage(w, h, format, fileLevels.empty() ? size : static_cast<int>(size0), data);
    g_lastEngineUploadMs = MsSince(t0);
    if (!ResolveGl() || !g_texSlots) {
        if (g_mips)
            Log("HD tiles: GL entry points or the texture slot table missing, HD pages stay linear-filtered without mips");
        g_mips = false;
        return r;
    }
    // GL state queries can make some drivers wait for the GPU (seen on WSLg): the texture parameters every CResPVR
    // page gets (same DrawGenTexture arguments) and the internal format per PVR format are read once and reused; the
    // GL name comes from the engine's slot table.
    static int cachedInternal[2] = {0, 0}, cachedMag = 0, cachedWrapS = 0, cachedWrapT = 0;
    int& internal = cachedInternal[bc1 ? 0 : 1];
    if (!internal) {
        g_glGetTexLevelParameteriv(kGlTexture2D, 0, kGlInternalFormat, &internal);
        g_glGetTexParameteriv(kGlTexture2D, kGlMagFilter, &cachedMag);
        g_glGetTexParameteriv(kGlTexture2D, kGlWrapS, &cachedWrapS);
        g_glGetTexParameteriv(kGlTexture2D, kGlWrapT, &cachedWrapT);
    }
    const bool ok = bc1 ? (internal == static_cast<int>(kGlDxt1Rgb) || internal == static_cast<int>(kGlDxt1Rgba))
                        : internal == static_cast<int>(kGlDxt5);
    if (!ok || static_cast<std::size_t>(size) < size0) {
        ++g_mipSkipped;  // the engine's CPU decompression (no S3TC) or a short body
        return r;
    }
    // Level 0 alone for now (complete: MAX_LEVEL 0), the chain attached later by PollMipJobs.
    const unsigned* slotName = SlotName(g_pendingSlot);
    if (!slotName || !*slotName) {
        ++g_mipSkipped;  // not a slot DrawGenTexture handed out (should not happen)
        return r;
    }
    const unsigned name = *slotName;
    auto job = std::make_unique<MipJob>();
    job->id = g_nextJob++;
    job->texture = name;
    job->w = w;
    job->h = h;
    job->internal = internal;
    job->fmt = fmt;
    job->levels = log2Scale + 1;
    job->trilinear = trilinear;
    job->queued = std::chrono::steady_clock::now();
    job->slot = g_pendingSlot;
    job->magFilter = cachedMag;
    job->wrapS = cachedWrapS;
    job->wrapT = cachedWrapT;
    // The engine's texture (bound: the engine just filled it) keeps level 0 only and is drawn meanwhile; the stamp
    // identifies it later.
    g_glTexParameterf(kGlTexture2D, kGlMinLod, StampOf(job->id));
    const bool stored = !fileLevels.empty();
    job->level0.assign(static_cast<const std::uint8_t*>(data), static_cast<const std::uint8_t*>(data) + size0);
    if (stored) {
        // Mip levels from the file: copied (the engine frees its buffer), nothing to build.
        int cw = w, ch = h;
        const auto* d = static_cast<const std::uint8_t*>(data);
        for (std::size_t i = 0; i < fileLevels.size(); ++i) {
            cw = std::max(1, cw / 2);
            ch = std::max(1, ch / 2);
            const std::size_t n = mips::LevelSize(fmt, cw, ch);
            job->out.emplace_back(d + fileLevels[i], d + fileLevels[i] + n);
            job->ow.push_back(cw);
            job->oh.push_back(ch);
        }
        ++g_mipFromFile;
        {
            std::lock_guard<std::mutex> lock(g_jobMutex);
            g_done.push_back(std::move(job));
        }
        g_doneCount.fetch_add(1, std::memory_order_release);
    } else {
        {
            std::lock_guard<std::mutex> lock(g_jobMutex);
            if (!g_workerStarted) {
                g_workerStarted = true;
                std::thread(Worker).detach();
            }
            g_todo.push_back(std::move(job));
        }
        g_jobCv.notify_one();
    }
    const double ms = MsSince(t0);
    NoteRenderTime(ms - g_lastEngineUploadMs, stored ? "stored mip copy" : "level-0 copy for the worker");
    static int logged = 0;
    if (++logged <= 4)
        Log("HD tiles: %dx%d page: %.1f ms on the render thread (engine level 0 %.1f ms, %s); the engine's PVRZ inflate "
            "before it took %.1f ms", w, h, ms, g_lastEngineUploadMs,
            stored ? "stored mip levels queued" : "copy for the mip worker", inflateMs);
    return r;
}

// The CResTileSet::SetTile calls of CInfTileSet::SetResID (area load): the engine gives every PVRZ page of a TIS
// the GL_NEAREST filter (its seam shader filters by hand). An HD page is marked for a mip chain with trilinear
// filtering (nearest-mip filtering when the player chose "Use Nearest Neighbour Scaling"), or gets plain GL_LINEAR
// when the mip hooks are not available. Written before the page's texture is created.
void HookSetTile(void* set, void* resTile, int index)
{
    g_setTile(set, resTile, index);
    if (!g_pvrFilterOffset)
        return;
    const int scale = SetScale(set);
    if (scale == 1)
        return;
    if (g_renderer && g_renderer() == kRendererD3D9)
        return;
    // Program 8 was built by DrawInit_GL before the switch was installed: rebuild it once with the HD path.
    if (!g_seamTried && g_createProgram && (g_shaderSource || g_shaderSourcePtr)) {
        g_seamTried = true;
        if (!g_seamHd)
            HookCreateProgram(kSeamProgram, "vpDraw", "fpSEAM");
    }
    const bool smooth = SmoothScaling();
    auto* pvr = Read<std::uint8_t*>(resTile, kResTilePvr);
    if (!pvr || Read<std::uint32_t>(pvr, g_pvrFilterOffset) != kGlNearest)
        return;
    std::uint32_t value;
    if (g_mips) {
        const std::uint32_t log2Scale = scale == 2 ? 1 : scale == 4 ? 2 : 3;
        value = kMarkTag | (smooth ? 1u << 8 : 0u) | log2Scale;
    } else if (smooth) {
        value = kGlLinear;
    } else {
        return;
    }
    std::memcpy(pvr + g_pvrFilterOffset, &value, 4);
    ++g_linearPages;
}

bool CallsTo(std::uintptr_t site, std::uintptr_t target)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    return code[0] == 0xE8 && site + 5 + rel == target;
}

std::vector<std::uint32_t> ConstList(const char* prefix)
{
    std::vector<std::uint32_t> out;
    for (int i = 0; i < 16; ++i) {
        std::uint64_t v = 0;
        if (!engineTypes.Const(std::string(prefix) + std::to_string(i), v))
            break;
        out.push_back(static_cast<std::uint32_t>(v));
    }
    return out;
}

bool Available()
{
    return engineTypes.Symbol(kRenderTexture) && engineTypes.Symbol(kDrawTexCoord) &&
           engineTypes.Symbol(kDrawColorTone) && !engineTypes.CallSitesOf(kRenderTexture).empty() &&
           !ConstList("IEX.hdTiles.texCoord.").empty() && !ConstList("IEX.hdTiles.tone.").empty();
}

// All sites or none: half of the texture coordinates scaled would draw garbage.
bool Install(std::string& why, std::uintptr_t, std::uintptr_t)
{
    if (!Available()) {
        why = "sites not in this build's engine description";
        return false;
    }
    const std::uintptr_t base = EngineImageBase();
    const std::uintptr_t render = base + engineTypes.Symbol(kRenderTexture);
    const std::uintptr_t texCoord = base + engineTypes.Symbol(kDrawTexCoord);
    const std::uintptr_t tone = base + engineTypes.Symbol(kDrawColorTone);
    struct Site {
        std::uint32_t rva;
        std::uintptr_t target;
        const void* replacement;
    };
    std::vector<Site> sites;
    for (std::uint32_t s : engineTypes.CallSitesOf(kRenderTexture))
        sites.push_back({s, render, reinterpret_cast<const void*>(&HookRenderTexture)});
    const std::vector<std::uint32_t> tc = ConstList("IEX.hdTiles.texCoord.");
    if (tc.size() != 6) {
        why = "expected 6 DrawTexCoord calls in CVidTile::RenderTexture";
        return false;
    }
    for (std::uint32_t s : tc)
        sites.push_back({s, texCoord, reinterpret_cast<const void*>(&HookTexCoord)});
    for (std::uint32_t s : ConstList("IEX.hdTiles.tone."))
        sites.push_back({s, tone, reinterpret_cast<const void*>(&HookTone)});
    // Optional: linear filtering of HD pages (needs the CResPVR filter offset of this build).
    std::uint64_t filterOff = 0;
    const std::uint32_t setTileRva = engineTypes.Symbol(kSetTile);
    const std::uint32_t chitinRva = engineTypes.Symbol(kChitin);
    const bool linear = engineTypes.Const("IEX.hdTiles.pvrFilter", filterOff) && setTileRva && chitinRva &&
                        !engineTypes.CallSitesOf(kSetTile).empty();
    if (linear)
        for (std::uint32_t s : engineTypes.CallSitesOf(kSetTile))
            sites.push_back({s, base + setTileRva, reinterpret_cast<const void*>(&HookSetTile)});
    // Optional: mipmaps of HD pages (DrawGenTexture / DrawCompressedTexImage2D calls of CResPVR + GL entry points).
    const std::uint32_t genRva = engineTypes.Symbol(kGenTexture), texRva = engineTypes.Symbol(kTexImage);
    const std::vector<std::uint32_t> genSites = ConstList("IEX.hdTiles.genTexture.");
    const std::vector<std::uint32_t> texSites = ConstList("IEX.hdTiles.texImage.");
    // (GL entry points are resolved at the first upload: the switch may be installed before DrawInit_GL.)
    const bool mipHooks = linear && genRva && texRva && !genSites.empty() && genSites.size() == texSites.size();
    if (mipHooks) {
        for (std::uint32_t s : genSites)
            sites.push_back({s, base + genRva, reinterpret_cast<const void*>(&HookGenTexture)});
        for (std::uint32_t s : texSites)
            sites.push_back({s, base + texRva, reinterpret_cast<const void*>(&HookTexImage)});
    } else {
        Log("HD tiles: no mipmaps for HD pages (sites missing in this build's engine description)");
    }
    // Optional: HD-aware seam program (program 8 call site of DrawInit_GL + the engine's glShaderSource).
    std::uint64_t seamSite = 0, ssPtr = 0, ssPlt = 0;
    const std::uint32_t cpRva = engineTypes.Symbol(kCreateProgram);
    engineTypes.Const("IEX.hdTiles.seamProgramSite", seamSite);
    const std::vector<std::uint32_t> ssSites = ConstList("IEX.hdTiles.shaderSource.");
    const bool winPtr = engineTypes.Const("IEX.hdTiles.glShaderSourcePtr", ssPtr);
    const bool linPlt = engineTypes.Const("IEX.hdTiles.glShaderSourcePlt", ssPlt) && ssSites.size() == 2;
    bool seam = cpRva && seamSite && (winPtr || linPlt);
    if (seam) {
        sites.push_back({static_cast<std::uint32_t>(seamSite), base + cpRva,
                         reinterpret_cast<const void*>(&HookCreateProgram)});
        if (linPlt)
            for (std::uint32_t s : ssSites)
                sites.push_back({s, base + ssPlt, reinterpret_cast<const void*>(&WrapShaderSource)});
    }
    for (const Site& s : sites) {
        if (!CallsTo(base + s.rva, s.target)) {
            why = "call site already patched or other build";
            Log("HD tiles: %s (0x%x)", why.c_str(), s.rva);
            return false;
        }
    }
    g_render = reinterpret_cast<RenderFn>(render);
    g_texCoord = reinterpret_cast<TexCoordFn>(texCoord);
    g_tone = reinterpret_cast<ToneFn>(tone);
    if (const std::uint32_t r = engineTypes.Symbol(kDrawGetRenderer))
        g_renderer = reinterpret_cast<RendererFn>(base + r);
    if (mipHooks) {
        std::uint64_t slots = 0;
        if (engineTypes.Const("IEX.hdTiles.texSlots", slots))
            g_texSlots = base + slots;
        g_genTexture = reinterpret_cast<GenTextureFn>(base + genRva);
        g_texImage = reinterpret_cast<TexImageFn>(base + texRva);
        g_mips = true;
    }
    if (seam) {
        g_createProgram = reinterpret_cast<CreateProgramFn>(base + cpRva);
        if (winPtr) {
            g_shaderSourcePtr = base + ssPtr;  // read when program 8 is built (DrawInit_GL fills it)
        } else {
            g_shaderSource = reinterpret_cast<ShaderSourceFn>(base + ssPlt);
        }
    }
    if (linear) {
        g_setTile = reinterpret_cast<SetTileFn>(base + setTileRva);
        g_chitinPtr = base + chitinRva;
        g_pvrFilterOffset = static_cast<std::uint32_t>(filterOff);
    }
    int n = 0;
    for (const Site& s : sites) {
        if (!HookCallSite(base + s.rva, s.target, s.replacement)) {
            why = "code write failed";
            Log("HD tiles: %s at 0x%x (%d sites already redirected)", why.c_str(), s.rva, n);
            return false;
        }
        ++n;
    }
    hp::SetSites(hp::kHdTiles, n);
    Log("HD tiles: %d call sites redirected (TIS tile size 128/256/512 = 2x/4x/8x PVRZ pages; 64 = engine as is; "
        "HD pages: %s; seam program: %s)", n,
        g_mips ? "mipmapped, trilinear (nearest-mip with nearest neighbour scaling)"
               : linear ? "linear-filtered unless nearest neighbour scaling" : "engine filter",
        seam ? "HD-aware" : "engine (HD tiles use fpDraw)");
    return true;
}

// IEX_HdTiles_Stats() -> HD tile draws, other tile draws (since start), tile sets seen, HD page filter writes,
// HD pages mipmapped, mip levels uploaded, HD seam program active, HD pages left without mips, worker build ms,
// render-thread attach ms, chains attached, chains dropped (texture gone / reused), pages with stored mips,
// longest render-thread time for one HD page (ms)
int LuaStats(lua_State* L)
{
    lua.pushinteger(L, static_cast<lua_Integer>(g_hdDraws));
    lua.pushinteger(L, static_cast<lua_Integer>(g_plainDraws));
    lua.pushinteger(L, static_cast<lua_Integer>(g_seenSets.size()));
    lua.pushinteger(L, static_cast<lua_Integer>(g_linearPages));
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipPages));
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipLevels));
    lua.pushboolean(L, g_seamHd ? 1 : 0);
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipSkipped));
    lua.pushnumber(L, g_mipBuildMs);
    lua.pushnumber(L, g_mipUploadMs);
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipAttached));
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipDropped));
    lua.pushinteger(L, static_cast<lua_Integer>(g_mipFromFile));
    lua.pushnumber(L, g_renderMaxMs);
    return 14;
}

} // namespace

void InstallHdTileHooks()
{
    hp::SetInstaller(hp::kHdTiles, &Install, &Available);
}

void OpenLuaHdTiles(lua_State* L)
{
    lua.pushcclosure(L, LuaStats, 0);
    lua.setglobal(L, "IEX_HdTiles_Stats");
}

} // namespace iex
