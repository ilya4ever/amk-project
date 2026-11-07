from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]


class AtmosphericsTests(unittest.TestCase):
    def test_weather_manager_save_compatibility(self):
        subprocess.run([sys.executable,'-B',str(ROOT/'tools/tests/run_lua_test.py'),
                        str(ROOT/'story/gamedata/scripts/level_weathers.script'),
                        str(ROOT/'tools/tests/test_atmospherics_weather.lua')],check=True)

    def test_cycles_and_game_levels(self):
        folder=ROOT/'story/gamedata/config/environment'
        cycles={p.stem for p in (folder/'weathers').glob('*.ltx')}
        self.assertGreaterEqual(len(cycles),20)
        graph=(folder/'dynamic_weather_graphs.ltx').read_text(encoding='utf-8-sig')
        names=re.findall(r'(?m)^\s*(w_\w+)\s*=',graph)
        self.assertTrue(set(names)<=cycles)
        for path in (folder/'weathers').glob('*.ltx'):
            self.assertGreaterEqual(len(re.findall(r'(?m)^\[\d\d:\d\d:\d\d\]',path.read_text(encoding='utf-8-sig'))),2)
        maps=(ROOT/'story/gamedata/config/game_maps_single.ltx').read_text(encoding='cp1251')
        for section,body in re.findall(r'(?ms)^\[([^\]]+)\](.*?)(?=^\[|\Z)',maps):
            weather=re.search(r'(?m)^\s*weathers\s*=\s*([^;\r\n]+)',body)
            if not weather:continue
            expected='indoor' if section.lower() in {'l03u_agr_underground','l04u_labx18','l08u_brainlab','l10u_bunker','l12u_sarcofag','l12u_control_monolith'} else 'dynamic_default'
            self.assertEqual(weather.group(1).strip(),expected,section)
        self.assertIn('[dead_city]',maps)

    def test_mod_filesystem_and_installed_configuration(self):
        fs=(ROOT/'game/fsgame.ltx').read_text()
        self.assertIn('$game_weathers$',fs)
        self.assertIn('$game_weather_effects$',fs)
        for path in (ROOT/'story/gamedata/config/environment').rglob('*.ltx'):
            relative=path.relative_to(ROOT/'story/gamedata')
            self.assertEqual(path.read_bytes(),(ROOT/'game/gamedata'/relative).read_bytes(),str(relative))

    def test_sky_textures_available(self):
        # These are the large additional media files, absent from vanilla SoC.
        textures=set()
        for path in (ROOT/'story/gamedata/config/environment').rglob('*.ltx'):
            text=path.read_text(encoding='utf-8-sig',errors='replace')
            textures.update(re.findall(r'(?m)^[ \t]*(?:sky_texture|clouds_texture)[ \t]*=[ \t]*([^;\r\n]*)',text))
        missing=[]
        for name in textures:
            name=name.strip()
            if not name: continue
            texture=ROOT/'game/gamedata/textures'/(name.replace('\\','/')+'.dds')
            if not texture.exists():missing.append(name)
        self.assertFalse(missing,'Missing sky/cloud media: '+str(sorted(missing)))


if __name__=='__main__': unittest.main()
