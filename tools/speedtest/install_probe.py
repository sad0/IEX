"""Installs the speed test probe in a test copy's override: python -I install_probe.py <override dir>.

M_IEXSPD.lua = probe/spd_body.lua wrapped in load() + pcall (under EEex a Lua error in an M_ file opens a modal
popup); SPD.menu = the per-frame tick menu.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'difftest'))
from gen_cases import wrap  # noqa: E402


def main():
    dst = sys.argv[1]
    with open(os.path.join(HERE, 'probe', 'spd_body.lua'), encoding='utf-8') as f:
        src = f.read()
    text = wrap(src, 'M_IEXSPD.lua').replace('difftest_status.txt', 'speedtest_status.txt').replace('DIFFT|', 'SPD|')
    with open(os.path.join(dst, 'M_IEXSPD.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    shutil.copy(os.path.join(HERE, 'probe', 'SPD.menu'), os.path.join(dst, 'SPD.menu'))


if __name__ == '__main__':
    main()
