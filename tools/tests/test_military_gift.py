"""Validate authored quest data; native behaviour is covered by military_gift.script."""
import json
import math
from pathlib import Path
import re
import sys
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from build_newgame_spawn import blocks, value, LevelAI
from build_deadcity_population import cells, neighbourhood


def xml(name):
    data = (ROOT/'story/gamedata/config/gameplay'/name).read_text(encoding='cp1251')
    data = re.sub(r'<\?xml[^>]+>', '', data)
    # X-Ray's include directives are text, rather than XML elements.
    return ET.fromstring('<root>'+data+'</root>')


class MilitaryGiftTests(unittest.TestCase):
    def test_speaker_order_without_game_object_equality(self):
        subprocess.run([sys.executable, '-B', str(ROOT/'tools/tests/run_lua_test.py'),
                        str(ROOT/'story/gamedata/scripts/pravo_mil_gift.script'),
                        str(ROOT/'tools/tests/test_military_gift_dialog.lua')], check=True)

    @classmethod
    def setUpClass(cls):
        cls.objects=[]
        for path in (ROOT/'spawn-clean').glob('alife_*.ltx'):
            cls.objects.extend(blocks(path.read_text(encoding='cp1251')))

    def by_sid(self, sid):
        found=[b for b in self.objects if value(b,'story_id')==str(sid)]
        self.assertEqual(len(found),1, f'Duplicate or missing SID {sid}')
        return found[0]

    def test_one_existing_traitor_and_exactly_three_one_shot_guards(self):
        traitor=self.by_sid(6520)
        self.assertEqual(value(traitor,'character_profile'),'pravo_mil_bar_traitor')
        self.assertIn('cond = {-pravo_mil_gift_ambush_spawned}',traitor)
        self.assertEqual(sum(value(b,'character_profile')=='pravo_mil_bar_traitor' for b in self.objects),1)
        guards=[b for b in self.objects if value(b,'name').startswith('pravo_mil_gift_guard_')]
        self.assertEqual(len(guards),3)
        for i in range(1,4):
            b=self.by_sid(6530+i)
            self.assertIn('cond = {+pravo_mil_gift_ambush_started}',b)
            self.assertEqual(value(b,'section_name'),'stalker')
            self.assertNotIn('respawn',b)

    def test_attic_shape_and_acceptance_gate(self):
        b=self.by_sid(6530)
        self.assertEqual(value(b,'section_name'),'space_restrictor')
        x,y,z=map(float,value(b,'position').split(','))
        self.assertAlmostEqual(x,-296.806)
        self.assertAlmostEqual(z,291.181)
        self.assertLess(abs(y-(-18.027)),.8)
        self.assertGreater(y-.8,-19)
        self.assertIn('{+pravo_mil_gift_accepted -pravo_mil_gift_entered}',b)

    def test_single_point_walker_paths_have_native_terminal_flag(self):
        ways=(ROOT/'spawn-clean/way_l07_military.ltx').read_text(encoding='cp1251')
        for i in range(1,4):
            path=ways.split(f'[pravo_mil_gift_guard_{i}_walk]')[1].split('\n[')[0]
            self.assertIn('p0:flags = 0x1',path)

    def test_valid_separated_connected_ground_positions_and_cross_table(self):
        ai=LevelAI((ROOT/'build-deadcity/newgame/l07_military/level.ai').read_bytes())
        cross=cells((ROOT/'build-deadcity/military-gift/level.gct').read_bytes())
        manifest=json.loads((ROOT/'build-deadcity/military-gift/placements.json').read_text())
        guards=manifest['guards']
        connected={v for v,_ in neighbourhood(ai, guards[0]['lv'], 8)}
        for i,point in enumerate(guards):
            self.assertEqual(point['gv'],cross[point['lv']])
            self.assertIn(point['lv'],connected)
            self.assertLess(math.dist(point['position'],(-307.715,-22.064,288.178)),7)
            self.assertLess(math.dist(ai.position(point['lv']),point['position']),.1)
            for other in guards[:i]: self.assertGreater(math.dist(point['position'],other['position']),2.5)

    def test_unique_leader_evidence_survives_native_death_inventory_filter(self):
        profiles=xml('character_desc_pravo_bar.xml')
        found=[]
        for i in range(1,4):
            p=profiles.find(f'.//specific_character[@id="pravo_mil_gift_guard_{i}"]')
            self.assertIsNotNone(p)
            self.assertEqual(p.findtext('community'),'dolg')
            self.assertIn('wpn_groza',p.findtext('supplies'))
            if 'pravo_mil_duty_pda' in p.findtext('supplies'): found.append(i)
        self.assertEqual(found,[1])
        death=(ROOT/'story/gamedata/config/misc/death_generic.ltx').read_text(encoding='cp1251')
        keep=death.split('[keep_items]')[1].split('\n[')[0]
        self.assertIn('pravo_mil_duty_pda = true',keep)
        items=(ROOT/'story/gamedata/config/misc/pravo_items.ltx').read_text(encoding='cp1251')
        self.assertIn('[pravo_mil_duty_pda]:bar_tiran_pda',items)

    def test_dialogue_conditions_and_no_traitor_marker_or_meeting_task(self):
        dialogs=xml('dialogs_pravo_military.xml')
        offer=dialogs.find('.//dialog[@id="pravo_mil_gift_offer"]')
        ret=dialogs.find('.//dialog[@id="pravo_mil_gift_return"]')
        self.assertEqual(offer.findtext('dont_has_info'),'pravo_mil_gift_accepted')
        self.assertEqual(ret.findtext('has_info'),'pravo_mil_gift_pda_found')
        self.assertEqual(ret.findtext('dont_has_info'),'pravo_mil_gift_done')
        self.assertEqual(len(offer.findall('.//action')),1)
        self.assertEqual(offer.findtext('.//action'),'pravo_mil_gift.accept')
        self.assertEqual(ret.findtext('.//action'),'pravo_mil_gift.finish')
        tasks=xml('tasks_pravo_military.xml')
        gift_tasks=[t for t in tasks.findall('.//game_task') if t.attrib['id'].startswith('pravo_mil_gift')]
        self.assertEqual(len(gift_tasks),2)
        markers=[node.text for t in gift_tasks for node in t.findall('.//object_story_id')]
        self.assertEqual(markers,['pravo_mil_gift_attic','Mil_Lukash'])
        info=xml('info_pravo_military.xml')
        self.assertEqual(info.findtext('.//info_portion[@id="pravo_mil_gift_pda_found"]/article'),'pravo_mil_gift_evidence')


if __name__=='__main__': unittest.main()
