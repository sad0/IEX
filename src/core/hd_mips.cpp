#include "hd_mips.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>

namespace iex::mips {

namespace {

struct Rgba {
    std::uint8_t r, g, b, a;
};

int BlockBytes(Format f)
{
    return f == Format::BC1 ? 8 : 16;
}

void Unpack565(std::uint16_t c, int& r, int& g, int& b)
{
    r = ((c >> 11) & 31) * 255 / 31;
    g = ((c >> 5) & 63) * 255 / 63;
    b = (c & 31) * 255 / 31;
}

std::uint16_t Pack565(int r, int g, int b)
{
    return static_cast<std::uint16_t>(((r * 31 + 127) / 255) << 11 | ((g * 63 + 127) / 255) << 5 |
                                      ((b * 31 + 127) / 255));
}

// Colour part of a BC1 / BC3 block -> 16 texels. `bc1` allows the 3-colour + transparent mode.
void DecodeColor(const std::uint8_t* b, Rgba* px, bool bc1)
{
    const std::uint16_t c0 = static_cast<std::uint16_t>(b[0] | b[1] << 8);
    const std::uint16_t c1 = static_cast<std::uint16_t>(b[2] | b[3] << 8);
    int p[4][4];
    Unpack565(c0, p[0][0], p[0][1], p[0][2]);
    Unpack565(c1, p[1][0], p[1][1], p[1][2]);
    p[0][3] = p[1][3] = 255;
    const bool four = !bc1 || c0 > c1;
    for (int k = 0; k < 3; ++k) {
        p[2][k] = four ? (2 * p[0][k] + p[1][k]) / 3 : (p[0][k] + p[1][k]) / 2;
        p[3][k] = four ? (p[0][k] + 2 * p[1][k]) / 3 : 0;
    }
    p[2][3] = 255;
    p[3][3] = four ? 255 : 0;
    const std::uint32_t bits = b[4] | b[5] << 8 | b[6] << 16 | static_cast<std::uint32_t>(b[7]) << 24;
    for (int i = 0; i < 16; ++i) {
        const int* q = p[(bits >> (2 * i)) & 3];
        px[i] = {static_cast<std::uint8_t>(q[0]), static_cast<std::uint8_t>(q[1]), static_cast<std::uint8_t>(q[2]),
                 static_cast<std::uint8_t>(q[3])};
    }
}

void DecodeAlpha(const std::uint8_t* b, Rgba* px)
{
    int a[8];
    a[0] = b[0];
    a[1] = b[1];
    if (a[0] > a[1])
        for (int i = 1; i < 7; ++i)
            a[i + 1] = ((7 - i) * a[0] + i * a[1]) / 7;
    else {
        for (int i = 1; i < 5; ++i)
            a[i + 1] = ((5 - i) * a[0] + i * a[1]) / 5;
        a[6] = 0;
        a[7] = 255;
    }
    std::uint64_t bits = 0;
    for (int i = 0; i < 6; ++i)
        bits |= static_cast<std::uint64_t>(b[2 + i]) << (8 * i);
    for (int i = 0; i < 16; ++i)
        px[i].a = static_cast<std::uint8_t>(a[(bits >> (3 * i)) & 7]);
}

// Bounding-box encoder (inset endpoints), good enough for mip levels.
void EncodeColor(const Rgba* px, std::uint8_t* out, bool bc1)
{
    int lo[3] = {255, 255, 255}, hi[3] = {0, 0, 0};
    bool transparent = false;
    for (int i = 0; i < 16; ++i) {
        if (bc1 && px[i].a < 128) {
            transparent = true;
            continue;
        }
        const int c[3] = {px[i].r, px[i].g, px[i].b};
        for (int k = 0; k < 3; ++k) {
            lo[k] = std::min(lo[k], c[k]);
            hi[k] = std::max(hi[k], c[k]);
        }
    }
    if (lo[0] > hi[0])  // all transparent
        for (int k = 0; k < 3; ++k)
            lo[k] = hi[k] = 0;
    for (int k = 0; k < 3; ++k) {
        const int inset = (hi[k] - lo[k]) / 16;
        lo[k] += inset;
        hi[k] -= inset;
    }
    std::uint16_t c0 = Pack565(hi[0], hi[1], hi[2]);
    std::uint16_t c1 = Pack565(lo[0], lo[1], lo[2]);
    if (transparent) {
        if (c0 > c1)
            std::swap(c0, c1);  // 3-colour mode: c0 <= c1, index 3 = transparent
    } else if (c0 < c1) {
        std::swap(c0, c1);
    }
    int p[4][3];
    Unpack565(c0, p[0][0], p[0][1], p[0][2]);
    Unpack565(c1, p[1][0], p[1][1], p[1][2]);
    const bool four = c0 > c1;
    for (int k = 0; k < 3; ++k) {
        p[2][k] = four ? (2 * p[0][k] + p[1][k]) / 3 : (p[0][k] + p[1][k]) / 2;
        p[3][k] = four ? (p[0][k] + 2 * p[1][k]) / 3 : 0;
    }
    const int candidates = four ? 4 : 3;
    std::uint32_t bits = 0;
    for (int i = 0; i < 16; ++i) {
        int best = 0;
        if (transparent && px[i].a < 128) {
            best = 3;
        } else {
            int bestD = 1 << 30;
            for (int j = 0; j < candidates; ++j) {
                const int dr = px[i].r - p[j][0], dg = px[i].g - p[j][1], db = px[i].b - p[j][2];
                const int d = dr * dr + dg * dg + db * db;
                if (d < bestD) {
                    bestD = d;
                    best = j;
                }
            }
        }
        bits |= static_cast<std::uint32_t>(best) << (2 * i);
    }
    out[0] = static_cast<std::uint8_t>(c0);
    out[1] = static_cast<std::uint8_t>(c0 >> 8);
    out[2] = static_cast<std::uint8_t>(c1);
    out[3] = static_cast<std::uint8_t>(c1 >> 8);
    std::memcpy(out + 4, &bits, 4);
}

void EncodeAlpha(const Rgba* px, std::uint8_t* out)
{
    int lo = 255, hi = 0;
    for (int i = 0; i < 16; ++i) {
        lo = std::min<int>(lo, px[i].a);
        hi = std::max<int>(hi, px[i].a);
    }
    out[0] = static_cast<std::uint8_t>(hi);
    out[1] = static_cast<std::uint8_t>(lo);
    int a[8];
    a[0] = hi;
    a[1] = lo;
    for (int i = 1; i < 7; ++i)
        a[i + 1] = ((7 - i) * hi + i * lo) / 7;
    std::uint64_t bits = 0;
    for (int i = 0; i < 16; ++i) {
        int best = 0, bestD = 1 << 30;
        for (int j = 0; j < (hi > lo ? 8 : 1); ++j) {
            const int d = std::abs(px[i].a - a[j]);
            if (d < bestD) {
                bestD = d;
                best = j;
            }
        }
        bits |= static_cast<std::uint64_t>(best) << (3 * i);
    }
    for (int i = 0; i < 6; ++i)
        out[2 + i] = static_cast<std::uint8_t>(bits >> (8 * i));
}

void Decode(Format f, int w, int h, const std::uint8_t* data, std::vector<Rgba>& img)
{
    img.assign(static_cast<std::size_t>(w) * h, Rgba{0, 0, 0, 0});
    const int bw = (w + 3) / 4, bh = (h + 3) / 4, bb = BlockBytes(f);
    Rgba px[16];
    for (int by = 0; by < bh; ++by)
        for (int bx = 0; bx < bw; ++bx) {
            const std::uint8_t* b = data + (static_cast<std::size_t>(by) * bw + bx) * bb;
            if (f == Format::BC1) {
                DecodeColor(b, px, true);
            } else {
                DecodeColor(b + 8, px, false);
                DecodeAlpha(b, px);
            }
            for (int y = 0; y < 4; ++y)
                for (int x = 0; x < 4; ++x) {
                    const int X = bx * 4 + x, Y = by * 4 + y;
                    if (X < w && Y < h)
                        img[static_cast<std::size_t>(Y) * w + X] = px[y * 4 + x];
                }
        }
}

void Encode(Format f, int w, int h, const std::vector<Rgba>& img, std::vector<std::uint8_t>& out)
{
    const int bw = (w + 3) / 4, bh = (h + 3) / 4, bb = BlockBytes(f);
    out.assign(static_cast<std::size_t>(bw) * bh * bb, 0);
    Rgba px[16];
    for (int by = 0; by < bh; ++by)
        for (int bx = 0; bx < bw; ++bx) {
            for (int y = 0; y < 4; ++y)
                for (int x = 0; x < 4; ++x) {
                    const int X = std::min(bx * 4 + x, w - 1), Y = std::min(by * 4 + y, h - 1);
                    px[y * 4 + x] = img[static_cast<std::size_t>(Y) * w + X];
                }
            std::uint8_t* b = out.data() + (static_cast<std::size_t>(by) * bw + bx) * bb;
            if (f == Format::BC1) {
                EncodeColor(px, b, true);
            } else {
                EncodeAlpha(px, b);
                EncodeColor(px, b + 8, false);
            }
        }
}

// 2x2 box filter (colour weighted by alpha so transparent texels do not darken edges).
void Half(const std::vector<Rgba>& src, int w, int h, std::vector<Rgba>& dst, int& dw, int& dh)
{
    dw = std::max(1, w / 2);
    dh = std::max(1, h / 2);
    dst.resize(static_cast<std::size_t>(dw) * dh);
    for (int y = 0; y < dh; ++y)
        for (int x = 0; x < dw; ++x) {
            int r = 0, g = 0, b = 0, a = 0, n = 0;
            for (int k = 0; k < 4; ++k) {
                const int X = std::min(2 * x + (k & 1), w - 1), Y = std::min(2 * y + (k >> 1), h - 1);
                const Rgba& p = src[static_cast<std::size_t>(Y) * w + X];
                r += p.r * p.a;
                g += p.g * p.a;
                b += p.b * p.a;
                a += p.a;
                ++n;
            }
            Rgba& o = dst[static_cast<std::size_t>(y) * dw + x];
            o.a = static_cast<std::uint8_t>(a / n);
            o.r = static_cast<std::uint8_t>(a ? r / a : 0);
            o.g = static_cast<std::uint8_t>(a ? g / a : 0);
            o.b = static_cast<std::uint8_t>(a ? b / a : 0);
        }
}

} // namespace

std::size_t LevelSize(Format f, int w, int h)
{
    return static_cast<std::size_t>((w + 3) / 4) * ((h + 3) / 4) * BlockBytes(f);
}

void Build(Format f, int w, int h, const std::uint8_t* level0, int levels, std::vector<std::vector<std::uint8_t>>& out,
           std::vector<int>& outW, std::vector<int>& outH)
{
    out.clear();
    outW.clear();
    outH.clear();
    std::vector<Rgba> cur, next;
    Decode(f, w, h, level0, cur);
    int cw = w, ch = h;
    for (int i = 0; i < levels && cw >= 8 && ch >= 8; ++i) {
        int nw, nh;
        Half(cur, cw, ch, next, nw, nh);
        out.emplace_back();
        Encode(f, nw, nh, next, out.back());
        outW.push_back(nw);
        outH.push_back(nh);
        cur.swap(next);
        cw = nw;
        ch = nh;
    }
}

} // namespace iex::mips
