"""Apply weather configuration without replacing story maps or the actor binder."""
import argparse
from pathlib import Path
import re
import shutil


def configure(root, configure_fs=False):
    source = root/'tools/assets/atmospherics/gamedata'
    story = root/'story/gamedata'
    if not source.exists():
        raise FileNotFoundError('Atmospherics source configurations are missing')
    shutil.copytree(source, story, dirs_exist_ok=True)
    maps_path = story/'config/game_maps_single.ltx'
    maps = maps_path.read_text(encoding='cp1251')
    underground = {'l03u_agr_underground', 'l04u_labx18', 'l08u_brainlab',
                   'l10u_bunker', 'l12u_sarcofag', 'l12u_control_monolith'}
    def section(match):
        name, body = match.group(1), match.group(2)
        weather = 'indoor' if name.lower() in underground else 'dynamic_default'
        # Only replace active weather lines; map bounds, music and IDs stay put.
        body = re.sub(r'(?m)^([ \t]*weathers[ \t]*=)[^\r\n]*', r'\g<1> '+weather, body)
        return '['+name+']'+body
    maps = re.sub(r'(?ms)^\[([^\]]+)\](.*?)(?=^\[|\Z)', section, maps)
    maps_path.write_text(maps, encoding='cp1251', newline='\n')
    cycles = sorted(p.stem for p in (story/'config/environment/weathers').glob('*.ltx'))
    (story/'config/pravo_atmospherics.ltx').write_text(
        '; Atmospherics 2.69 RC7.1 OGSR Edition, ShOC adapter.\n[cycles]\n'+
        ''.join(name+' = true\n' for name in cycles), encoding='ascii', newline='\n')
    if configure_fs: configure_filesystem(root)
    print(f'Atmospherics configured: {len(cycles)} weather cycles; dynamic outdoor weather, indoor underground')


def configure_filesystem(root):
    fs_path = root/'game/fsgame.ltx'
    fs = fs_path.read_text(encoding='utf-8-sig')
    for alias, folder in [('game_weathers', 'weathers'), ('game_weather_effects', 'weather_effects')]:
        line = f'${alias}$ = true| false| $game_config$| environment\\{folder}\\'
        pattern = r'(?m)^\$'+alias+r'\$[^\r\n]*'
        if re.search(pattern, fs): fs = re.sub(pattern, lambda _: line, fs)
        else: fs += '\n'+line+'\n'
    fs_path.write_text(fs, encoding='utf-8', newline='\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    configure(parser.parse_args().project)
