#pragma once

// Mip chains for block-compressed textures (BC1 = DXT1, BC3 = DXT5; public S3TC formats), built on the CPU: the
// level is decoded, box-filtered 2x2 and encoded again. Used for HD area tile pages (hd_tiles.cpp), whose PVRZ
// files carry one level only. Portable, no GL.
#include <cstdint>
#include <vector>

namespace iex::mips {

enum class Format { BC1, BC3 };

// Levels 1..levels of a w x h texture whose level 0 is `level0` (whole blocks, row-major). Stops early when a
// level would be smaller than one block in either direction. out[i] = level i + 1, sizes in outW / outH.
void Build(Format f, int w, int h, const std::uint8_t* level0, int levels, std::vector<std::vector<std::uint8_t>>& out,
           std::vector<int>& outW, std::vector<int>& outH);

// Bytes of one level (whole 4x4 blocks).
std::size_t LevelSize(Format f, int w, int h);

} // namespace iex::mips
