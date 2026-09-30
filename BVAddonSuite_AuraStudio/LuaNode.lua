-- Lua Script node (in-game finding 53, decided by Florian 2026-09-27): the
-- player writes a small Lua function. Up to four typed inputs arrive as
-- in1..in4, the code returns up to four typed outputs in order.
-- Safety model:
-- * Restricted environment: only the inputs, a per-node `memory` table,
--   math/string/table, basic functions and a whitelist of read-only game
--   API. No _G, no loadstring, no frame or protected functions.
-- * Every run is wrapped in pcall; an error faults the node (red card, the
--   runtime's retry/pause rules apply).
-- * Time: WoW offers no way to interrupt running Lua, so a run is measured
--   afterwards; a run over the limit faults the node. An endless loop would
--   still freeze the client - the wiki says so plainly.
-- * Imports and blocks reset "Allow running code" (Messaging.ResetPermissions);
--   the code stays visible and runs only after the player enables it.
-- * Protected actions (target, cast, ...) stay impossible, as for all addon
--   code.
-- This is the only file that may call loadstring (check.py guard).
local _,A=...
if A.blocked then return end
local G=A.G
local L={maxCode=4000,maxPorts=4,maxText=4000,slowMs=10};A.LuaNode=L
local types={"boolean","integer","float","string","timestamp"}
local typeLabels={boolean="Boolean",integer="Integer",float="Number",string="Text",timestamp="Timestamp"}
local known={};for _,t in ipairs(types) do known[t]=true end
local function default(kind) if kind=="boolean" then return false elseif kind=="string" then return "" else return 0 end end
local function port(kind,label,value,order) return {type=kind,label=label,default=value,order=order,optional=true,required=false} end
-- Read-only game functions the code may call (missing ones stay nil).
L.api={"GetTime","time","date","UnitName","UnitGUID","UnitExists","UnitIsDead","UnitIsGhost","UnitIsPlayer","UnitIsFriend","UnitIsEnemy",
    "UnitClass","UnitRace","UnitLevel","UnitHealth","UnitHealthMax","UnitPower","UnitPowerMax","UnitPowerType","UnitAffectingCombat",
    "UnitInParty","UnitInRaid","UnitIsUnit","InCombatLockdown","IsInGroup","IsInRaid","GetNumGroupMembers","GetZoneText","GetSubZoneText",
    "GetRealZoneText","GetMoney","GetSpellInfo","GetItemInfo","GetItemCount","IsMounted","IsResting","GetFramerate"}
local function copy(t) local o={};for k,v in pairs(t) do o[k]=v end;return o end
function L.Environment()
    local env={pairs=pairs,ipairs=ipairs,next=next,select=select,tonumber=tonumber,tostring=tostring,type=type,unpack=unpack,
        error=error,assert=assert,math=copy(math),string=copy(string),table=copy(table),memory={}}
    env.string.dump=nil
    for _,name in ipairs(L.api) do local f=_G[name];if type(f)=="function" then env[name]=f end end
    return env
end
-- "Lua Script:3: message" -> "Line 3: message".
function L.Clean(message)
    message=tostring(message or "error")
    return (message:gsub("^%[?[^:]*Lua Script%]?:(%d+):%s*","Line %1: "))
end
-- Inputs arrive as in1..in4 on the first line, so line numbers stay exact.
function L.Compile(code)
    if type(code)~="string" or #code>L.maxCode then return nil,"Code must be text of at most "..L.maxCode.." bytes" end
    local fn,why=loadstring("local in1,in2,in3,in4=...;"..code,"=Lua Script")
    if not fn then return nil,L.Clean(why) end
    return fn
end
local checked,checkedCount={},0
local function syntaxError(code)
    local hit=checked[code];if hit~=nil then return hit or nil end
    local _,why=L.Compile(code)
    if checkedCount>64 then checked,checkedCount={},0 end
    checked[code]=why or false;checkedCount=checkedCount+1
    return why
end
function L.CheckValue(kind,v)
    if v==nil then return true end
    if kind=="boolean" then return type(v)=="boolean","must be true or false" end
    if type(v)~="number" and kind~="string" then return false,"must be a number" end
    if kind=="integer" then return v==v and v~=math.huge and v~=-math.huge and v%1==0,"must be a whole number" end
    if kind=="float" or kind=="timestamp" then return v==v and v~=math.huge and v~=-math.huge,"must be a finite number" end
    if kind=="string" then return type(v)=="string" and #v<=L.maxText,"must be text of at most "..L.maxText.." bytes" end
    return false,"has an unknown type"
end
local base={label="Lua Script",flowOperation="lua",category="logic",keywords="lua code script custom programming function",
    inputs={},outputs={},
    defaults={code="-- in1 .. in4 are the inputs. Return the outputs in order.\nreturn in1",inputs=1,outputs=1,
        in1="string",in2="string",in3="string",in4="string",out1="string",out2="string",out3="string",out4="string",permission=true},
    help="Write a small Lua function: the inputs arrive as in1..in4, return the outputs in order (return a, b). "
        .."It runs whenever an input changes. Available: math, string, table, memory (a table kept between runs of this node) and read-only game functions such as UnitHealth, UnitName, GetTime. "
        .."No global variables, frames or protected actions. Errors and runs over "..L.slowMs.." ms mark the node red. "
        .."Imported code is shown but switched off until you enable Allow running code. An endless loop freezes the game; WoW cannot interrupt it."}
base.resolve=function(c)
    if not G.Number(c.inputs) or c.inputs%1~=0 or c.inputs<0 or c.inputs>L.maxPorts then return nil,"Inputs must be 0..4" end
    if not G.Number(c.outputs) or c.outputs%1~=0 or c.outputs<1 or c.outputs>L.maxPorts then return nil,"Outputs must be 1..4" end
    for i=1,L.maxPorts do if not known[c["in"..i]] or not known[c["out"..i]] then return nil,"Choose a type for every port" end end
    if type(c.permission)~="boolean" then return nil,"Allow running code must be on or off" end
    local why=syntaxError(c.code);if why then return nil,why end
    local d=G.Copy(base);d.resolve=nil
    d.fields={{key="permission",label="Allow running code",type="boolean"},
        {key="inputs",label="Inputs (0..4)",type="integer",advanced=true},{key="outputs",label="Outputs (1..4)",type="integer",advanced=true}}
    for i=1,c.inputs do
        d.inputs["in"..i]=port(c["in"..i],"in"..i.." ("..typeLabels[c["in"..i]]..")",default(c["in"..i]),i)
        d.fields[#d.fields+1]={key="in"..i,label="in"..i.." type",choices=types,choiceLabels=typeLabels,advanced=true}
    end
    for i=1,c.outputs do
        d.outputs["out"..i]=port(c["out"..i],"out"..i.." ("..typeLabels[c["out"..i]]..")",nil,i)
        d.fields[#d.fields+1]={key="out"..i,label="out"..i.." type",choices=types,choiceLabels=typeLabels,advanced=true}
    end
    d.outputs.status=port("string","Status",nil,L.maxPorts+1)
    return d
end
A.catalog.lua_script=base;A.order[#A.order+1]="lua_script"
function L.Evaluate(run,id,n,def,state,resolve,context,now)
    local c=n.config
    if c.permission~=true then
        local out={status="code disabled"};return out,"code disabled: review it, then enable Allow running code"
    end
    -- One compiled function and environment per node; recompiled on edits.
    if state.luaCode~=c.code or not state.luaFn then
        local fn,why=L.Compile(c.code);if not fn then error(why,0) end
        state.luaEnv=L.Environment();setfenv(fn,state.luaEnv);state.luaFn=fn;state.luaCode=c.code
    end
    local args={}
    for i=1,c.inputs do args[i]=resolve("in"..i) end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    local results={pcall(state.luaFn,args[1],args[2],args[3],args[4])}
    local elapsed=clock and clock()-started or 0
    if not results[1] then error(L.Clean(results[2]),0) end
    if elapsed>L.slowMs then error(string.format("Code took %.1f ms (limit %d ms)",elapsed,L.slowMs),0) end
    local out={}
    for i=1,c.outputs do
        local v=results[i+1];local ok,why=L.CheckValue(c["out"..i],v)
        if not ok then error("out"..i.." "..why,0) end
        out["out"..i]=v
    end
    out.status=string.format("ran in %.1f ms",elapsed)
    return out,"ran"
end
