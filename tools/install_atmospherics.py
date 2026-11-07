"""Install the official weather assets, retaining overwritten files for recovery."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
from datetime import datetime

from build_atmospherics import configure


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--cache', type=Path)
    args = ap.parse_args()
    root = args.project.resolve()
    cache = args.cache or root.parent/'mod-tools/atmospherics'
    cache.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((root/'tools/assets/atmospherics/source.json').read_text(encoding='utf-8'))
    sevenzip = root.parent/'mod-tools/7zip-xdb/7z.exe'
    if subprocess.run(['tasklist', '/FI', 'IMAGENAME eq xrEngine.exe', '/NH'], capture_output=True).stdout.lower().find(b'xrengine.exe') >= 0:
        raise RuntimeError('Close the game before installing Atmospherics')
    for source in metadata['archives']:
        archive = cache/source['filename']
        if not archive.exists():
            print('Downloading '+source['filename'], flush=True)
            partial = archive.with_suffix('.partial')
            with urllib.request.urlopen(source['download_url'], timeout=60) as response, partial.open('wb') as output:
                if 'text/html' in response.headers.get('Content-Type', ''):
                    raise RuntimeError('Download returned a web page instead of the official archive')
                shutil.copyfileobj(response, output, 4*1024*1024)
            if sha(partial) != source['sha256']:
                raise RuntimeError('Archive hash differs from the pinned official release')
            partial.replace(archive)
        if sha(archive) != source['sha256']:
            raise RuntimeError('Archive checksum mismatch: '+str(archive))
        extracted = cache/source['extract_to']
        marker = extracted/'.archive-sha256'
        if not marker.exists() or marker.read_text().strip() != source['sha256']:
            subprocess.run([str(sevenzip), 'x', str(archive), '-o'+str(extracted), '-y'], check=True)
            marker.write_text(source['sha256'])

    backup = root/'game/_backups'/('atmospherics-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
    backup.mkdir(parents=True)
    manifest = {'version': metadata['version'], 'files': []}
    def preserve(target):
        relative = target.relative_to(root).as_posix()
        if any(entry['path'] == relative for entry in manifest['files']): return
        entry = {'path': relative, 'existed': target.exists()}
        if target.exists():
            destination = backup/relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, destination)
            entry['before_sha256'] = sha(target)
        manifest['files'].append(entry)
    def install(source, target):
        preserve(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # Only common media comes from CoP; all environment configuration is ShOC.
    base = cache/'base/gamedata'
    for folder in ('sounds', 'textures'):
        for source in (base/folder).rglob('*'):
            if source.is_file(): install(source, root/'game/gamedata'/source.relative_to(base))
    story = root/'story/gamedata'
    for relative in ('config/game_maps_single.ltx',): preserve(story/relative)
    preserve(root/'game/fsgame.ltx')
    configure(root, configure_fs=True)
    for source in (root/'tools/assets/atmospherics/gamedata').rglob('*'):
        if source.is_file(): install(story/source.relative_to(root/'tools/assets/atmospherics/gamedata'), root/'game/gamedata'/source.relative_to(root/'tools/assets/atmospherics/gamedata'))
    for relative in ('config/pravo_atmospherics.ltx', 'config/game_maps_single.ltx', 'scripts/level_weathers.script'):
        install(story/relative, root/'game/gamedata'/relative)
    # Apply the author's lighting calibration, preserving resolution, controls,
    # texture quality, shadow resolution, vegetation distance and upscaler choice.
    user_path = root/'game/_appdata_/user_ogsr.ltx'
    preserve(user_path)
    user = user_path.read_text(encoding='utf-8-sig')
    preset = (root/'tools/assets/atmospherics/gamedata/config/rspec_atmospherics.ltx').read_text()
    for line in preset.splitlines():
        if not line or line.startswith(';'): continue
        key = line.split()[0]
        pattern = r'(?m)^'+re.escape(key)+r'[ \t]+[^\r\n]*'
        if re.search(pattern, user, re.I): user = re.sub(pattern, lambda _: line, user, flags=re.I)
        else: user += '\n'+line+'\n'
    user_path.write_text(user, encoding='utf-8', newline='\n')
    for entry in manifest['files']:
        entry['after_sha256'] = sha(root/entry['path'])
    (backup/'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    (root/'game/gamedata/config/pravo_atmospherics_install.json').write_text(json.dumps({
        'version': metadata['version'], 'backup': str(backup),
        'media_files': sum(entry['path'].startswith(('game/gamedata/textures/', 'game/gamedata/sounds/')) for entry in manifest['files'])
    }, indent=2), encoding='utf-8')
    print('Installed '+metadata['version']+'; backup: '+str(backup), flush=True)


if __name__ == '__main__': main()
