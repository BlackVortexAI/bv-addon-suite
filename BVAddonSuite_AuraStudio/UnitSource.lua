-- One bounded unit snapshot. Opaque client scalars are immediately captured
-- by Core's private runtime handle store; saved/trace paths never receive them.
local _,A=...
if A.blocked then return end
local G=A.G
local P={};A.UnitSource=P
P.presentationFields={classIcon=true,classColor=true,classRed=true,classGreen=true,classBlue=true,roleIcon=true}
-- Player-only observations reuse the existing progress/economy adapter. Their
-- names cannot collide with ordinary UnitData fields such as level or power.
P.playerFields={
    moneyCopper={kind="player_money",field="copper",type="integer",reason="money"},
    xpCurrent={kind="player_xp",field="current",type="integer",reason="xp"},
    xpMaximum={kind="player_xp",field="maximum",type="integer",reason="xp"},
    xpRested={kind="player_xp",field="rested",type="integer",reason="xp"},
    xpLevel={kind="player_xp",field="level",type="integer",reason="xp"},
    xpDisabled={kind="player_xp",field="disabled",type="boolean",reason="xp"},
    xpCapped={kind="player_xp",field="capped",type="boolean",reason="xp"},
}
P.playerFieldOrder={"moneyCopper","xpCurrent","xpMaximum","xpRested","xpLevel","xpDisabled","xpCapped"}
P.fields={"health","healthMax","healthPercent","power","powerMax","powerType","powerToken",
    "mounted","resting","moving","combat","mana","manaMax","rage","rageMax","energy","energyMax",
    "focus","focusMax","comboPoints","comboPointsMax","runicPower","runicPowerMax"}
local resources={mana="Mana",rage="Rage",energy="Energy",focus="Focus",comboPoints="ComboPoints",runicPower="RunicPower"}
local fixed={player="player",target="target",focus="focus",target_target="targettarget",focus_target="focustarget",pet="pet",mouseover="mouseover"}
local function protected(value,api)
    local ok,hidden=pcall(G.IsSecret,value);if not ok or hidden then return true end
    if api and api.issecretvalue then ok,hidden=pcall(api.issecretvalue,value);if not ok or hidden then return true end end
    return false
end
function P.ValidToken(unit)
    if protected(unit) or type(unit)~="string" then return false end
    for _,token in pairs(fixed) do if unit==token then return true end end
    local party=unit:match("^party([1-4])$");if party then return true end
    local plate=unit:match("^nameplate(%d+)$");if plate then return tonumber(plate)>=1 and tonumber(plate)<=40 and tostring(tonumber(plate))==plate end
    local raid=unit:match("^raid(%d+)$");return raid~=nil and tonumber(raid)>=1 and tonumber(raid)<=40 and tostring(tonumber(raid))==raid
end
function P.Token(kind,config,instance)
    if protected(kind) or type(kind)~="string" then return end
    if kind=="group_units" or kind=="group_aura" or kind=="group_cast" then
        local group=config and config.kind
        if protected(group) or (group~="party" and group~="raid") then return end
        local ok,binding=pcall(G.Object,instance,"unitref");if not ok then return end
        if binding and P.ValidToken(binding.unit) and binding.unit:match("^"..group.."%d+$") then return binding.unit end
        return
    end
    if kind=="nameplates" or kind=="nameplates_aura" or kind=="nameplates_cast" then
        local ok,binding=pcall(G.Object,instance,"unitref");if not ok then return end
        if binding and P.ValidToken(binding.unit) and binding.unit:match("^nameplate%d+$") then return binding.unit end
        return
    end
    if kind=="unit" or kind=="unit_aura" or kind=="unit_cast" then kind=config and config.unit or "player" end
    if protected(kind) or type(kind)~="string" then return end
    if fixed[kind] then return fixed[kind] end
    local limit=kind=="party_member" and 4 or (kind=="raid_member" or kind=="nameplate") and 40
    local slot=config and config.slot
    if limit and G.Number(slot) and slot==math.floor(slot) and slot>=1 and slot<=limit then return (kind=="party_member" and "party" or kind=="nameplate" and "nameplate" or "raid")..slot end
end
-- A positive readable relationship is required for filtered collections. A
-- protected/absent/error result never means hostile, friendly or neutral.
function P.MatchesRelation(api,unit,relation)
    if protected(unit,api) or protected(relation,api) then return false,"protected" end
    if not P.ValidToken(unit) then return false,"invalid unit" end
    if relation=="ALL" then return true,"all" end
    local fn=relation=="FRIENDLY" and api.UnitIsFriend or relation=="HOSTILE" and api.UnitCanAttack
    if type(fn)~="function" then return false,"unsupported" end
    local ok,value=pcall(fn,"player",unit)
    if not ok then return false,"error" end
    if protected(value,api) then return false,"protected" end
    if type(value)~="boolean" then return false,"unavailable" end
    return value,value and "matched" or "filtered"
