"""Regression checks for the isolated Dead City fence replacement."""
import hashlib
from pathlib import Path
import struct
import sys
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from stage_dead_city_assets import chunks, strings, TEXTURE_OVERRIDES


class FenceTests(unittest.TestCase):
    def test_only_shader_texture_table_changes(self):
        original = list(chunks(Path('C:/unpackedtt2/levels/dead_city/level').read_bytes()))
        staged = list(chunks(Path('build-deadcity/assets/gamedata/levels/dead_city/level').read_bytes()))
        self.assertEqual([tag for tag, _ in original], [tag for tag, _ in staged])
        for (tag, before), (_, after) in zip(original, staged):
            if tag != 2:
                self.assertEqual(before, after, f'Unexpected change in level chunk {tag}')
                continue
            count, = struct.unpack_from('<I', before)
            self.assertEqual(count, struct.unpack_from('<I', after)[0])
            for old, new in zip(strings(before[4:], count), strings(after[4:], count)):
                expected = old
                for source, target in TEXTURE_OVERRIDES.items():
                    expected = expected.replace('/' + source + ',', '/' + target + ',')
                self.assertEqual(expected, new)
            self.assertIn(b'pravo\\dead_city\\mtl_fence1\0', after.replace(b',', b'\0'))

    def test_dds_is_unmodified_transparent_donor(self):
        source = Path('C:/unpackedtt2/textures/mtl/mtl_fence1.dds')
        target = Path('build-deadcity/assets/gamedata/textures/pravo/dead_city/mtl_fence1.dds')
        self.assertEqual(hashlib.sha256(source.read_bytes()).digest(),
                         hashlib.sha256(target.read_bytes()).digest())
        with Image.open(target) as image:
            self.assertEqual(image.getchannel('A').getextrema(), (0, 255))


if __name__ == '__main__':
    unittest.main()
