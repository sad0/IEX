"""Minimal Infinity Engine resource reader (public KEY V1 / BIFF V1 formats, IESDP): read a resource of a game
folder from override/ first, then from the BIFFs listed in chitin.key. No game data is stored by this module."""
import os
import struct

TYPES = {'WED': 0x3e9, 'TIS': 0x3eb, 'MOS': 0x3ec, 'ARE': 0x3f2, 'PVRZ': 0x404, '2DA': 0x3f4, 'BAM': 0x3e8}


class Game:
    def __init__(self, root):
        self.root = root
        d = open(os.path.join(root, 'chitin.key'), 'rb').read()
        assert d[:8] == b'KEY V1  ', 'not a KEY V1 file'
        nbif, nres, obif, ores = struct.unpack_from('<IIII', d, 8)
        self.bifs = []
        for i in range(nbif):
            _, noff, nlen = struct.unpack_from('<IIH', d, obif + i * 12)
            self.bifs.append(d[noff:noff + nlen].rstrip(b'\0').decode('latin-1').replace(chr(92), '/'))
        self.res = {}
        for i in range(nres):
            o = ores + i * 14
            name = d[o:o + 8].rstrip(b'\0').decode('latin-1').upper()
            typ, loc = struct.unpack_from('<HI', d, o + 8)
            self.res[(name, typ)] = loc
        self._bif = {}

    def names(self, typ):
        t = TYPES[typ]
        return sorted(n for n, k in self.res if k == t)

    def _open_bif(self, idx):
        if idx not in self._bif:
            path = os.path.join(self.root, self.bifs[idx])
            if not os.path.exists(path):  # case-insensitive file systems only, as the engine
                path = os.path.join(self.root, 'data', os.path.basename(self.bifs[idx]))
            self._bif[idx] = open(path, 'rb').read()
        return self._bif[idx]

    def read(self, name, typ, override=True):
        """Resource bytes. A TIS from a BIFF gets the TIS V1 header the engine adds (24 bytes)."""
        name, t = name.upper(), TYPES[typ]
        if override:
            p = os.path.join(self.root, 'override', '%s.%s' % (name, typ))
            for cand in (p, p.lower(), os.path.join(self.root, 'override', '%s.%s' % (name.lower(), typ.lower()))):
                if os.path.exists(cand):
                    return open(cand, 'rb').read()
        loc = self.res[(name, t)]
        b = self._open_bif(loc >> 20)
        assert b[:8] == b'BIFFV1  ', 'not a BIFF V1 file (compressed BIFs are not supported)'
        nfile, ntis, oentries = struct.unpack_from('<III', b, 8)
        if t == TYPES['TIS']:
            want = (loc >> 14) & 0x3f
            o = oentries + nfile * 16
            for i in range(ntis):
                l, off, cnt, size, _ = struct.unpack_from('<IIIIH', b, o + i * 20)
                if (l >> 14) & 0x3f == want:
                    return struct.pack('<4s4sIIII', b'TIS ', b'V1  ', cnt, size, 0x18, 0x40) + b[off:off + cnt * size]
            raise KeyError(name)
        want = loc & 0x3fff
        for i in range(nfile):
            l, off, size, _ = struct.unpack_from('<IIIH', b, oentries + i * 16)
            if l & 0x3fff == want:
                return b[off:off + size]
        raise KeyError(name)
