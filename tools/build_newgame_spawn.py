"""Author the new-game world in all.spawn; no in-game NPC migration loops."""
import argparse
import json
import math
from pathlib import Path
import re
import struct
import subprocess


def blocks(text):
    return re.findall(r'(?ms)^\[\d+\].*?(?=^\[\d+\]|\Z)', text)


def value(block, key):
    match = re.search(r'(?m)^' + re.escape(key) + r'\s*=\s*([^\r\n]*)', block)
    return match.group(1).strip() if match else ''


def set_value(block, key, data):
    pattern = r'(?m)^' + re.escape(key) + r'\s*=.*$'
    if re.search(pattern, block):
        return re.sub(pattern, lambda _: key + ' = ' + str(data), block)
    return block.rstrip() + '\n' + key + ' = ' + str(data) + '\n'


class LevelAI:
    def __init__(self, data):
        self.data = data
        self.version, self.count, self.cell, self.factor_y = struct.unpack_from('<IIff', data)
        if self.version not in (8, 9):
            raise ValueError(f'Unsupported AI format {self.version}; expected SoC')
        self.minimum = struct.unpack_from('<3f', data, 16)
        maximum = struct.unpack_from('<3f', data, 28)
        self.row = math.floor((maximum[2]-self.minimum[2])/self.cell + 1.5001)
        if len(data) != 56+self.count*21:
            raise ValueError('Unexpected SoC AI node size')

    def position(self, vertex):
        offset = 56+vertex*21+16
        xz = int.from_bytes(self.data[offset:offset+3], 'little')
        y, = struct.unpack_from('<H', self.data, offset+3)
        return (self.minimum[0]+(xz//self.row)*self.cell,
                self.minimum[1]+y/65535*self.factor_y,
                self.minimum[2]+(xz%self.row)*self.cell)

    def nearest(self, point):
        best, result = float('inf'), None
        for vertex in range(self.count):
            pos = self.position(vertex)
            distance = sum((a-b)**2 for a,b in zip(pos, point))
            if distance < best:
                best, result = distance, (vertex, pos)
        if best > 4:
            raise ValueError(f'No AI node within 2m of {point}: distance={math.sqrt(best)}')
        vertex, pos = result
        return vertex, (pos[0], pos[1]+0.05, pos[2])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', required=True)
    ap.add_argument('--sevenzip', default=str(Path(__file__).resolve().parents[2] / 'mod-tools' / '7zip-xdb' / '7z.exe'))
    args = ap.parse_args()
    root = Path(args.project)
    spawn = root/'spawn-clean'
    stage = root/'build-deadcity'/'newgame'
    stage.mkdir(parents=True, exist_ok=True)
    archives = {}
    for archive in sorted((root/'game').glob('gamedata.db*')):
        listing = subprocess.run([args.sevenzip,'l','-slt',str(archive)], check=True, capture_output=True)
        for line in listing.stdout.decode('utf-8', errors='replace').splitlines():
            if line.startswith('Path = '): archives[line[7:].lower()] = archive
    ai_cache = {}

    def ai(level):
        if level in ai_cache: return ai_cache[level]
        path = root/'game'/'gamedata'/'levels'/level/'level.ai'
        if not path.exists():
            name = f'levels\\{level}\\level.ai'
            target = stage/level
            target.mkdir(exist_ok=True)
            subprocess.run([args.sevenzip,'e',str(archives[name]),name,'-o'+str(target),'-y'],
                           check=True, capture_output=True)
            path = target/'level.ai'
        ai_cache[level] = LevelAI(path.read_bytes())
        return ai_cache[level]

    ids = {}
    next_spawn = 11000
    placements = {}

    def npc(name, profile, visual, level, position, gv, sid, cfg, condition='', health=1, yaw=0):
        nonlocal next_spawn
        lv, pos = ai(level).nearest(position)
        placements[name] = {'lv':lv,'gv':gv,'position':pos,'story_id':sid}
        ids[sid] = name
        custom = ('[spawner]\ncond = {'+condition+'}\n\n') if condition else ''
        custom += '[smart_terrains]\nnone = true\n[logic]\ncfg = '+cfg+'\n'
        text = f'''[{next_spawn}]
section_name = stalker
name = {name}
position = {','.join(map(str,pos))}
direction = 0,{yaw},0
id = 65535
version = 118
script_version = 6
spawn_id = {next_spawn}
money = 500
character_profile = {profile}
game_vertex_id = {gv}
level_vertex_id = {lv}
object_flags = 0xffffffff
story_id = {sid}
custom_data = <<END
{custom}END
visual_name = {visual}
g_team = 0
g_squad = 0
g_group = 0
health = {health}
dynamic_out_restrictions =
dynamic_in_restrictions =
equipment_preferences = 1,1,1,1,1
main_weapon_preferences = 1,1,1,1
upd:health = {health}
upd:timestamp = 0
upd:creature_flags = 0
upd:position = {','.join(map(str,pos))}
upd:o_torso = {yaw},0,0
upd:g_squad = 0
upd:start_dialog =
'''
        next_spawn += 1
        return text

    pri_path = spawn/'alife_l11_pripyat.ltx'
    pri = blocks(pri_path.read_text(encoding='cp1251'))
    # The kindergarten changes immediately on escaping, not after a Radar job.
    old_escape = 'on_actor_outside = sr_idle@thought_delay %+pravo_pri_escape_done%'
    new_escape = 'on_actor_outside = sr_idle@thought_delay %+pravo_pri_escape_done =pravo_pri_escape_aftermath%'
    escape_hooks = sum(b.count(old_escape) for b in pri)
    if escape_hooks != 1:
        raise ValueError('Expected exactly one authored escape completion trigger')
    pri = [b.replace(old_escape,new_escape) for b in pri]
    intro = [
        ('unknown','ilya_pri_unknown',r'actors\novice\green_stalker_4',(103.66,5.64,-9.85)),
        ('alexander','ilya_pri_alexander',r'actors\novice\green_stalker_2',(103.60,5.64,-13.03))]
    for i,(name,profile,visual,pos) in enumerate(intro):
        pri.append(npc('pravo_pri_intro_'+name,profile,visual,'l11_pripyat',pos,2231,6510+i,
                       'scripts\\'+profile+'.ltx','-pravo_pri_kindergarten_aftermath_done'))
        pri.append(npc('pravo_pri_dead_'+name,profile,visual,'l11_pripyat',pos,2231,6516+i,
                       'scripts\\'+profile+'.ltx','+pravo_pri_kindergarten_aftermath_done',health=0))
    duty = [
        ('leader','pravo_pri_duty_leader',(102.951889,-0.92949,-26.4901),213633,2234),
        ('1','pravo_pri_duty_1',(103.261482,-0.94036,-30.21914),214322,2234),
        ('2','pravo_pri_duty_2',(94.76617,-2.3414,-32.3258),205430,2144),
        ('3','pravo_pri_duty_3',(94.29622,-2.28476,-22.4324),205444,2144)]
    # Use the same validated visuals as the specific-character profiles.
    chars = (root/'story/gamedata/config/gameplay/character_desc_pravo.xml').read_text(encoding='cp1251')
    for i,(name,profile,pos,_,gv) in enumerate(duty):
        block = re.search(r'<specific_character id="'+profile+r'".*?</specific_character>',chars,re.S).group()
        visual = re.search(r'<visual>(.*?)</visual>',block).group(1)
        pri.append(npc('pravo_pri_duty_'+name,profile,visual,'l11_pripyat',pos,gv,6512+i,
                       r'scripts\pravo_pri_duty_wait.ltx',
                       '+pravo_pri_intro_done -pravo_pri_kindergarten_aftermath_done'))
    pri_path.write_text('\n\n'.join(b.rstrip() for b in pri)+'\n',encoding='cp1251',newline='\n')

    mil_path = spawn/'alife_l07_military.ltx'
    mil = blocks(mil_path.read_text(encoding='cp1251'))
    for i,b in enumerate(mil):
        if value(b,'story_id') != '728': continue
        lv,pos = ai('l07_military').nearest((-78.4,-11.32,38.5))
        pos_text=','.join(map(str,pos))
        for key,data in [('position',pos_text),('upd:position',pos_text),('level_vertex_id',lv),
                         ('game_vertex_id',1595),('direction','0,0,0'),('upd:o_torso','0,0,0')]:
            b=set_value(b,key,data)
        b=re.sub(r'(?ms)^custom_data\s*=\s*<<END\n.*?^END[^\S\n]*',
                 lambda _:'custom_data = <<END\n[smart_terrains]\nnone = true\n[logic]\ncfg = scripts\\pravo_mil_bar_cook.ltx\nEND',b)
        mil[i]=b
        placements['mil_cook']={'lv':lv,'gv':1595,'position':pos,'story_id':728}
    for i,(name,profile,visual,pos,yaw) in enumerate([
        ('freedom_1','pravo_mil_bar_freedom_1',r'actors\svoboda\stalker_sv_rukzak_1_1',(-74.5,-11.35,18.5),1.57),
        ('freedom_2','pravo_mil_bar_freedom_2',r'actors\svoboda\stalker_sv_hood_9',(-75.5,-11.35,29.5),3.14),
        ('traitor','pravo_mil_bar_traitor',r'actors\neytral\stalker_neytral_balon_1',(-79.,-11.35,21.),-1.57)]):
        mil.append(npc('pravo_mil_bar_'+name,profile,visual,'l07_military',pos,1595,6518+i,
                       r'scripts\pravo_mil_bar_visitor.ltx',
                       condition='-pravo_mil_gift_ambush_spawned' if name == 'traitor' else '', yaw=yaw))
    mil_path.write_text('\n\n'.join(b.rstrip() for b in mil)+'\n',encoding='cp1251',newline='\n')

    rad_path=spawn/'alife_l10_radar.ltx'
    rad=blocks(rad_path.read_text(encoding='cp1251'))
    result=[]
    for b in rad:
        if value(b,'name')=='zone_flame_small_0010': continue # duplicate campfire damage zone
        if value(b,'name')=='rad_zone_flame_small_0000':
            b=set_value(b,'section_name','pravo_rad_safe_campfire')
            b=set_value(b,'max_power',0)
        if value(b,'name')=='pravo_rad_freedom_camper_1':
            lv,pos=ai('l10_radar').nearest((59.7,-4.2,-44.7))
            for key,data in [('position',','.join(map(str,pos))),('upd:position',','.join(map(str,pos))),('level_vertex_id',lv)]:
                b=set_value(b,key,data)
        if value(b,'name')=='pravo_rad_freedom_trader':
            b=set_value(b,'story_id',6521)
            ids[6521]='pravo_rad_freedom_trader'
        result.append(b)
    rad_path.write_text('\n\n'.join(b.rstrip() for b in result)+'\n',encoding='cp1251',newline='\n')

    sid_path=root/'story/gamedata/config/game_story_ids.ltx'
    sids=sid_path.read_text(encoding='cp1251')
    for sid,name in sorted(ids.items()):
        if re.search(r'(?m)^\s*'+str(sid)+r'\s*=',sids):
            sids=re.sub(r'(?m)^\s*'+str(sid)+r'\s*=.*$',str(sid)+' = "'+name+'"',sids)
        else: sids+='\n'+str(sid)+' = "'+name+'"\n'
    sid_path.write_text(sids,encoding='cp1251',newline='\n')
    (stage/'placements.json').write_text(json.dumps(placements,indent=2),encoding='utf-8')
    print('New-game spawn: 2 intro NPCs, 4 conditional Duty, 2 conditional corpses, 3 bar visitors; kitchen cook; safe campfire')


if __name__=='__main__':
    main()
