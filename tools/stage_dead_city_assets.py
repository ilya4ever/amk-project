"""Stage only Dead City geometry and its missing rendering dependencies."""
import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
from PIL import Image


# Vanilla mtl_fence1.dds is an opaque developer placeholder. Give the TT2
# replacement a level-specific name rather than changing fences on every map.
TEXTURE_OVERRIDES = {'mtl\\mtl_fence1': 'pravo\\dead_city\\mtl_fence1'}


def chunks(data):
    pos = 0
    while pos + 8 <= len(data):
        tag, size = struct.unpack_from('<II', data, pos)
        pos += 8
        if pos + size > len(data):
            raise ValueError('Invalid chunk boundary')
        yield tag, data[pos:pos + size]
        pos += size


def strings(data, count):
    result = []
    for _ in range(count):
        end = data.index(b'\0')
        result.append(data[:end].decode('cp1251'))
        data = data[end + 1:]
    return result


def remap_level_textures(data, replacements):
    output = bytearray()
    matched = set()
    for tag, payload in chunks(data):
        if tag == 2:
            count, = struct.unpack_from('<I', payload)
            definitions = strings(payload[4:], count)
            updated = []
            for definition in definitions:
                shader, slash, texture_list = definition.partition('/')
                textures = texture_list.split(',')
                for i, name in enumerate(textures):
                    if name.lower() in replacements:
                        matched.add(name.lower())
                        textures[i] = replacements[name.lower()]
                updated.append(shader + slash + ','.join(textures))
            payload = struct.pack('<I', count) + b''.join(
                s.encode('cp1251') + b'\0' for s in updated)
        output.extend(struct.pack('<II', tag, len(payload)))
        output.extend(payload)
    if matched != set(replacements):
        raise ValueError('Expected fence material not found in donor level')
    return output


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', required=True)
    ap.add_argument('--donor', required=True)
    ap.add_argument('--sevenzip', required=True)
    args = ap.parse_args()
    project, donor = Path(args.project), Path(args.donor)
    stage = project / 'build-deadcity' / 'assets' / 'gamedata'
    game = project / 'game'
    level = donor / 'levels' / 'dead_city'
    shader_blob = (game / 'gamedata' / 'shaders.xr').read_bytes()
    available = set()
    for archive in sorted(game.glob('gamedata.db*')):
        result = subprocess.run([args.sevenzip, 'l', '-slt', str(archive)],
                                capture_output=True, check=True)
        for line in result.stdout.decode('utf-8', errors='replace').splitlines():
            if line.startswith('Path = '):
                available.add(line[7:].replace('\\', '/').lower())
    # Only the base archives count as installed dependencies. Counting our own
    # previous deployment here would silently omit textures on a clean rebuild.
    shader_data = dict(chunks((level / 'level').read_bytes()))[2]
    count, = struct.unpack_from('<I', shader_data)
    definitions = strings(shader_data[4:], count)
    shaders, textures = set(), set()
    for definition in definitions:
        if not definition:
            continue
        shader, _, texture_list = definition.partition('/')
        shaders.add(shader)
        textures.update(t.strip().lower() for t in texture_list.split(',') if t.strip())
    detail_models = dict(chunks((level / 'level.details').read_bytes())).get(1)
    if detail_models:
        for _, model in chunks(detail_models):
            shader, texture = strings(model, 2)
            shaders.add(shader)
            textures.add(texture.lower())
    missing_shaders = sorted(s for s in shaders if s.encode('cp1251') + b'\0' not in shader_blob)
    if missing_shaders:
        raise RuntimeError('Unsupported OGSR shader names: ' + ', '.join(missing_shaders))
    target_level = stage / 'levels' / 'dead_city'
    target_level.mkdir(parents=True, exist_ok=True)
    # Deliberately exclude donor NPC spawn, quests, graphs and developer statistics.
    names = ['level', 'level.geom', 'level.geomx', 'level.cform', 'level.ai',
             'level.hom', 'level.details', 'level.ltx', 'level.game', 'level.wallmarks',
             'level_lods.dds', 'level_lods_nm.dds', 'build_details.dds']
    names += [p.name for p in level.glob('lmap#*.dds')]
    for name in names:
        shutil.copy2(level / name, target_level / name)
    (target_level / 'level').write_bytes(
        remap_level_textures((level / 'level').read_bytes(), TEXTURE_OVERRIDES))
    if (level / 'terrain').is_dir():
        shutil.copytree(level / 'terrain', target_level / 'terrain', dirs_exist_ok=True)
    metadata = {'association': {}, 'specification': {}}
    section = ''
    for raw in (donor / 'textures' / 'textures.ltx').read_text(encoding='cp1251').splitlines():
        line = raw.split(';', 1)[0].strip()
        if line.startswith('['):
            section = line.strip('[]').lower()
        elif '=' in line and section in metadata:
            key, value = line.split('=', 1)
            metadata[section][key.strip().lower()] = value.strip()
    copied, failures = set(), set()

    def ensure_texture(name):
        name = name.replace('\\', '/').removesuffix('.dds').lower()
        if name.startswith('$') or (level / (name + '.dds')).is_file():
            return
        asset = 'textures/' + name + '.dds'
        if asset in available or asset in copied:
            return
        source = donor / asset
        if not source.is_file():
            failures.add(name)
            return
        destination = stage / asset
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied.add(asset)
        for suffix in ('_bump', '_bump#'):
            bump = donor / ('textures/' + name + suffix + '.dds')
            if bump.is_file():
                ensure_texture(name + suffix)

    for texture in sorted(textures):
        ensure_texture(texture)
    # BmmD resolves these by convention rather than listing them in level chunk 2.
    ensure_texture('terrain/terrain_gr_mask')
    puddles_mask = stage / 'textures' / 'terrain' / 'terrain_gr_puddles_mask.dds'
    puddles_mask.parent.mkdir(parents=True, exist_ok=True)
    # TT2 has no puddle data: white means no artificial puddles, not a missing-texture checker.
    Image.new('RGBA', (4, 4), (255, 255, 255, 255)).save(puddles_mask)
    selected = {s: {} for s in metadata}
    # Local terrain textures are not in the global DDS tree, but still need
    # their detail association. Without it BmmD selects its non-detail fallback.
    local_assets = {'textures/' + t.replace('\\', '/') + '.dds' for t in textures
                    if (level / (t.replace('\\', '/') + '.dds')).is_file()}
    for asset in sorted(copied | local_assets):
        key = asset[len('textures/'):-4].replace('/', '\\')
        for section, records in metadata.items():
            if key not in records:
                continue
            selected[section][key] = records[key]
            if section == 'association':
                ensure_texture(records[key].split(',')[0].strip())
            else:
                bump = re.search(r'bump_mode\[use:([^\]]+)\]', records[key])
                if bump:
                    ensure_texture(bump.group(1))
                    ensure_texture(bump.group(1) + '#')
    for source_name, target_name in TEXTURE_OVERRIDES.items():
        source = donor / 'textures' / (source_name.replace('\\', '/') + '.dds')
        # Keep the original compressed DDS and all its alpha/mipmap data.
        with Image.open(source) as image:
            if 'A' not in image.getbands() or image.getchannel('A').getextrema() != (0, 255):
                raise ValueError('Fence replacement must contain transparent and opaque pixels')
        destination = stage / 'textures' / (target_name.replace('\\', '/') + '.dds')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied.add('textures/' + target_name.replace('\\', '/') + '.dds')
        for section, records in metadata.items():
            if source_name not in records:
                continue
            selected[section][target_name] = records[source_name]
            if section == 'association':
                ensure_texture(records[source_name].split(',')[0].strip())
    if failures:
        raise RuntimeError('Missing texture dependencies: ' + ', '.join(sorted(failures)))
    ltx = '\n'.join('[' + s + ']\n' + '\n'.join(k + ' = ' + v for k, v in records.items())
                    for s, records in selected.items()) + '\n'
    (stage / 'textures').mkdir(parents=True, exist_ok=True)
    (stage / 'textures' / 'zz_pravo_deadcity_textures.ltx').write_text(ltx, encoding='cp1251')
    # This is the previously corrected TT2 map, not the low-resolution MGCity texture.
    map_source = project / 'tools' / 'assets' / 'map_dead_city.dds'
    map_target = stage / 'textures' / 'map' / 'map_dead_city.dds'
    map_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(map_source, map_target)
    report = {'shaders': sorted(shaders), 'textures_checked': len(textures),
              'extra_textures': sorted(copied), 'level_source': str(level),
              'isolated_texture_overrides': TEXTURE_OVERRIDES}
    (project / 'build-deadcity' / 'assets.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'Dead City staged: {len(shaders)} compatible shaders, {len(textures)} textures checked, '
          f'{len(copied)} missing textures supplied; no AMK/TT2 scripts imported')


if __name__ == '__main__':
    main()
