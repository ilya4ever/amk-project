"""Copy missing texture dependencies of an SDK-built level, never its spawn/AI."""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess

from stage_dead_city_assets import chunks, strings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument('--sdk', default=str(Path(__file__).resolve().parents[2] / 'ogsr-sdk'))
    ap.add_argument('--donor', default=str(Path(__file__).resolve().parents[2] / 'unpackedtt2'))
    ap.add_argument('--level', default='l07_military')
    ap.add_argument('--sevenzip', default=str(Path(__file__).resolve().parents[2] / 'mod-tools' / '7zip-xdb' / '7z.exe'))
    ap.add_argument('--output-root', type=Path, help='Stage texture dependencies in this gamedata folder')
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()
    project, sdk, donor = Path(args.project), Path(args.sdk), Path(args.donor)
    game = project / 'game'
    level = sdk / 'gamedata' / 'levels' / args.level
    shader_data = dict(chunks((level / 'level').read_bytes()))[2]
    count, = struct.unpack_from('<I', shader_data)
    referenced = set()
    for definition in strings(shader_data[4:], count):
        if '/' in definition:
            referenced.update(t.strip().replace('\\', '/').lower()
                              for t in definition.partition('/')[2].split(',') if t.strip())
    available = set()
    for archive in sorted(game.glob('gamedata.db*')):
        result = subprocess.run([args.sevenzip, 'l', '-slt', str(archive)],
                                check=True, capture_output=True)
        for line in result.stdout.decode('utf-8', errors='replace').splitlines():
            if line.startswith('Path = textures\\'):
                available.add(line[7:].replace('\\', '/').lower())
    for texture in (game / 'gamedata' / 'textures').rglob('*.dds'):
        available.add(texture.relative_to(game / 'gamedata').as_posix().lower())
    roots = [sdk / 'rawdata' / 'textures', sdk / 'gamedata' / 'textures', donor / 'textures']
    planned, unresolved = {}, []
    for name in sorted(referenced):
        if name.startswith('$') or (level / (name + '.dds')).is_file():
            continue
        if 'textures/' + name + '.dds' in available:
            continue
        source = next((root / (name + '.dds') for root in roots
                       if (root / (name + '.dds')).is_file()), None)
        if source is None:
            unresolved.append(name)
            continue
        # Main texture, settings and conventional relief maps. Prefer the SDK's
        # version; TT2 is only a fallback for missing files of the same family.
        for suffix in ('', '_bump', '_bump#'):
            for extension in ('.dds', '.thm'):
                relative = name + suffix + extension
                candidate = next((root / relative for root in roots
                                  if (root / relative).is_file()), None)
                if candidate is not None:
                    planned[relative] = candidate
    if unresolved:
        print('Unresolved texture names: ' + ', '.join(unresolved))
        raise SystemExit(1)
    for relative, source in sorted(planned.items()):
        print(('Install: ' if args.apply else 'Missing: ') + relative)
        if not args.apply:
            continue
        for data_root in ([args.output_root] if args.output_root else (project / 'story' / 'gamedata', game / 'gamedata')):
            destination = data_root / 'textures' / relative
            if not destination.resolve().is_relative_to((data_root / 'textures').resolve()):
                raise ValueError('Texture path escapes target root')
            # Do not overwrite unrelated retextures or already installed files.
            if not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
    print(f'{len(planned)} texture/settings files; '
          + ((f'installed in {args.output_root}' if args.output_root else 'installed in story and game') if args.apply else 'preview only'))


if __name__ == '__main__':
    main()
