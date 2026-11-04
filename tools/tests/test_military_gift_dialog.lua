-- Reproduce OGSR's game_object equality failure without opening a game window.
local module = {}
local shared_meta = {__eq = function() error("game_object has no __eq") end}
local function object(profile)
    return setmetatable({profile_name = function() return profile end}, shared_meta)
end
local actor, traitor, other = object("actor"), object("pravo_mil_bar_traitor"), object("pravo_mil_bar_freedom_1")
local has_attic = true
module.db = {actor = actor}
module.alife = function() return {story_object = function(_, id)
    assert(id == 6530)
    return has_attic and {} or nil
end} end
setmetatable(module, {__index = _G})
setfenv(assert(loadstring(module_source)), module)()
assert(module.is_traitor(actor, traitor))
assert(module.is_traitor(traitor, actor)) -- The real dialogue manager's order.
assert(module.is_traitor(traitor, nil))
assert(module.is_traitor(nil, traitor))
assert(not module.is_traitor(other, actor))
assert(not module.is_traitor(actor, other))
assert(not module.is_traitor(nil, nil))
has_attic = false
assert(not module.is_traitor(traitor, actor))
print("PASS: dialogue precondition supports both speaker orders without object equality")
