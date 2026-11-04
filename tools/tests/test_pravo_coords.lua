-- Exercise the actual helper with engine API doubles, not a copy of its logic.
local now, pressed, hud_items, records, queries = 0, {}, {}, {}, 0
local console = {visible = false}
local dev = {cam_pos={x=10,y=20,z=30}, cam_dir={x=0,y=-0.6,z=0.8}, paused=false}
function dev:is_paused() return self.paused end
function device() return dev end
function time_global() return now end
function vector()
    return {set=function(self,x,y,z)
        if type(x)=='table' then self.x,self.y,self.z=x.x,x.y,x.z else self.x,self.y,self.z=x,y,z end
        return self
    end, getH=function() return 1.25 end}
end
db = {actor={position=function() error('Must not use actor position for free camera') end}}
DIK_keys={DIK_G=34,DIK_H=35}
rq_target={rqtStatic=1}
local has_hit=true
level={name=function() return 'l07_military' end,
    ray_query=function(pos,dir,range,target,ignore)
        queries=queries+1
        assert(pos.x==10 and range==500 and target==1 and ignore==db.actor)
        return {result=has_hit,range=5}
    end}
function key_state(k) return pressed[k] or 0 end
function get_console() return console end
function getFS() return {update_path=function(_,alias,name) assert(alias=='$app_data_root$');return name end} end
function printf(fmt,...) records[#records+1]=string.format(fmt,...) end
function log1(message) records[#records+1]=message end
local hud={GetCustomStatic=function(_,id) return hud_items[id] end,
    AddCustomStatic=function(_,id)
        local wnd={SetText=function(self,text) self.text=text end}
        hud_items[id]={wnd=function() return wnd end};return hud_items[id]
    end, RemoveCustomStatic=function(_,id) hud_items[id]=nil end}
function get_hud() return hud end
local saved={}
local open=io.open
io.open=function(path,mode)
    assert(path=='pravo_npc_points.txt' and mode=='ab')
    return {write=function(self,s) saved[#saved+1]=s; return self end,close=function() return true end}
end
pravo_coords={}
local module=assert(coords_source and loadstring(coords_source) or loadfile(arg[1]));setfenv(module,setmetatable(pravo_coords,{__index=_G}));module()
local function tick() now=now+100;pravo_coords.update() end
pravo_coords.reset();tick();assert(queries==0 and not hud_items.pravo_coords)
pressed[34]=128;tick();assert(hud_items.pravo_coords)
tick();assert(hud_items.pravo_coords,'Holding G must not toggle repeatedly')
pressed[34]=0;pressed[35]=128;tick();assert(#saved==1)
assert(saved[1]:find('position = 10.000, 17.000, 34.000',1,true))
assert(saved[1]:find('camera_position = 10.000, 20.000, 30.000',1,true))
assert(saved[1]:find('position_source = aim_static',1,true))
tick();assert(#saved==1,'Holding H must save once')
pressed[35]=0;tick();has_hit=false;pressed[35]=true;tick();assert(#saved==2)
assert(saved[2]:find('position_source = camera',1,true))
console.visible=true;pressed[35]=0;tick();pressed[35]=128;tick();assert(#saved==2)
console.visible=false;tick();assert(#saved==2,'Do not replay a console key')
pressed[35]=0;tick();io.open=function() return nil,'read only' end;pressed[35]=128;tick()
assert(records[#records]:find('File write failed',1,true),'File error must leave a log entry')
pressed[35]=0;pressed[34]=128;tick();assert(not hud_items.pravo_coords)
local before=queries;tick();assert(queries==before,'No ray queries while disabled')
pravo_coords.reset();assert(not hud_items.pravo_coords)
io.open=open
print('PASS: free camera, ground point, numeric/boolean keys, key edges, console guard, append file, write failure, disabled cost, cleanup')
