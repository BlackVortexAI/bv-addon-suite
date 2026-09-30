-- Distance to one unit. No API returns yards for arbitrary units, so the
-- result is exact only for group members in the open world and otherwise a
-- bracket from range checks (like LibRangeCheck, without embedding it).
-- Unknown or protected results never mean "out of range".
local _,A=...
if A.blocked then return end
local G=A.G
local Range={interval=.25,maxChecks=24};A.RangeCheck=Range
-- Checker data from LibRangeCheck-3.0 (037851f8), Era branch: yards -> item
-- IDs with a known use range. Only one cached item per range is used.
-- See docs/research/2026-09-26-unit-range-sources.md ("Checker data").
Range.friendItems={
    [5]={1970,8149,15826,16308,16991,17117,20403,22259,208855,209027,209057,213036,221199,225943},
    [10]={17626,17689,21267,23164,226207,226208,226209,226210,226211,226212,226213,226214},
    [15]={1251,2581,3530,3531,6450,6451,8544,8545,14529,14530,19066,19067,19068,19307,20065,20066,20067,20232,20234,20235,20237,20243,20244,23684,232433},
    [20]={12450,12451,12455,12457,12458,12460,17757,21519,219963,219965,219983,219984,219985,219986,219987,219988,219989,219990,219991,219992,219993,219994,219995,219996,219997,219998,220053,220054,220055,220056,220057,220058,220059,220060,220061,220062,220063,220064,220065,220066,220067,220068,220069,220070,220071,220072,220073,220074,220075,220076,220077,220078,220079,220080,220081,220082,220083,220084,220085,220086,220087,220088,220089,220090,220091,220092,220093,220094,220095,220096,220097,220098,220099,220100,220101,220102,220103,220104,220105,220106,220792,223168,223171,224806,224893,231298,231836,232344},
    [25]={13289},
    [30]={954,955,1180,1181,1477,1478,1711,1712,1851,1912,2289,2290,2948,3012,3013,4381,4419,4421,4422,4424,4425,4426,4444,5232,5613,6452,6453,10305,10306,10307,10308,10309,10310,11563,11564,11567,16892,16893,16895,16896,17202,17310,18637,19440,20908,21038,21713,22200,22206,22218},
    [35]={18904},
    [40]={1713,5205,5323,8346,11562,18640,18662,213349,216500,216503,216517,216607,230280},
    [45]={221316},
    [50]={221315},
    [100]={5418,17162,23715,23718,23719,23721,23722,227685},
}
Range.harmItems={
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
-- CheckInteractDistance index -> yards (LRC default; Tauren/Undead differ).
Range.interact={[3]=8,[4]=28}
Range.raceInteract={Tauren={[3]=6,[4]=25},Scourge={[3]=7,[4]=27}}
local function secret(v) return G.IsSecret(v) end
-- pcall wrapper: value(s), or nil plus "missing" / "error" / "protected".
local function call(fn,...)
    if type(fn)~="function" then return nil,"missing" end
    local ok,a,b=pcall(fn,...)
    if not ok then return nil,"error" end
    if secret(a) or secret(b) then return nil,"protected" end
    return a,b
end
Range.call=call
-- One cached item per range, re-chosen at most every 5 s when none is cached yet.
Range.chosen={}
local function pick(list,yards)
    local key=tostring(list)..":"..yards;local c=Range.chosen[key];local now=GetTime()
    if c and (c.item or now-c.at<5) then return c.item end
    local item
    local cached=C_Item and C_Item.IsItemDataCachedByID
    for _,id in ipairs(list[yards]) do
        local ok,v=pcall(cached or GetItemInfo,id)
        if ok and v and not G.IsSecret(v) then item=id;break end
    end
    Range.chosen[key]={item=item,at=now};return item
end
local function itemCheck(item,unit)
    local api=C_Item and C_Item.IsItemInRange or IsItemInRange
    local v,why=call(api,item,unit)
    if v==true or v==false then return v end
    return nil,why
end
local function interactCheck(index,unit)
    local v,why=call(CheckInteractDistance,unit,index)
    if v==true or v==false then return v end
    if v==1 then return true end
    if v==0 then return false end
    return nil,why
end
local function spellCheck(spell,unit)
    local api=C_Spell and C_Spell.IsSpellInRange
    local v,why=call(api,spell,unit)
    if v==true or v==false then return v end
    return nil,why
end
Range.SpellInRange=spellCheck
-- Spell ranges in yards from spell info, or nil.
local function spellRange(spell)
    local info=call(C_Spell and C_Spell.GetSpellInfo,spell)
    if type(info)~="table" then return end
    local max,min=info.maxRange,info.minRange
    if secret(max) or secret(min) or not G.Number(max) or max<0 then return end
    return math.floor(max+.5),G.Number(min) and math.floor(min+.5) or 0
end
-- Returns {min,max,inSpell,status}; min/max in yards (nil when unbounded or unknown).
function Range.Measure(unit,spellID)
    local out={status="unknown"}
    local exists,why=call(UnitExists,unit)
    if why=="protected" then out.status="protected";return out end
    if exists~=true then return out end
    if unit=="player" then out.min,out.max,out.status=0,0,"exact";return out end
    if G.Number(spellID) and spellID>0 then out.inSpell=spellCheck(spellID,unit) end
    local d2,checked=call(UnitDistanceSquared,unit)
    if G.Number(d2) and d2>=0 and checked==true then
        local yards=math.sqrt(d2);out.min,out.max,out.status=yards,yards,"exact";return out
    end
    -- Item and interact checks are blocked in combat for units you cannot attack.
    local canAttack=call(UnitCanAttack,"player",unit)
    local allowItems=not InCombatLockdown() or canAttack==true
    local checks={}
    if allowItems then
        local list=canAttack==true and Range.harmItems or Range.friendItems
        for yards in pairs(list) do
            local item=pick(list,yards)
            if item then checks[#checks+1]={yards=yards,run=function() return itemCheck(item,unit) end} end
        end
        local _,race=call(UnitRace,"player")
        for index,yards in pairs(Range.raceInteract[race] or Range.interact) do checks[#checks+1]={yards=yards,run=function() return interactCheck(index,unit) end} end
    end
    local max,min=spellRange(spellID)
    if max and max<=0 then max=2 end -- melee spells, like LibRangeCheck
    if max and min==0 then checks[#checks+1]={yards=max,run=function() return out.inSpell end} end
    table.sort(checks,function(a,b) return a.yards<b.yards end)
    local readable,protected=false,false
    for i=1,math.min(#checks,Range.maxChecks) do
        local c=checks[i];local v,reason=c.run()
        if v==true then readable=true;out.max=c.yards;break
        elseif v==false then readable=true;out.min=c.yards
        elseif reason=="protected" then protected=true end
    end
    if readable then out.status="estimated";out.min=out.min or 0
    elseif protected then out.status="protected" end
    return out
end
