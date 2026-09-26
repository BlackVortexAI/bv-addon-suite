-- Declarative click bindings. No graph evaluation executes a game action.
local _,ns=...
local A={};ns.Actions=A
local G,V=ns.GraphModel,ns.GraphValues
local function integer(n,lo,hi) return G.Number(n) and n==math.floor(n) and n>=lo and n<=hi end
local function one(v,list) return type(v)=="string" and list[v]==true end
local function name(v) return type(v)=="string" and #v>0 and #v<=128 and not v:find("[%c|]") end
local spellUnits={player=true,target=true,targettarget=true,focus=true,focustarget=true}
function A.Unit(v)
    if type(v)~="string" then return false end
    if spellUnits[v] or v=="pet" or v=="mouseover" then return true end
    local n=v:match("^party([1-4])$") or v:match("^raid([1-9][0-9]?)$")
    return n~=nil and tonumber(n)<=40
end
local fields={spell={spellID=true,unit=true},item={itemID=true,slot=true,unit=true},target={unit=true},assist={unit=true},focus={unit=true},
    macro={name=true,scope=true},pet={slot=true,unit=true},action={slot=true},cancelaura={spellID=true},
    raidtarget={marker=true,operation=true,unit=true},worldmarker={marker=true,operation=true},togglemenu={unit=true},ui={operation=true},group={operation=true,seconds=true}}
function A.Valid(v)
    if V.IsSecret(v) then return false end
    if type(v)=="table" and (getmetatable(v) or V.IsSecret(v.kind)) then return false end
    if type(v)=="table" and v.kind=="click" then
        if not V.PlainExcept(v,{payload="click"}) or type(v.key)~="string" or #v.key<1 or #v.key>40 or not v.key:match("^[%w_.%-]+$") then return false end
        for k in pairs(v) do if k~="kind" and k~="key" and k~="payload" then return false end end
        return v.payload==nil or V.Accepts("click",v.payload)
    end
    if type(v)=="table" and not V.IsSecret(v) and v.kind=="bindings" then
        if getmetatable(v) or type(v.bindings)~="table" or V.IsSecret(v.bindings) or getmetatable(v.bindings) then return false end
        for k in pairs(v) do if k~="kind" and k~="bindings" then return false end end
        local count=0
        for key,a in pairs(v.bindings) do
            if V.IsSecret(key) or V.IsSecret(a) or not A.bindings or not A.bindings[key] or type(a)~="table" or getmetatable(a) or V.IsSecret(a.kind) or a.kind=="bindings" or not A.Valid(a) then return false end
            count=count+1
        end
        return count>0 and count<=40
    end
    if not V.PlainExcept(v,{}) or type(v)~="table" or not fields[v.kind] then return false end
    for k in pairs(v) do if k~="kind" and not fields[v.kind][k] then return false end end
    local k=v.kind
    if k=="spell" then return integer(v.spellID,1,2147483647) and (spellUnits[v.unit]==true or A.Unit(v.unit) and (v.unit:match("^party")~=nil or v.unit:match("^raid")~=nil)) end
    if k=="item" then return (v.unit==nil or A.Unit(v.unit)) and ((v.slot==nil and integer(v.itemID,1,2147483647)) or (v.itemID==nil and integer(v.slot,1,19))) end
    if k=="target" then return v.unit=="none" or A.Unit(v.unit) end
    if k=="assist" or k=="focus" or k=="togglemenu" then return A.Unit(v.unit) end
    if k=="macro" then return name(v.name) and one(v.scope,{account=true,character=true}) end
    if k=="pet" then return integer(v.slot,1,10) and (v.unit==nil or A.Unit(v.unit)) end
    if k=="action" then return integer(v.slot,1,180) end
    if k=="cancelaura" then return integer(v.spellID,1,2147483647) end
    if k=="raidtarget" or k=="worldmarker" then return integer(v.marker,1,8) and one(v.operation,{set=true,clear=true,toggle=true}) and (k=="worldmarker" or A.Unit(v.unit)) end
    if k=="ui" then return one(v.operation,{character=true,spellbook=true,bags=true,map=true}) end
    if k=="group" then return one(v.operation,{readycheck=true,countdown=true}) and integer(v.seconds,1,3600) end
    return false
end
function A.Same(a,b)
    if not a or not b then return false end
    if a.kind=="bindings" or b.kind=="bindings" then return ns.DisplayModel.Equal(a,b) end
    for k,v in pairs(a) do if b[k]~=v then return false end end
    for k,v in pairs(b) do if a[k]~=v then return false end end
    return true
end
function A.Label(a)
    if a.kind=="bindings" then return "Action bindings" end
    if a.kind=="click" then return a.key end
    if a.kind=="spell" then return a.unit.." / Spell "..a.spellID end
    return a.kind.." / "..tostring(a.name or a.operation or a.itemID or a.slot or a.spellID or a.unit)