end
P.queryDefaults={spellName="",damageClass=0,spellID=0,auraIndex=1,controlIndex=1,statIndex=1,interactionIndex=1}
function P.Options(config)
    local out={};for key,value in pairs(P.queryDefaults) do out[key]=config and config[key] or value end;return out
end
function P.Key(unit,config)
    local options=P.Options(config);local changed=false;local bits={unit}
    for _,key in ipairs({"spellID","spellName","damageClass","auraIndex","controlIndex","statIndex","interactionIndex"}) do
        local value=tostring(options[key]);bits[#bits+1]=#value.."="..value;changed=changed or options[key]~=P.queryDefaults[key]
    end
    return changed and table.concat(bits,":") or unit
end
function P.New(api)
    api=api or _G
    local source=A.UnitData.New(api)
    local playerSource
    local derived=P.presentationFields
    local function enrich(result,requested)
        local values,status=result.values,result.fields
        local token=values.classToken
        local function set(key,value,why) if requested[key] then values[key]=value;status[key]=value~=nil and "readable" or (why~="readable" and why or nil) or "unavailable" end end
        local readable=not protected(token,api) and type(token)=="string" and token:match("^[A-Z]+$")
        if requested.classIcon then set("classIcon",readable and BVAddonSuiteCore.DisplayModel.New("icon",{atlas="classicon-"..token}) or nil,status.classToken) end
        if requested.roleIcon then
            local role=values.groupRolesAssigned
            local atlases={TANK="UI-LFG-RoleIcon-Tank",HEALER="UI-LFG-RoleIcon-Healer",DAMAGER="UI-LFG-RoleIcon-DPS"}
            local atlas=not protected(role,api) and type(role)=="string" and atlases[role]
            set("roleIcon",atlas and BVAddonSuiteCore.DisplayModel.New("icon",{atlas=atlas}) or nil,status.groupRolesAssigned=="protected" and "protected" or "unavailable")
        end
        if requested.classColor or requested.classRed or requested.classGreen or requested.classBlue then
            local r,g,b;local why=status.classToken
            if readable then
                local ok,color=pcall(function() return api.C_ClassColor and api.C_ClassColor.GetClassColor and api.C_ClassColor.GetClassColor(token) end)
                if ok and color and not protected(color,api) then
                    local accessOK,accessible=true,true
                    if api.canaccesstable then accessOK,accessible=pcall(api.canaccesstable,color) end
                    if accessOK and accessible==true then
                        ok,r,g,b=pcall(function() return color:GetRGB() end)
                        if not ok then r,g,b=nil,nil,nil end
                    end
                end
                if protected(r,api) or protected(g,api) or protected(b,api) then r,g,b=nil,nil,nil;why="protected"
                elseif not (G.Number(r) and G.Number(g) and G.Number(b) and r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1) then r,g,b=nil,nil,nil;why="unavailable" end
            end
            set("classRed",r,why);set("classGreen",g,why);set("classBlue",b,why)
            set("classColor",r and string.format("%02X%02X%02X",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5)),why)
        end
        for _,key in ipairs({"classToken","groupRolesAssigned"}) do if not requested[key] then values[key]=nil;status[key]=nil end end
    end
    return {Capture=function(_,requested,unit,options)
        unit=unit or "player";assert(P.ValidToken(unit),"Unsupported unit selector")
        requested=requested or {}
        local fields={exists=true};for key in pairs(requested) do if key~="instance" and key~="castSucceeded" and key~="succeededSpellID" and not derived[key] and not P.playerFields[key] then fields[key]=true end end
        if requested.classIcon or requested.classColor or requested.classRed or requested.classGreen or requested.classBlue then fields.classToken=true end
        if requested.roleIcon then fields.groupRolesAssigned=true end
        options=options or {};options.liveExistence=true
        local result=source:Capture(unit,fields,options)
        enrich(result,requested)
        local observations={}
        for _,key in ipairs(P.playerFieldOrder) do
            if requested[key] then
                local field=P.playerFields[key]
                if unit~="player" then result.fields[key]="unsupported"
                else
                    if not observations[field.kind] then
                        playerSource=playerSource or A.DataSource.New(api)
                        local ok,observation=pcall(playerSource.Observe,playerSource,field.kind,{})
                        observations[field.kind]=ok and observation or {values={},fields={},status="error"}
                    end
                    local observation=observations[field.kind]
                    result.values[key]=observation.values[field.field]
                    result.fields[key]=observation.fields[field.field] or observation.status or "unavailable"
                end
            end
        end
        if not (requested and requested.exists) then result.values.exists=nil;result.fields.exists=nil end
        return result
    end}
end
