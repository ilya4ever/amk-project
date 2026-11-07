local env = {}
setmetatable(env, {__index = _G})
env.class = function(name)
    local cls = {}; cls.__index = cls
    setmetatable(cls, {__call = function(_, ...)
        local instance = setmetatable({}, cls); instance:__init(...); return instance
    end})
    env[name] = cls
end
local map, day, hour, minute = "l07_military", 0, 12, 58
local current, calls = nil, 0
local cycles = {w_clear1=true, w_rain1=true, indoor=true}
local cycle_ini = {line_exist=function(_, section, name) return cycles[name] == true end}
local graph = {
    section_exist=function(_, name) return name=="dynamic_default" end,
    line_count=function() return 2 end,
    r_line=function(_, _, index) return true, index==0 and "w_clear1" or "w_rain1", "1" end
}
env.ini_file = function(name)
    if name=="pravo_atmospherics.ltx" then return cycle_ini end
    if name=="environment\\dynamic_weather_graphs.ltx" then return graph end
    return {}
end
env.db = {actor={}}
env.utils = {cfg_get_string=function() return map=="l03u_agr_underground" and "indoor" or "dynamic_default" end}
env.xr_logic = {parse_condlist=function(_, _, _, value) return value end, pick_section_from_condlist=function(_, _, value) return value end}
env.level = {
    name=function() return map end,
    set_weather=function(name) assert(cycles[name]); current=name; calls=calls+1 end,
    get_time_days=function() return day end, get_time_hours=function() return hour end,
    get_time_minutes=function() return minute end
}
env.math = {random=function() return .1 end}
setfenv(assert(loadstring(module_source)),env)()
local function reader(fields)
    return {index=1, fields=fields,
        r_stringZ=function(self) local value=self.fields[self.index];self.index=self.index+1;assert(type(value)=="string");return value end,
        r_u32=function(self) local value=self.fields[self.index];self.index=self.index+1;assert(type(value)=="number");return value end}
end
local manager=env.WeatherManager()
local legacy=reader({"l07_military",123456,"quest payload"})
manager:load(legacy)
assert(legacy:r_stringZ()=="quest payload", "Legacy save reader consumed quest data")
manager:reset()
assert(current=="w_clear1", "Legacy save did not switch to Atmospherics")
local before=calls
manager:update();assert(calls==before)
minute=59;manager:update();assert(calls==before+1)
manager:update();assert(calls==before+1,"Requested weather twice in the same hour")
local fields={}
manager:save({w_stringZ=function(_,v) fields[#fields+1]=v end,w_u32=function(_,v) fields[#fields+1]=v end})
assert(#fields==2 and type(fields[1])=="string" and type(fields[2])=="number", "Weather save layout changed")
fields[3]="quest payload"
local restored=env.WeatherManager()
local stream=reader(fields);restored:load(stream)
assert(stream:r_stringZ()=="quest payload")
restored:reset();before=calls
restored:update();assert(calls==before,"Reload at minute 59 repeated the hourly request")
hour=13;restored:update();assert(calls==before+1)
map="l03u_agr_underground";restored:update();assert(current=="indoor", "Underground received outdoor weather")
map="dead_city";restored:update();assert(current=="w_clear1", "Dead City did not receive dynamic weather")
print("PASS: legacy save alignment, weather persistence, hourly transitions and indoor/outdoor maps")
