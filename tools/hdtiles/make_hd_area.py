"""Make HD test tiles for one area of a private test copy: its PVRZ-based TIS rewritten with tile size 64*N and its
PVRZ pages upscaled N times (Pillow Lanczos filter, alpha-weighted; 1-bit alpha kept; BC1 = DXT1 like the vanilla pages), written to <game>/override.
The InfinityEngine-Enhancer convention: TIS header +0x14 = 128/256/512 for 2x/4x/8x, tile entries = page + texel
x / y in the HD page. ARE / WED are not touched.

  python -I make_hd_area.py <game dir> <TIS resref> <scale 1|2|4|8> [--mark]
      scale 1 removes the area's files from override again (vanilla).
      --mips  stores levels 0..log2(scale)+1 in each PVRZ (PVR3 mip count), as a creator tool could
      --mark  draws a 1-texel white / black frame on every tile edge and the scale ("2x") in each tile, so the
              screenshots show that every HD texel lands in its own world tile (UV origin, span, no atlas bleed).

Test data only: run it on private copies under E:/Dev/IEX-data/testgame, never on a player's game.
"""
import os
import struct
import sys
import zlib

import etcpak
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ie_res  # noqa: E402

PVR3 = 0x03525650
FMT_DXT1 = 7


def read_pvrz(data):
    raw = zlib.decompress(data[4:])
    version, flags, fmt, cs, ct, h, w, depth, surf, faces, mips, meta = struct.unpack_from('<IIQIIIIIIIII', raw, 0)
    assert version == PVR3, 'not a PVR3 texture'
    assert fmt == FMT_DXT1, 'test pages must be DXT1 (format %d)' % fmt
    body = raw[52 + meta:52 + meta + w * h // 2]
    return Image.fromarray(decode_bc1(body, w, h), 'RGBA')


def decode_bc1(body, w, h):
    """BC1 / DXT1 blocks (public S3TC format) -> RGBA array h x w x 4."""
    b = np.frombuffer(body, dtype=np.uint8).reshape(h // 4, w // 4, 8)
    c0 = b[..., 0].astype(np.uint32) | (b[..., 1].astype(np.uint32) << 8)
    c1 = b[..., 2].astype(np.uint32) | (b[..., 3].astype(np.uint32) << 8)
    bits = (b[..., 4].astype(np.uint32) | (b[..., 5].astype(np.uint32) << 8) | (b[..., 6].astype(np.uint32) << 16)
            | (b[..., 7].astype(np.uint32) << 24))

    def rgb(c):
        r, g, bl = (c >> 11) & 31, (c >> 5) & 63, c & 31
        return np.stack([(r * 255 + 15) // 31, (g * 255 + 31) // 63, (bl * 255 + 15) // 31], -1).astype(np.int32)

    p0, p1 = rgb(c0), rgb(c1)
    four = (c0 > c1)[..., None]
    p2 = np.where(four, (2 * p0 + p1) // 3, (p0 + p1) // 2)
    p3 = np.where(four, (p0 + 2 * p1) // 3, 0)
    pal = np.stack([p0, p1, p2, p3], 2)  # by, bx, 4, 3
    alpha = np.stack([np.full(c0.shape, 255)] * 3 + [np.where(c0 > c1, 255, 0)], 2)  # index 3 transparent if 3-colour
    idx = np.stack([(bits >> (2 * i)) & 3 for i in range(16)], -1)  # by, bx, 16
    by, bx = np.indices(c0.shape)
    col = pal[by[..., None], bx[..., None], idx]  # by, bx, 16, 3
    a = alpha[by[..., None], bx[..., None], idx]
    out = np.concatenate([col, a[..., None]], -1).astype(np.uint8).reshape(h // 4, w // 4, 4, 4, 4)
    return out.transpose(0, 2, 1, 3, 4).reshape(h, w, 4)


def bc1(level):
    """BC1 blocks of one RGBA level. Texels with alpha 0 (the vanilla 1-bit "punch-through" alpha that water / overlay
    base tiles use) stay transparent: etcpak writes opaque blocks only, so the blocks with such texels are re-encoded
    in BC1 3-colour mode (c0 <= c1, index 3 = transparent)."""
    w, h = level.size
    rgba = np.asarray(level.convert('RGBA'))
    body = etcpak.compress_bc1(rgba.tobytes(), w, h)
    tr = rgba[..., 3] < 128
    if not tr.any():
        return body
    bt = tr.reshape(h // 4, 4, w // 4, 4).transpose(0, 2, 1, 3).reshape(h // 4, w // 4, 16)
    px = rgba[..., :3].astype(np.int32).reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(h // 4, w // 4, 16, 3)
    b = np.frombuffer(bytes(body), dtype=np.uint8).reshape(h // 4, w // 4, 8).copy()
    by, bx = np.nonzero(bt.any(-1))
    c0 = b[by, bx, 0].astype(np.uint32) | (b[by, bx, 1].astype(np.uint32) << 8)
    c1 = b[by, bx, 2].astype(np.uint32) | (b[by, bx, 3].astype(np.uint32) << 8)
    lo, hi = np.minimum(c0, c1), np.maximum(c0, c1)

    def rgb(c):
        r, g, bl = (c >> 11) & 31, (c >> 5) & 63, c & 31
        return np.stack([(r * 255 + 15) // 31, (g * 255 + 31) // 63, (bl * 255 + 15) // 31], -1).astype(np.int32)

    p0, p1 = rgb(lo), rgb(hi)
    pal = np.stack([p0, p1, (p0 + p1) // 2], 1)  # n, 3, 3
    src = px[by, bx]  # n, 16, 3
    idx = ((src[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1).argmin(-1).astype(np.uint32)
    idx[bt[by, bx]] = 3
    bits = np.zeros(len(by), np.uint32)
    for i in range(16):
        bits |= idx[:, i] << (2 * i)
    b[by, bx, 0], b[by, bx, 1] = lo & 255, lo >> 8
    b[by, bx, 2], b[by, bx, 3] = hi & 255, hi >> 8
    for k in range(4):
        b[by, bx, 4 + k] = (bits >> (8 * k)) & 255
    return b.tobytes()


def write_pvrz(img, mips=1):
    w, h = img.size
    body = b''
    level = img.convert('RGBA')
    for i in range(mips):
        body += bc1(level)
        level = level.resize((max(4, level.width // 2), max(4, level.height // 2)), Image.BOX)
    raw = struct.pack('<IIQIIIIIIIII', PVR3, 0, FMT_DXT1, 0, 0, h, w, 1, 1, 1, mips, 0) + body
    return struct.pack('<I', len(raw)) + zlib.compress(raw, 6)


def upscale(img, scale):
    """Lanczos for colour, weighted by alpha so transparent (black) texels do not bleed; nearest for the 1-bit
    alpha, so the transparent footprint is exactly the vanilla one scaled."""
    a = np.asarray(img.convert('RGBA'))
    W, H = img.width * scale, img.height * scale
    alpha = (a[..., 3] >= 128).astype(np.float32)
    up = lambda ch: np.asarray(Image.fromarray(ch.astype(np.float32), 'F').resize((W, H), Image.LANCZOS))
    wsum = up(alpha)
    rgb = np.stack([up(a[..., c] * alpha) for c in range(3)], -1) / np.maximum(wsum, 1e-3)[..., None]
    am = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8), 'L').resize((W, H), Image.NEAREST))
    out = np.concatenate([np.clip(rgb, 0, 255), am[..., None]], -1).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def page_name(tis, page):
    return '%s%s%02d' % (tis[0], tis[2:8], page)  # CResTileSet::SetTile: "%c%.6s%02d", name[0], name + 2


def main():
    a = sys.argv[1:]
    if len(a) < 3:
        sys.exit(__doc__)
    game, tis, scale = a[0], a[1].upper(), int(a[2])
    mark = '--mark' in a
    stored = '--mips' in a
    root = os.path.abspath(game).lower()
    if not root.startswith(os.path.abspath('E:/Dev/IEX-data/testgame').lower() + os.sep) or 'eet-2.7.3' in root:
        sys.exit('refused: private test copies under E:/Dev/IEX-data/testgame only')
    g = ie_res.Game(game)
    src = g.read(tis, 'TIS', override=False)
    count, length, hsize, tsize = struct.unpack_from('<IIII', src, 8)
    assert length == 12, 'not a PVRZ-based TIS'
    assert tsize == 64, 'source TIS is not 1x'
    entries = [struct.unpack_from('<iii', src, hsize + i * 12) for i in range(count)]
    pages = sorted({p for p, _, _ in entries if p >= 0})
    ovr = os.path.join(game, 'override')
    out = [os.path.join(ovr, tis + '.TIS')] + [os.path.join(ovr, page_name(tis, p) + '.PVRZ') for p in pages]
    for f in out:
        if os.path.exists(f):
            os.remove(f)
    if scale == 1:
        print('removed', len(out), 'files: vanilla', tis)
        return
    assert scale in (2, 4, 8)
    t = 64 * scale
    hd = bytearray(struct.pack('<4s4sIIII', b'TIS ', b'V1  ', count, 12, 0x18, t))
    for p, x, y in entries:
        hd += struct.pack('<iii', p, x * scale if p >= 0 else x, y * scale if p >= 0 else y)
    open(out[0], 'wb').write(hd)
    for p in pages:
        img = read_pvrz(g.read(page_name(tis, p), 'PVRZ', override=False))
        big = upscale(img, scale)
        if mark:
            d = ImageDraw.Draw(big)
            for q, x, y in entries:
                if q != p:
                    continue
                X, Y = x * scale, y * scale
                d.rectangle([X, Y, X + t - 1, Y + t - 1], outline=(255, 255, 255, 255))
                d.rectangle([X + 1, Y + 1, X + t - 2, Y + t - 2], outline=(0, 0, 0, 255))
                d.line([X + 2, Y + 2, X + t - 3, Y + t - 3], fill=(255, 255, 255, 255))
                d.text((X + t // 2 - 6, Y + t // 2 - 5), '%dx' % scale, fill=(255, 255, 255, 255))
        open(os.path.join(ovr, page_name(tis, p) + '.PVRZ'), 'wb').write(write_pvrz(big, scale.bit_length() + 1 if stored else 1))
    print('%s: %d tiles, tile size %d, %d page(s) of %dx%d%s -> %s' % (
        tis, count, t, len(pages), img.width * scale, img.height * scale, (', marked' if mark else '') + (', stored mips' if stored else ''), ovr))


if __name__ == '__main__':
    main()
