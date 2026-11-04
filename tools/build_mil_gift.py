"""One-shot military ambush, using the map's original AI graph and cross-table."""
import argparse
import json
import math
from pathlib import Path
import re
import subprocess

from build_newgame_spawn import LevelAI, blocks, value
from build_deadcity_population import cells, neighbourhood


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', required=True)
    args = ap.parse_args()
    root = Path(args.project)
    config = root / 'story/gamedata/config'
    stage = root / 'build-deadcity/military-gift'
    stage.mkdir(parents=True, exist_ok=True)
    ai = LevelAI((root / 'build-deadcity/newgame/l07_military/level.ai').read_bytes())
    gct = stage / 'level.gct'
    if not gct.exists():
        sevenzip = root.parent / 'mod-tools/7zip-xdb/7z.exe'
        subprocess.run([str(sevenzip), 'e', str(root/'game/gamedata.dbb'),
                        r'levels\l07_military\level.gct', '-o'+str(stage), '-y'],
                       check=True, capture_output=True)
    cross = cells(gct.read_bytes())
    assert len(cross) == ai.count
    center, _ = ai.nearest((-307.715, -22.064, 288.178))
    candidates = neighbourhood(ai, center, 6)
    chosen = [(center, ai.position(center))]
    # Keep the whole group near the supplied point and on one connected floor.
    while len(chosen) < 3:
        candidate = max(candidates, key=lambda p: min(math.dist(p[1], q[1]) for q in chosen))
        assert min(math.dist(candidate[1], q[1]) for q in chosen) >= 2.5
        chosen.append(candidate)
    def node(vertex):
        x, y, z = ai.position(vertex)
        return {'lv': vertex, 'gv': cross[vertex], 'position': (x, y+.05, z)}
    positions = [node(v) for v, _ in chosen]
    # The attic is above the AI map: attach its restrictor to the nearest ground
    # node, while retaining the exact trigger height instead of snapping it.
    attic_lv, _ = ai.nearest((-296.806, -22.027, 291.181))
    attic = {'lv': attic_lv, 'gv': cross[attic_lv],
             'position': (-296.806, -17.427, 291.181)}
    objects_path = root / 'spawn-clean/alife_l07_military.ltx'
    objects = [b for b in blocks(objects_path.read_text(encoding='cp1251'))
               if not value(b, 'name').startswith('pravo_mil_gift_')]
    ways_path = root / 'spawn-clean/way_l07_military.ltx'
    ways = ways_path.read_text(encoding='cp1251')
    ways = re.sub(r'(?ms)^\[pravo_mil_gift_[^\]]+\].*?(?=^\[|\Z)', '', ways)
    report = {'attic': attic, 'guards': positions}
    def coords(p): return ','.join(map(str, p['position']))
    def header(number, section, name, point, sid):
        return f'''[{number}]
section_name = {section}
name = {name}
position = {coords(point)}
direction = 0,3.608852,0
id = 65535
version = 118
script_version = 6
spawn_id = {number}
game_vertex_id = {point['gv']}
level_vertex_id = {point['lv']}
object_flags = {'0xffffffff' if section == 'stalker' else '0xffffff3e'}
story_id = {sid}
'''
    objects.append(header(13000, 'space_restrictor', 'pravo_mil_gift_attic', attic, 6530)+'''custom_data = <<END
[logic]
active = sr_idle
[sr_idle]
on_actor_inside = {+pravo_mil_gift_accepted -pravo_mil_gift_entered} nil %+pravo_mil_gift_entered%
END
shapes = 1
shape_0:type = box
shape_0:offset = 0,0,0
shape_0:axis_x = 3,0,0
shape_0:axis_y = 0,1.6,0
shape_0:axis_z = 0,0,3
restrictor_type = 0
''')
    chars = (root/'vanilla-reference/config/gameplay/character_desc_military.xml').read_text(encoding='cp1251')
    bar = config / 'gameplay/character_desc_pravo_bar.xml'
    profiles = bar.read_text(encoding='cp1251')
    profiles = re.sub(r'(?s)\s*<specific_character id="pravo_mil_gift_guard_.*?</specific_character>', '', profiles)
    registration = config / 'gameplay/npc_pravo_bar.xml'
    reg = registration.read_text(encoding='cp1251')
    reg = re.sub(r'(?s)\s*<character id="pravo_mil_gift_guard_.*?</character>', '', reg)
    for i, point in enumerate(positions, 1):
        name = f'pravo_mil_gift_guard_{i}'
        base = 'mil_Dolg_specnaz_silence' if i == 1 else 'mil_Dolg_specnaz'
        profile = re.search(r'<specific_character id="'+base+r'".*?</specific_character>', chars, re.S).group()
        profile = profile.replace('id="'+base+'"', 'id="'+name+'"')
        profile = re.sub(r'<class>.*?</class>', '<class>'+name+'</class>', profile)
        profile = re.sub(r'<(?:actor_dialog|start_dialog)>.*?</(?:actor_dialog|start_dialog)>', '', profile)
        if i == 1:
            profile = profile.replace('</supplies>', r' \n pravo_mil_duty_pda</supplies>')
        profiles = profiles.replace('</xml>', profile+'\n</xml>')
        reg = reg.replace('</xml>', f'<character id="{name}"><class>{name}</class><specific_character>{name}</specific_character></character>\n</xml>')
        visual = re.search(r'<visual>(.*?)</visual>', profile).group(1)
        objects.append(header(13000+i, 'stalker', name, point, 6530+i)+f'''character_profile = {name}
money = 500
custom_data = <<END
[spawner]
cond = {{+pravo_mil_gift_ambush_started}}
[smart_terrains]
none = true
[logic]
cfg = scripts\\{name}.ltx
END
visual_name = {visual}
g_team = 0
g_squad = 0
g_group = 0
health = 1
dynamic_out_restrictions =
dynamic_in_restrictions =
equipment_preferences = 1,1,1,1,1
main_weapon_preferences = 1,1,1,1
upd:health = 1
upd:timestamp = 0
upd:creature_flags = 0
upd:position = {coords(point)}
upd:o_torso = 3.608852,0,0
upd:g_squad = 0
upd:start_dialog =
''')
        # A short native walker path brings the gunmen toward the house.
        # All points are connected AI vertices; combat stays with engine AI.
        target = min(candidates, key=lambda p: math.dist(p[1], (-301, -22, 287+2*i)))
        for suffix, p in [('walk', node(target[0]))]:
            ways += f'\n[{name}_{suffix}]\npoints = p0\np0:name = wp00\np0:flags = 0x1\np0:position = {coords(p)}\np0:game_vertex_id = {p["gv"]}\np0:level_vertex_id = {p["lv"]}\n'
        (config/f'scripts/{name}.ltx').write_text(f'''[smart_terrains]
none = true
[logic]
active = walker@ambush
on_death = death
[walker@ambush]
path_walk = {name}_walk
meet = no_meet
def_state_moving1 = assault
def_state_moving2 = assault
def_state_moving3 = assault
on_info = walker@fight %=actor_enemy%
[walker@fight]:walker@ambush
on_info =
[death]
on_info = %+pravo_mil_gift_guard_{i}_dead%
''', encoding='ascii')
    objects_path.write_text('\n\n'.join(b.rstrip() for b in objects)+'\n', encoding='cp1251', newline='\n')
    ways_path.write_text(ways, encoding='cp1251', newline='\n')
    bar.write_text(profiles, encoding='cp1251')
    registration.write_text(reg, encoding='cp1251')
    sid_path = config/'game_story_ids.ltx'
    sids = sid_path.read_text(encoding='cp1251')
    for sid, name in [(6530, 'pravo_mil_gift_attic')]+[(6530+i, f'pravo_mil_gift_guard_{i}') for i in range(1,4)]:
        sids = re.sub(r'(?m)^\s*'+str(sid)+r'\s*=.*$', '', sids)
        sids += f'\n{sid} = "{name}"\n'
    sid_path.write_text(sids, encoding='cp1251')
    # The native death manager deletes non-whitelisted inventory on death.
    death_path = config/'misc/death_generic.ltx'
    death = death_path.read_text(encoding='cp1251') if death_path.exists() else (root/'vanilla-reference/config/misc/death_generic.ltx').read_text(encoding='cp1251')
    if 'pravo_mil_duty_pda' not in death:
        death = death.replace('[keep_items]', '[keep_items]\npravo_mil_duty_pda = true')
    death_path.write_text(death, encoding='cp1251')
    (stage/'placements.json').write_text(json.dumps(report, indent=2))
    print('Military gift: attic trigger, 3 connected AI positions, leader PDA preserved on death')


if __name__ == '__main__':
    main()
