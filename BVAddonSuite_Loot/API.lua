local _,L=...
if not L.ready then return end
-- Public interface for DKP/loot council addons (global BVLoot). Everything a
-- caller receives is a copy; providers and callbacks run protected, so a
-- faulty integration never stops rolls, awards or the windows.
local ns=L.ns
local I={tooltips={},tooltipOrder={},buttons={},buttonOrder={},callbacks={}}
L.Integrations=I
local EVENTS={RollStarted="ROLL_STARTED",RollUpdated="ROLL_UPDATED",RollFinished="ROLL_FINISHED",
    ItemAwarded="ITEM_AWARDED",LootReceived="LOOT_RECEIVED",RollRequested="ROLL_REQUESTED"}
local function validID(id) return type(id)=="string" and id:match("^[%w_%-%.:]+$") and #id<=64 end

function I.Snapshot(roll)
    if type(roll)~="table" then return nil end
    local out={key=roll.key,kind=roll.kind,id=roll.id,link=roll.link,itemID=roll.itemID,name=roll.name,quality=roll.quality,
        owner=roll.owner,winner=roll.winner,done=roll.done==true,reason=roll.reason,options={},entries={},targets={},
        custom=roll.custom and {label=roll.custom.label,symbol=roll.custom.symbol} or nil}
    for i,option in ipairs(roll.options or {}) do out.options[i]=option end
    for i,name in ipairs(roll.targetList or {}) do out.targets[i]=name end
    for i,entry in ipairs(L.Rolls:Ranking(roll)) do
        out.entries[i]={name=entry.name,class=entry.class,choice=entry.choice,value=entry.value,manual=entry.manual==true}
    end
    return out
end
local function copyContext(context)
    local out={}
    for k,v in pairs(context or {}) do out[k]=type(v)=="table" and k~="roll" and I.Copy(v) or v end
    if context and context.roll and context.roll.key then out.roll=I.Snapshot(context.roll) end
    return out
end
function I.Copy(value)
    if type(value)~="table" then return value end
    local out={}
    for k,v in pairs(value) do out[k]=I.Copy(v) end
    return out
end

-- Tooltip sections: provider(context) -> nil | {title=string, lines={string | {left,right,r,g,b}}}
function I:Sections(context)
    local out={}
    for _,id in ipairs(self.tooltipOrder) do
        local provider=self.tooltips[id]
        if provider then
            local ok,section=ns:Call("loot/tooltip/"..id,provider,copyContext(context))
            if ok and type(section)=="table" and type(section.lines)=="table" then
                local lines={}
                for _,line in ipairs(section.lines) do
                    if type(line)=="string" then lines[#lines+1]={left=line}
                    elseif type(line)=="table" and (type(line[1])=="string" or type(line.left)=="string") then
                        lines[#lines+1]={left=line.left or line[1],right=line.right or line[2],r=line.r or line[3],g=line.g or line[4],b=line.b or line[5]}
                    end
                    if #lines>=12 then break end
                end
                if #lines>0 then out[#out+1]={title=type(section.title)=="string" and section.title or id,lines=lines} end
            end
        end
    end
    return out
end
-- Buttons: where = "master" (master loot window) or "candidate" (row menu).
function I:Buttons(where)
    local out={}
    for _,id in ipairs(self.buttonOrder) do
        local def=self.buttons[id]
        if def and def.where==where then out[#out+1]=def end
    end
    return out
end
function I:Click(def,context)
    ns:Call("loot/button/"..def.id,def.onClick,copyContext(context))
end
function I:Dispatch(event,...)
    local public=EVENTS[event]
    local list=public and self.callbacks[public]
    if not list then return end
    local args={...}
    for i,v in ipairs(args) do if type(v)=="table" and v.key then args[i]=I.Snapshot(v) end end
    for _,callback in ipairs(list) do ns:Call("loot/callback/"..public,callback,public,unpack(args)) end
end
for event in pairs(EVENTS) do L:On(event,I,function(...) I:Dispatch(event,...) end) end

local public={apiVersion=1}
BVLoot=public
function public:RegisterTooltipProvider(id,provider)
    assert(validID(id) and type(provider)=="function","BVLoot: tooltip provider needs an id and a function")
    if not I.tooltips[id] then I.tooltipOrder[#I.tooltipOrder+1]=id end
    I.tooltips[id]=provider
end
function public:RegisterButton(id,def)
    assert(validID(id) and type(def)=="table" and type(def.label)=="string" and type(def.onClick)=="function","BVLoot: button needs an id, label and onClick")
    local where=def.where=="candidate" and "candidate" or "master"
    if not I.buttons[id] then I.buttonOrder[#I.buttonOrder+1]=id end
    I.buttons[id]={id=id,label=def.label,tooltip=type(def.tooltip)=="string" and def.tooltip or nil,where=where,onClick=def.onClick}
    if L.Master and L.Master.window then L.Master:Refresh() end
end
function public:Unregister(id)
    I.tooltips[id],I.buttons[id]=nil,nil
    for _,list in ipairs({I.tooltipOrder,I.buttonOrder}) do
        for i=#list,1,-1 do if list[i]==id then table.remove(list,i) end end
    end
    if L.Master and L.Master.window then L.Master:Refresh() end
end
function public:RegisterCallback(event,callback)
    local valid=false
    for _,name in pairs(EVENTS) do if name==event then valid=true end end
    assert(valid and type(callback)=="function","BVLoot: unknown callback event")
    I.callbacks[event]=I.callbacks[event] or {}
    table.insert(I.callbacks[event],callback)
end
function public:UnregisterCallback(event,callback)
    local list=I.callbacks[event] or {}
    for i=#list,1,-1 do if list[i]==callback then table.remove(list,i) end end
end
-- options: preset id ("need_greed", "need_off", "need") or a list of option ids.
-- custom: {label=reason, symbol=Lucide name} when options contain "custom".
function public:RequestRoll(link,players,options,duration,custom)
    if not L:Active() then return nil,"loot module is off" end
    if type(options)=="string" then options=L.PRESETS[options] end
    local roll,err=L.Rolls:Request(link,players,options,duration,type(custom)=="table" and custom or nil)
    if roll then L:Emit("RollRequested",roll) end
    return roll and roll.id,err
end
function public:GetRolls()
    local out={}
    for _,roll in ipairs(L.Rolls:List()) do out[#out+1]=I.Snapshot(roll) end
    return out
end
function public:IsMasterLooter() return L.IsMasterLooter() end
function public:IsEnabled() return L:Active() end