end
function A.Macros(fresh)
    if fresh then A.macroCache=nil end
    if A.macroCache then return A.macroCache end
    local list={}
    if type(GetMacroInfo)~="function" then return list end
    local c=Constants and Constants.MacroConsts
    local accounts=c and c.MAX_ACCOUNT_MACROS or 120;local characters=c and c.MAX_CHARACTER_MACROS or 30
    for i=1,accounts+characters do
        local ok,n,icon,body=pcall(GetMacroInfo,i)
        if ok and V.PlainExcept({n,icon,body},{}) and name(n) and type(body)=="string" then
            list[#list+1]={index=i,name=n,icon=icon,body=body,scope=i<=accounts and "account" or "character"}
        end
    end
    A.macroCache=list;return list
end
function A.FindMacro(n,scope,fresh)
    local found
    for _,m in ipairs(A.Macros(fresh)) do if m.name==n and m.scope==scope then
        if found then return nil,"Ambiguous macro name in this scope" end;found=m
    end end
    if found then return found end
    return nil,"Macro missing; select or create a saved macro"
end
-- Fresh, read-only presence check. An incomplete scan is never "missing".
-- Only names are inspected; macro bodies are neither compared nor returned.
function A.CheckMacro(n,scope)
    if V.IsSecret(n) or V.IsSecret(scope) or not name(n) or not one(scope,{account=true,character=true}) then return nil,"Invalid macro target" end
    if type(GetMacroInfo)~="function" then return nil,"Macro lookup unavailable" end
    local c=Constants and Constants.MacroConsts
    local accounts=c and c.MAX_ACCOUNT_MACROS or 120;local characters=c and c.MAX_CHARACTER_MACROS or 30
    if not integer(accounts,1,1000) or not integer(characters,1,1000) then return nil,"Macro limits unavailable" end
    local first,last=1,accounts
    if scope=="character" then first,last=accounts+1,accounts+characters end
    local found,count=nil,0
    for i=first,last do
        local ok,value=pcall(GetMacroInfo,i)
        if not ok or V.IsSecret(value) or (value~=nil and not name(value)) then return nil,"Macro lookup incomplete" end
        if value==n then found=i;count=count+1 end
    end
    if count>1 then return {exists=true},"Ambiguous macro name in this scope" end
    return {exists=count==1,index=found},count==1 and "found" or "missing"
end
-- Called by the explicit editor or an enabled fresh-event Write Macro node.
-- Snapshot comparison prevents
-- silently overwriting edits from Blizzard's editor or another addon.
function A.SaveMacro(snapshot,n,scope,body)
    if InCombatLockdown() then return nil,"Save macros outside combat" end
    if not name(n) or not one(scope,{account=true,character=true}) or type(body)~="string" or body:find("%z") then return nil,"Invalid macro data" end
    local letters=0;for _ in body:gmatch("[^\128-\191]") do letters=letters+1 end
    if letters>255 then return nil,"Macro text exceeds 255 characters" end
    local current,why=A.FindMacro(n,scope,true)
    if snapshot then
        if not current or not A.Same(current,snapshot) then return nil,"Macro changed externally; reload before saving" end
        if type(EditMacro)~="function" then return nil,"Macro editing unavailable" end
        local ok,result=pcall(EditMacro,current.index,nil,nil,body)
        if not ok then return nil,"Native macro edit failed: "..tostring(result) end
    else
        if current or why=="Ambiguous macro name in this scope" then return nil,"Name already exists in this scope" end
        local nameLetters=0;for _ in n:gmatch("[^\128-\191]") do nameLetters=nameLetters+1 end
        if nameLetters>16 then return nil,"Choose a name of at most 16 characters" end
        if type(CreateMacro)~="function" then return nil,"Macro creation unavailable" end
        local ok,result=pcall(CreateMacro,n,134400,body,scope=="character")
        if not ok then return nil,"Native macro creation failed: "..tostring(result) end
    end
    local saved,err=A.FindMacro(n,scope,true)
    if not saved or saved.body~=body then return nil,err or "Native macro text differs; reopen the saved macro" end
    return G.Copy(saved)
end
function A.Prepare(a)
    if not A.Valid(a) then return nil,"Invalid action" end
    local k=a.kind;local attrs={["*type1"]=k,unit=a.unit}
    if k=="spell" then attrs.spell=a.spellID
    elseif k=="item" then attrs.item=a.itemID and "item:"..a.itemID or tostring(a.slot)
    elseif k=="macro" then local m,why=A.FindMacro(a.name,a.scope);if not m then return nil,why end;attrs.macro=m.index
    elseif k=="pet" or k=="action" then attrs.action=a.slot
    elseif k=="cancelaura" then
        local ok,info=pcall(function() return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(a.spellID) end)
        if not ok or V.IsSecret(info) or type(info)~="table" then return nil,"Spell name unavailable" end
        local n=info.name
        if V.IsSecret(n) or not name(n) then return nil,"Spell name unavailable" end;attrs.spell=n;attrs.unit="player"
    elseif k=="raidtarget" or k=="worldmarker" then attrs.marker=a.marker;attrs.action=a.operation
    elseif k=="ui" or k=="group" or k=="click" then return {},nil,"local" end
    if k=="focus" and type(FocusUnit)~="function" then return nil,"Focus unavailable on this client" end
    return attrs,nil,"secure"
end
-- Ordinary UI/group actions run synchronously from a hardware click only.
function A.ExecuteLocal(a)
    if InCombatLockdown() then return false,"Available outside combat" end
    if not A.Valid(a) then return false,"Invalid action" end
    local fn,arg
    if a.kind=="ui" then
        if a.operation=="character" then fn,arg=ToggleCharacter,"PaperDollFrame"
        elseif a.operation=="spellbook" then fn=PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame
        elseif a.operation=="bags" then fn=ToggleAllBags elseif a.operation=="map" then fn=ToggleWorldMap end
    elseif a.kind=="group" then
        if not IsInGroup or not IsInGroup() or not ((UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then return false,"Requires group leader or assistant" end
        if C_PartyInfo then
            if a.operation=="readycheck" then fn=C_PartyInfo.DoReadyCheck else fn=C_PartyInfo.DoCountdown end
        end
        if a.operation=="countdown" then arg=a.seconds end
    else return false,"Not a direct UI action" end
    if type(fn)~="function" then return false,"Action unavailable on this client" end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then return false,"Native action rejected" end
    return true,"ready"
end
