import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('android_pages', Path(__file__).resolve().parents[1] / 'check_android_pages.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def elf(alignment, file_offset=0, address=0):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<QQ', data, 72, file_offset, address)
    struct.pack_into('<Q', data, 112, alignment)
    return data


class AlignmentTests(unittest.TestCase):
    def test_accepts_16_and_64_kb(self):
        for alignment in [16384, 65536]:
            bits, segments = module.elf_loads(elf(alignment))
            self.assertEqual(bits, 64)
            self.assertTrue(segments[0]['aligned_16kb'])

    def test_rejects_4kb_or_incongruent_load(self):
        for data in [elf(4096), elf(16384, file_offset=4096)]:
            self.assertFalse(module.elf_loads(data)[1][0]['aligned_16kb'])

    def test_rejects_truncated_input(self):
        with self.assertRaises(ValueError):
            module.elf_loads(elf(16384)[:80])


if __name__ == '__main__':
    unittest.main()
