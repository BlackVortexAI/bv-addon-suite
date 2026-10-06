local _,L=...
if not L.ready then return end
-- Distance band to an enemy (0.7.3), for the flight time of a spell: no API
-- gives yards for an enemy, so the band comes from range checks: item use
-- ranges against attackable units (allowed in combat), CheckInteractDistance
-- and the cast spell's own range. Checker data from LibRangeCheck-3.0
-- (037851f8, Era branch), the same as AuraStudio's RangeCheck.lua
-- (docs/research/2026-09-26-unit-range-sources.md). Unknown or protected
-- answers leave the band open; nothing here means "out of range".
local R={MAX_CHECKS=16}
L.Range=R
R.HARM={
    [5]={8149,15826,16308,17117,22259,22432,206466,208760,208855,209027,209057,213036,221199,225943},
    [10]={9606,9618,9619,9620,9621,10699,17626,17689,226472},
    [15]={4559},
    [20]={1191,2012,4388,10645,13892,17757,18209,22048,202251,227936,232344},
    [25]={13289},
    [30]={835,1404,1434,1444,1472,1704,1854,1914,1995,2091,3434,3441,4479,4480,4481,4941,5079,5457,6436,7344,7734,9328,9394,10588,10716,10720,11170,11522,11565,12288,12646,12647,13213,13509,13514,17202,17310,20084,20908,21038,21713,22200,22206,22218,220649,228576,233226},
    [35]={1258,1399,1402,8688,18904,220568,233216},
    [40]={4945,8348,191414,208773,208843,209047},
    [45]={221316},
    [100]={5418,17162,23715,23718,23719,23721,23722,227685},
}

-- CheckInteractDistance index -> yards (Tauren and Undead differ).
R.INTERACT={[3]=8,[4]=28}
R.RACE={Tauren={[3]=6,[4]=25},Scourge={[3]=7,[4]=27}}

local function call(f,...)
    if type(f)~="function" then return nil,"missing" end
    local ok,a,b=pcall(f,...)
    if not ok then return nil,"error" end
    if L.Secret(a) or L.Secret(b) then return nil,"protected" end
    return a,b
end
R.call=call
-- One cached item per range (re-chosen at most every 5 s while none is cached).
R.chosen={}
local function pick(yards)
    local c=R.chosen[yards]
    local now=GetTime()
    if c and (c.item or now-c.at<5) then return c.item end
    local item
    local cached=C_Item and C_Item.IsItemDataCachedByID or GetItemInfo
    for _,id in ipairs(R.HARM[yards]) do
        local ok,v=pcall(cached,id)
        if ok and v and not L.Secret(v) then item=id;break end
    end
    R.chosen[yards]={item=item,at=now}
    return item
end
-- The checks between the interact distances (10, 15, 20, ... yards) need
-- their items in the client's cache; asked for once as the module starts
-- (flight probe 2026-10-07: only 0-7, 7-20, 20-27 yards without them).
function R:Preload()
    if self.preloaded then return end
    self.preloaded=true
    local request=C_Item and C_Item.RequestLoadItemDataByID
    if type(request)~="function" then return end
    for _,list in pairs(self.HARM) do
        for _,id in ipairs(list) do pcall(request,id) end
    end
    -- Choose again once the data is there (pick retries an empty choice after 5 s).
    self.chosen={}
end
local function yes(v) if v==true or v==1 then return true end;if v==false or v==0 then return false end end
local function spellRange(spellID)
    local info=call(C_Spell and C_Spell.GetSpellInfo,spellID)
    if type(info)~="table" then return nil end
    local max,min=info.maxRange,info.minRange
    if type(max)~="number" or L.Secret(max) or max<=0 then return nil end
    if type(min)=="number" and not L.Secret(min) and min>0 then return nil end
    return math.floor(max+.5)
end
-- Band {min, max, status} in yards to unit: status "estimated" (min/max set,
-- max nil when beyond every check), "protected" or "unknown".
function R:Band(unit,spellID)
    local out={status="unknown"}
    if call(UnitExists,unit)~=true then return out end
    local checks={}
    for yards in pairs(self.HARM) do
        local item=pick(yards)
        if item then checks[#checks+1]={yards=yards,run=function() return call(C_Item and C_Item.IsItemInRange or IsItemInRange,item,unit) end} end
    end
    local _,race=call(UnitRace,"player")
    for index,yards in pairs(self.RACE[race] or self.INTERACT) do
        checks[#checks+1]={yards=yards,run=function() return call(CheckInteractDistance,unit,index) end}
    end
    local max=type(spellID)=="number" and spellRange(spellID)
    if max then checks[#checks+1]={yards=max,run=function() return call(C_Spell and C_Spell.IsSpellInRange,spellID,unit) end} end
    table.sort(checks,function(a,b) return a.yards<b.yards end)
    local readable,protected=false,false
    for i=1,math.min(#checks,self.MAX_CHECKS) do
        local c=checks[i]
        local v,why=c.run()
        local inside=yes(v)
        if inside==true then readable=true;out.max=c.yards;break
        elseif inside==false then readable=true;out.min=c.yards
        elseif why=="protected" then protected=true end
    end
    if readable then out.status="estimated";out.min=out.min or 0
    elseif protected then out.status="protected" end
    return out
end
