"""Writes IEX_API.txt: every EEex_ name IEX defines (lua/*.lua and C++ registrations), one per line, sorted, LF.

Shipped as IEX/IEX_API.txt: install-time checks that look for an EEex function in EEex's own Lua files
(`FILE_CONTAINS_EVALUATED ~EEex_scripts/EEex_Resource.lua~ ~^function[ %TAB%]+EEex_Resource_Load2DA~`) are
rewritten by patch_mod.py (rule 7) to also accept `FILE_CONTAINS_EVALUATED (~IEX/IEX_API.txt~ ~^EEex_Resource_Load2DA$~)`.
Usage: python -I tools/compat/api_list.py <out file>
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from scan_mods import iex_defined  # noqa: E402


def main():
    out = pathlib.Path(sys.argv[1])
    names = sorted(n for n in iex_defined() if n.startswith('EEex_'))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(names) + '\n', encoding='ascii', newline='\n')
    print('%d EEex names -> %s' % (len(names), out))


if __name__ == '__main__':
    main()
