"""Structural regression checks for the new-game-only story build."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_newgame_spawn import blocks, value

ROOT=Path(__file__).resolve().parents[2]


class NewGameSpawnTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects=[]
        cls.radar_objects=blocks((ROOT/'spawn-clean/alife_l10_radar.ltx').read_text(encoding='cp1251'))
        for path in (ROOT/'spawn-clean').glob('alife_*.ltx'):
            cls.objects.extend(blocks(path.read_text(encoding='cp1251')))

    def by_sid(self,sid):
        matches=[b for b in self.objects if value(b,'story_id')==str(sid)]
        self.assertEqual(len(matches),1,f'Missing/duplicate story ID {sid}')
        return matches[0]

    def test_intro_duty_and_corpses(self):
        for sid in (6510,6511):
            b=self.by_sid(sid)
            self.assertEqual(value(b,'health'),'1')
            self.assertIn('-pravo_pri_kindergarten_aftermath_done',b)
        for sid in range(6512,6516):
            self.assertIn('+pravo_pri_intro_done -pravo_pri_kindergarten_aftermath_done',self.by_sid(sid))
        for sid in (6516,6517):
            b=self.by_sid(sid)
            self.assertEqual(value(b,'health'),'0')
            self.assertEqual(value(b,'upd:health'),'0')
            self.assertIn('+pravo_pri_kindergarten_aftermath_done',b)

    def test_aftermath_is_tied_to_escape_not_dogs(self):
        triggers=[b for b in self.objects if value(b,'name')=='pravo_pri_escape_zone']
        self.assertEqual(len(triggers),1)
        self.assertIn('on_actor_outside = sr_idle@thought_delay %+pravo_pri_escape_done =pravo_pri_escape_aftermath%',triggers[0])
        effects=(ROOT/'story/gamedata/scripts/xr_effects.script').read_text(encoding='cp1251')
        self.assertIn('function pravo_pri_escape_aftermath(actor, npc)',effects)
        dialogs=(ROOT/'story/gamedata/scripts/pravo_dialogs.script').read_text()
        reward=dialogs.split('function freedom_leader_give_dog_reward',1)[1].split('\nend',1)[0]
        self.assertNotIn('setup_kindergarten_aftermath',reward)

    def test_bar_and_vendor(self):
        for sid in (6518,6519,6520):
            b=self.by_sid(sid)
            self.assertEqual(value(b,'section_name'),'stalker')
            self.assertIn('cfg = scripts\\pravo_mil_bar_visitor.ltx',b)
            if sid == 6520:
                self.assertIn('cond = {-pravo_mil_gift_ambush_spawned}', b)
            else:
                self.assertNotIn('[spawner]',b)
        cook=self.by_sid(728)
        self.assertGreater(float(value(cook,'position').split(',')[2]),37)
        self.assertIn('cfg = scripts\\pravo_mil_bar_cook.ltx',cook)
        self.assertNotIn('mil_freedom =',cook)
        self.assertEqual(value(self.by_sid(6521),'character_profile'),'pravo_rad_freedom_trader')

    def test_safe_campfire_and_normal_npcs(self):
        fires=[b for b in self.objects if value(b,'section_name')=='pravo_rad_safe_campfire']
        self.assertEqual(len(fires),1)
        self.assertEqual(value(fires[0],'max_power'),'0')
        self.assertFalse(any(value(b,'name')=='zone_flame_small_0010' for b in self.radar_objects))
        for b in self.objects:
            if value(b,'character_profile')=='pravo_rad_freedom_camper':
                self.assertEqual(value(b,'section_name'),'stalker')
        sections=(ROOT/'story/gamedata/config/creatures/pravo_story_sections.ltx').read_text()
        self.assertIn('max_start_power = 0',sections)

    def test_no_runtime_migrations_or_debug_ui(self):
        for relative in ('scripts/pravo_debug.script','scripts/pravo_camp_safety.script',
                         'scripts/pravo_military_bar.script','scripts/xr_motivator.script',
                         'config/pravo_military_cleanup.ltx','config/ui/ui_pravo_debug.xml',
                         'config/pravo_waypoints.ltx'):
            self.assertFalse((ROOT/'story/gamedata'/relative).exists(),relative)
        story=(ROOT/'story/gamedata/scripts/pravo_story.script').read_text()
        self.assertIn('g_god on',story)
        self.assertNotIn('pravo_debug',story)
        self.assertNotIn('ensure_',story)
        self.assertNotIn('pravo_military.update',story)
        dialog=(ROOT/'story/gamedata/scripts/pravo_dialogs.script').read_text()
        self.assertNotIn('ensure_kindergarten',dialog)
        self.assertNotIn('_spawn"',dialog)

    def test_profile_dialogues_and_native_vendor_registration(self):
        import re
        characters=(ROOT/'story/gamedata/config/gameplay/character_desc_military.xml').read_text(encoding='cp1251')
        for profile,dialog in [('mil_Svoboda_blockpost_leader','pravo_mil_barrier_intro'),
                               ('mil_Svoboda_leader','pravo_mil_lukash_intro')]:
            block=re.search('<specific_character id="'+profile+'".*?</specific_character>',characters,re.S).group()
            self.assertIn('<actor_dialog>'+dialog+'</actor_dialog>',block)
        manager=(ROOT/'story/gamedata/scripts/task_manager.script').read_text(encoding='cp1251')
        self.assertIn('[6521] = "pravo_rad_trader"',manager)
        self.assertIn('pravo_rad_trader = 6521',manager)
        wrapper=(ROOT/'story/gamedata/scripts/pravo_task_manager.script').read_text()
        self.assertNotIn('original_action_give_task',wrapper)


if __name__=='__main__':
    unittest.main()
