local _,A=...
if A.blocked then return end
local L={};A.LoadConditions=L
L.classes={WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,DEATHKNIGHT=true,MONK=true,DEMONHUNTER=true,EVOKER=true}
L.instances={none=true,party=true,raid=true,pvp=true,arena=true,scenario=true}
local function readable(v)return not (issecretvalue and issecretvalue(v))end
local function integer(v)return readable(v) and type(v)=='number' and v==math.floor(v) and v>0 and v<=2147483647 end
function L.Validate(value)
    if value==nil then return true end
    assert(type(value)=='table','Load conditions must be a table')
    for k,v in pairs(value)do
        assert(k=='class' or k=='mapID' or k=='instance' or k=='instanceID','Unknown load condition')
        if k=='class'then assert(type(v)=='string' and L.classes[v],'Choose a supported player class')
        elseif k=='instance'then assert(type(v)=='string' and L.instances[v],'Choose a supported instance type')
        else assert(integer(v),'Map and instance IDs must be positive integers')end
    end
    return true
end
function L.Context(api)
    api=api or _G;local c={}
    if type(api.UnitClass)=='function'then local ok,_,token=pcall(api.UnitClass,'player');if ok and readable(token) and type(token)=='string'then c.class=token end end
    if api.C_Map and type(api.C_Map.GetBestMapForUnit)=='function'then local ok,id=pcall(api.C_Map.GetBestMapForUnit,'player');if ok and integer(id)then c.mapID=id end end
    if type(api.GetInstanceInfo)=='function'then
        local ok,_,kind,_,_,_,_,_,id=pcall(api.GetInstanceInfo)
        if ok and readable(kind) and type(kind)=='string' and L.instances[kind]then c.instance=kind end
        if ok and integer(id)then c.instanceID=id end
    end
    return c
end
function L.Matches(value,context)
    local valid=pcall(L.Validate,value);if not valid then return false,'Invalid load conditions' end
    for _,key in ipairs({'class','mapID','instance','instanceID'})do
        local want=value and value[key]
        if want~=nil then
            local actual=context[key]
            if actual==nil then return false,'Waiting for '..key end
            if actual~=want then return false,'Requires '..key..': '..tostring(want)end
        end
    end
    return true
end
