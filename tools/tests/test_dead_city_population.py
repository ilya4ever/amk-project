"""Static checks supplement (not replace) the native engine integration probe."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_deadcity_population import HABITATS, FIELDS, cells, links, neighbourhood
from build_newgame_spawn import LevelAI, blocks, value

ROOT = Path(__file__).resolve().parents[2]


class PopulationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT/'build-deadcity/population.json').read_text())
        cls.objects = blocks((ROOT/'spawn-clean/alife_dead_city.ltx').read_text(encoding='cp1251'))
        cls.ai = LevelAI((ROOT/'build-deadcity/assets/gamedata/levels/dead_city/level.ai').read_bytes())
        cls.cross = cells((ROOT/'build-deadcity/level.gct').read_bytes())

    def test_only_mutants_and_native_infrastructure(self):
        allowed = {'climable_object','lights_hanging_lamp','level_changer',
                   'pravo_dc_respawn','zone_mincer_weak_noart','zone_mosquito_bald_weak'}
        self.assertTrue(all(value(b,'section_name') in allowed for b in self.objects))
        self.assertEqual(len(self.objects), 10+8+14)
        self.assertEqual(sum(h[3] for h in HABITATS), 32)

    def test_no_duplicate_ids_or_names(self):
        objects=[]
        for path in (ROOT/'spawn-clean').glob('alife_*.ltx'):
            objects.extend(blocks(path.read_text(encoding='cp1251')))
        ids=[value(b,'spawn_id') for b in objects]
        self.assertEqual(len(ids),len(set(ids)))
        names=[value(b,'name') for b in self.objects]
        self.assertEqual(len(names),len(set(names)))

    def test_connected_spawn_points_and_exact_cross_table(self):
        for h in self.manifest['habitats']:
            connected = {lv for lv,_ in neighbourhood(self.ai,h['center']['lv'],11)}
            self.assertEqual(len(h['points']), h['cap'])
            for p in h['points']:
                self.assertIn(p['lv'],connected)
                self.assertEqual(p['gv'],self.cross[p['lv']])
                self.assertGreaterEqual(len(links(self.ai,p['lv'])),3)

    def test_native_ai_sections_and_limits(self):
        config=(ROOT/'story/gamedata/config/creatures/pravo_dc_population.ltx').read_text()
        for name,base,anchor,cap,minr,maxr in HABITATS:
            self.assertIn(f'[pravo_dc_{name}]:{base}',config)
            logic=(ROOT/f'story/gamedata/config/scripts/pravo_dc_{name}.ltx').read_text()
            self.assertIn('active = mob_home',logic)
            self.assertIn('none = true',logic)
            block=next(b for b in self.objects if value(b,'name')=='pravo_dc_population_'+name)
            self.assertIn(f'max_count = {cap}\n',block)
            self.assertIn('idle_spawn = 21600,43200',block)

    def test_anomalies_and_clear_transition(self):
        import math
        entry=(141.940994,1.228696,-134.634094)
        self.assertEqual(len(FIELDS),7)
        for field in self.manifest['fields']:
            self.assertEqual(len(field['points']),2)
            for p in field['points']:
                self.assertGreater(math.dist(p['position'],entry),110)
                self.assertEqual(p['gv'],self.cross[p['lv']])

    def test_zombie_death_statistics_and_direct_server_wrapper(self):
        classes=(ROOT/'story/gamedata/scripts/class_registrator.script').read_text(encoding='cp1251')
        self.assertEqual(classes.count('"pravo_dc_respawn.dc_respawn"'),1)
        stats=(ROOT/'story/gamedata/scripts/xr_statistic.script').read_text(encoding='cp1251')
        self.assertIn('[clsid.zombie_s] = "zombie"',stats)
        server=(ROOT/'story/gamedata/scripts/pravo_dc_respawn.script').read_text()
        self.assertIn('class "dc_respawn" (cse_alife_smart_zone)',server)
        self.assertIn('utils.w_CTime(packet, self.dc_due)',server)
        self.assertIn('self:prune()',server)

    def test_corpse_portraits_exist_for_every_habitat(self):
        import re
        import xml.etree.ElementTree as ET
        texts=[(ROOT/'story/gamedata/config/creatures/pravo_dc_population.ltx').read_text()]
        for species in ('boar','dog','zombie'):
            texts.append((ROOT/f'vanilla-reference/config/creatures/m_{species}.ltx').read_text(encoding='cp1251'))
        sections={}
        for text in texts:
            for match in re.finditer(r'(?ms)^\[([^\]]+)\]([^\r\n]*)\r?\n(.*?)(?=^\[|\Z)',text):
                name,parents,body=match.groups()
                parent=parents.lstrip(':').strip().split(',')[0].strip()
                icon=re.search(r'(?m)^\s*icon\s*=\s*([^;\r\n]+)',body)
                sections[name]=(parent,icon.group(1).strip() if icon else None)
        icons=set()
        for file in ('ui_npc_unique.xml','ui_npc_monster.xml'):
            icons.update(e.attrib['id'] for e in ET.parse(ROOT/'vanilla-reference/config/ui'/file).iter('texture'))
        for name,*_ in HABITATS:
            section='pravo_dc_'+name
            icon=None
            while section in sections:
                section,icon=sections[section]
                if icon: break
            self.assertIsNotNone(icon,f'Loot window icon missing: {name}')
            self.assertIn(icon,icons,f'Loot portrait not registered: {name}')


if __name__=='__main__':
    unittest.main()
