"""Populate Dead City using A-Life respawners, mob_home and native anomalies.

Coordinates are selected from the imported map's actual game graph and its AI
nodes, not guessed XYZs. Rebuilds are deterministic and leave other levels alone.
"""
import argparse
from collections import deque
import json
import math
from pathlib import Path
import re
import struct

from build_newgame_spawn import LevelAI, blocks, value, set_value

# Graph anchors checked against map_dead_city: forests/edges vs urban yards.
HABITATS = [
    ("boar_west", "boar_normal", 3513, 2, 18, 38),
    ("boar_northwest", "boar_normal", 3531, 3, 18, 38),
    ("dog_southwest", "dog_weak", 3524, 4, 18, 36),
    ("dog_north", "dog_weak", 3566, 4, 18, 36),
    ("dog_east", "dog_normal", 3588, 4, 18, 36),
    ("zombie_north_yard", "zombie_weak", 3539, 5, 10, 24),
    ("zombie_centre_yard", "zombie_normal", 3560, 5, 10, 24),
    ("zombie_south_street", "zombie_weak", 3571, 5, 10, 24),
]
# Two small hazards per field; no radiation blanket or blocked transition.
FIELDS = [
    ("west_scrub", 3514, "zone_mincer_weak_noart"),
    ("north_hollow", 3528, "zone_mosquito_bald_weak"),
    ("west_ruins", 3532, "zone_mincer_weak_noart"),
    ("north_roadside", 3554, "zone_mosquito_bald_weak"),
    ("south_ruins", 3569, "zone_mincer_weak_noart"),
    ("east_scrub", 3586, "zone_mosquito_bald_weak"),
    ("southwest_yard", 3536, "zone_mosquito_bald_weak"),
]


def cells(data):
    """SoC chunked cross-table: every AI node -> exact merged game vertex."""
    pos = 0
    while pos < len(data):
        chunk, size = struct.unpack_from('<II', data, pos)
        payload = data[pos+8:pos+8+size]
        if chunk == 1:
            return [gv for gv, distance in struct.iter_unpack('<Hf', payload)]
        pos += 8 + size
    raise ValueError('Missing cross-table cells')


def links(ai, vertex):
    packed = int.from_bytes(ai.data[56+vertex*21:56+vertex*21+12], 'little')
    return [v for shift in (0, 23, 46, 69)
            if (v := (packed >> shift) & 0x7fffff) < ai.count]


def neighbourhood(ai, start, radius):
    """Connected, same-height outdoor AI nodes; no roofs/isolated platforms."""
    origin = ai.position(start)
    visited, queue, result = {start}, deque([start]), []
    while queue:
        vertex = queue.popleft()
        pos = ai.position(vertex)
        if math.dist(pos, origin) > radius or abs(pos[1]-origin[1]) > 3:
            continue
        neighbours = links(ai, vertex)
        if len(neighbours) >= 3:
            result.append((vertex, pos))
        for node in neighbours:
            if node not in visited:
                visited.add(node)
                queue.append(node)
    return result


def separated(candidates, count, spacing):
    # Stable farthest-point sampling distributes the pack over walkable ground.
    result = [min(candidates, key=lambda node: node[0])]
    while len(result) < count:
        best = max(candidates, key=lambda node: min(math.dist(node[1], p[1]) for p in result))
        if min(math.dist(best[1], p[1]) for p in result) < spacing:
            raise ValueError('Not enough separated walkable spawn positions')
        result.append(best)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', required=True)
    args = ap.parse_args()
    root = Path(args.project)
    spawn = root/'spawn-clean'
    config = root/'story/gamedata/config'
    ai = LevelAI((root/'build-deadcity/assets/gamedata/levels/dead_city/level.ai').read_bytes())
    graph = json.loads((root/'build-deadcity/graph.json').read_text())
    vertices = {v['gv']: v for v in graph['vertices']}
    cross = cells((root/'build-deadcity/level.gct').read_bytes())
    assert len(cross) == ai.count
    entrance = (141.940994, 1.228696, -134.634094)
    objects = [b for b in blocks((spawn/'alife_dead_city.ltx').read_text(encoding='cp1251'))
               if not value(b, 'name').startswith('pravo_dc_population_')]
    ways, manifest = [], {'habitats': [], 'fields': [], 'max_alive': 0}
    sections = ['; Native respawn, native monster AI; Dead City only.',
                '[pravo_dc_respawn]:respawn', 'class = PR_DC_RP', '']
    next_id = 12500

    def node(vertex):
        pos = ai.position(vertex)
        return {'lv': vertex, 'gv': cross[vertex], 'position': [pos[0], pos[1]+.05, pos[2]]}

    def path(name, points):
        text = f'[{name}]\npoints = '+','.join(f'p{i}' for i in range(len(points)))+'\n'
        for i, point in enumerate(points):
            text += (f'p{i}:name = wp{i:02}\np{i}:position = '+','.join(map(str, point['position']))+
                     f"\np{i}:game_vertex_id = {point['gv']}\np{i}:level_vertex_id = {point['lv']}\n")
        ways.append(text)

    for pack, (name, base, anchor, cap, min_radius, max_radius) in enumerate(HABITATS, 1):
        center = node(vertices[anchor]['lv'])
        assert math.dist(center['position'], vertices[anchor]['position']) < 2
        candidates = neighbourhood(ai, center['lv'], 11)
        points = [node(v) for v, _ in separated(candidates, cap, 2)]
        assert all(math.dist(p['position'], entrance) > 110 for p in points)
        home, spawnpath = f'pravo_dc_{name}_home', f'pravo_dc_{name}_spawn'
        path(home, [center])
        path(spawnpath, points)
        cfg = config/f'scripts/pravo_dc_{name}.ltx'
        cfg.write_text(f'''[smart_terrains]
none = true
[logic]
active = mob_home
[mob_home]
path_home = {home}
home_min_radius = {min_radius}
home_max_radius = {max_radius}
''', encoding='ascii', newline='\n')
        section = f'pravo_dc_{name}'
        sections.extend([f'[{section}]:{base}', f'custom_data = scripts\\pravo_dc_{name}.ltx'])
        # Stock CZombie lacks the portrait required by CUICarBodyWnd on loot.
        # Reuse an existing registered zombie portrait; no new texture needed.
        if base.startswith('zombie_'):
            sections.append('icon = ui_npc_u_zombie_fresh_0')
        sections.append('')
        text = f'''[{next_id}]
section_name = pravo_dc_respawn
name = pravo_dc_population_{name}
position = {','.join(map(str, center['position']))}
direction = 0,0,0
id = 65535
version = 118
script_version = 6
spawn_id = {next_id}
game_vertex_id = {center['gv']}
level_vertex_id = {center['lv']}
object_flags = 0xffffff3e
custom_data = <<END
[respawn]
respawn_section = {section}
min_count = 0
max_count = {cap}
max_spawn = {cap}
idle_spawn = 21600,43200
conditions = 100
respawn_radius = 220
path_spawn = {spawnpath}
pack_id = {pack}
END
shapes = 1
shape_0:type = sphere
shape_0:offset = 0,0,0
shape_0:radius = 1
restrictor_type = 0
spawned_obj =
'''
        objects.append(text)
        manifest['habitats'].append(dict(name=name, base=base, cap=cap, radius=max_radius,
                                         center=center, points=points, spawn_id=next_id))
        manifest['max_alive'] += cap
        next_id += 1

    templates = blocks((root/'spawn-vanilla/alife_l01_escape.ltx').read_text(encoding='cp1251'))
    for name, anchor, section in FIELDS:
        template = next(b for b in templates if value(b, 'section_name') == section)
        points = [node(v) for v, _ in separated(neighbourhood(ai, vertices[anchor]['lv'], 8), 2, 7)]
        assert all(math.dist(p['position'], entrance) > 110 for p in points)
        for i, point in enumerate(points):
            text = re.sub(r'^\[\d+\]', f'[{next_id}]', template)
            for key, val in {'name': f'pravo_dc_population_anomaly_{name}_{i}',
                             'spawn_id': next_id, 'game_vertex_id': point['gv'],
                             'level_vertex_id': point['lv'], 'position': ','.join(map(str, point['position'])),
                             'direction': '0,0,0', 'shape_0:radius': 2.5,
                             'artefact_spawn_count': 0, 'artefact_position_offset': 0}.items():
                text = set_value(text, key, val)
            objects.append(text)
            next_id += 1
        manifest['fields'].append(dict(name=name, section=section, points=points, radius=2.5))

    (spawn/'alife_dead_city.ltx').write_text('\n\n'.join(objects), encoding='cp1251', newline='\n')
    (spawn/'way_dead_city.ltx').write_text('\n\n'.join(ways), encoding='ascii', newline='\n')
    (config/'creatures/pravo_dc_population.ltx').write_text('\n'.join(sections), encoding='ascii', newline='\n')
    all_ltx = (spawn/'all.ltx').read_text(encoding='cp1251')
    if 'way_dead_city.ltx' not in all_ltx:
        all_ltx = all_ltx.replace('[way]\nsource_files = <<END\n', '[way]\nsource_files = <<END\nway_dead_city.ltx,\n')
    (spawn/'all.ltx').write_text(all_ltx, encoding='cp1251', newline='\n')
    (root/'build-deadcity/population.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(f"Dead City: {len(HABITATS)} habitats, <= {manifest['max_alive']} mutants, {len(FIELDS)} anomaly fields")


if __name__ == '__main__':
    main()
